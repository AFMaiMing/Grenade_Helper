import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import '../../models.dart';
import '../lan_sync/lan_sync_local_store.dart';
import '../media_handle_service.dart';
import 'data_sync_and_media_models.dart';
import 'package_archive_codec.dart';
import 'package_sync_helpers.dart';

class MediaCleanupDelegate {
  final Isar isar;

  MediaCleanupDelegate(this.isar);

  static String normalizeMediaPath(String rawPath) {
    return MediaHandleService.normalizePath(rawPath);
  }

  static Future<bool> deleteMediaFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      debugPrint('删除媒体文件失败: $e');
      return false;
    }
  }

  static Future<void> deleteMediaFiles(List<String> paths) async {
    final targets =
        paths.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (targets.isEmpty) return;
    await MediaHandleService.releasePaths(targets);
    for (final path in targets) {
      await deleteMediaFile(path);
    }
  }

  Future<MediaReferenceSnapshot> collectMediaReferenceSnapshot({
    Set<int> excludingMediaIds = const {},
  }) async {
    final liveReferencedPaths = <String>{};
    final liveStepIds = <int>{};
    final liveMediaIds = <int>{};

    void addLocalPath(String rawPath) {
      final trimmed = rawPath.trim();
      if (trimmed.isEmpty || isAssetPath(trimmed)) return;
      final normalized = normalizeMediaPath(trimmed);
      if (normalized.isNotEmpty) {
        liveReferencedPaths.add(normalized);
      }
    }

    final maps = await isar.gameMaps.where().findAll();
    for (final map in maps) {
      addLocalPath(map.backgroundPath);
      addLocalPath(map.iconPath);
      await map.layers.load();
      for (final layer in map.layers) {
        addLocalPath(layer.assetPath);
        await layer.grenades.load();
        for (final grenade in layer.grenades) {
          await grenade.steps.load();
          for (final step in grenade.steps) {
            liveStepIds.add(step.id);
            await step.medias.load();
            for (final media in step.medias) {
              liveMediaIds.add(media.id);
              if (!excludingMediaIds.contains(media.id)) {
                addLocalPath(media.localPath);
              }
            }
          }
        }
      }
    }

    final allSteps = await isar.grenadeSteps.where().findAll();
    final orphanStepIds = <int>[
      for (final step in allSteps)
        if (!liveStepIds.contains(step.id)) step.id,
    ];

    final allMedias = await isar.stepMedias.where().findAll();
    final orphanMediaIds = <int>[
      for (final media in allMedias)
        if (!liveMediaIds.contains(media.id)) media.id,
    ];

    return MediaReferenceSnapshot(
      liveReferencedPaths: liveReferencedPaths,
      liveStepIds: liveStepIds,
      liveMediaIds: liveMediaIds,
      orphanStepIds: orphanStepIds,
      orphanMediaIds: orphanMediaIds,
    );
  }

  Future<List<String>> deleteMediaFilesIfUnused(
    Iterable<String> localPaths, {
    Set<int> excludingMediaIds = const {},
  }) async {
    final uniqueByNormalized = <String, String>{};
    for (final raw in localPaths) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || isAssetPath(trimmed)) continue;
      final normalized = normalizeMediaPath(trimmed);
      if (normalized.isNotEmpty) {
        uniqueByNormalized.putIfAbsent(normalized, () => trimmed);
      }
    }
    if (uniqueByNormalized.isEmpty) return const [];

    final snapshot = await collectMediaReferenceSnapshot(
      excludingMediaIds: excludingMediaIds,
    );
    final pathsToDelete = <String>[
      for (final entry in uniqueByNormalized.entries)
        if (!snapshot.liveReferencedPaths.contains(entry.key)) entry.value,
    ];
    if (pathsToDelete.isEmpty) return const [];

    await MediaHandleService.releasePaths(pathsToDelete);
    final failedPaths = <String>[];
    for (final path in pathsToDelete) {
      final ok = await deleteMediaFile(path);
      if (!ok) {
        failedPaths.add(path);
      }
    }
    return failedPaths;
  }

  Future<bool> deleteMediaFileIfUnused(
    String localPath, {
    int? excludingMediaId,
  }) async {
    final trimmed = localPath.trim();
    if (trimmed.isEmpty || isAssetPath(trimmed)) return false;

    final normalized = normalizeMediaPath(trimmed);
    if (normalized.isEmpty) return false;

    final snapshot = await collectMediaReferenceSnapshot(
      excludingMediaIds:
          excludingMediaId == null ? const {} : {excludingMediaId},
    );
    if (snapshot.liveReferencedPaths.contains(normalized)) return false;

    await MediaHandleService.releasePaths([trimmed]);
    return deleteMediaFile(trimmed);
  }

  Future<bool> deleteStepMedia(StepMedia media) async {
    final oldPath = media.localPath.trim();
    await media.step.load();
    final step = media.step.value;
    Grenade? grenade;
    if (step != null) {
      await step.grenade.load();
      grenade = step.grenade.value;
    }

    await isar.writeTxn(() async {
      await isar.stepMedias.delete(media.id);
      if (grenade != null) {
        grenade.updatedAt = DateTime.now();
        await isar.grenades.put(grenade);
      }
    });

    if (oldPath.isEmpty) return true;
    return deleteMediaFileIfUnused(oldPath);
  }

  Future<List<String>> deleteStep(GrenadeStep step) async {
    await step.medias.load();
    await step.grenade.load();
    final grenade = step.grenade.value;
    final mediaIds = step.medias.map((m) => m.id).toList(growable: false);
    final mediaPaths = <String>{
      for (final media in step.medias)
        if (media.localPath.trim().isNotEmpty) media.localPath.trim(),
    };

    await isar.writeTxn(() async {
      if (mediaIds.isNotEmpty) {
        await isar.stepMedias.deleteAll(mediaIds);
      }
      await isar.grenadeSteps.delete(step.id);
      if (grenade != null) {
        grenade.updatedAt = DateTime.now();
        await isar.grenades.put(grenade);
      }
    });

    return deleteMediaFilesIfUnused(mediaPaths);
  }

  Future<OrphanMediaScanResult> scanOrphanMediaFiles() async {
    final dataPath = (isar.directory ?? '').trim();
    if (dataPath.isEmpty) {
      return const OrphanMediaScanResult(orphanFiles: []);
    }

    final dataDir = Directory(dataPath);
    if (!await dataDir.exists()) {
      return const OrphanMediaScanResult(orphanFiles: []);
    }

    final snapshot = await collectMediaReferenceSnapshot();
    final flutterAssetsDir =
        normalizeMediaPath(p.join(dataDir.path, 'flutter_assets'));

    final orphanFiles = <OrphanMediaFileEntry>[];
    await for (final entity
        in dataDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final extension = p.extension(entity.path).toLowerCase();
      if (!trackedMediaExtensions.contains(extension)) continue;

      final normalized = normalizeMediaPath(entity.path);
      if (normalized.isEmpty) continue;
      if (normalized == flutterAssetsDir ||
          p.isWithin(flutterAssetsDir, normalized)) {
        continue;
      }
      if (snapshot.liveReferencedPaths.contains(normalized)) continue;

      int sizeBytes = 0;
      try {
        sizeBytes = await entity.length();
      } catch (_) {}

      orphanFiles.add(
        OrphanMediaFileEntry(
          path: entity.path,
          sizeBytes: sizeBytes,
        ),
      );
    }

    orphanFiles.sort((a, b) => a.path.compareTo(b.path));
    return OrphanMediaScanResult(
      orphanFiles: orphanFiles,
      orphanStepIds: snapshot.orphanStepIds,
      orphanMediaIds: snapshot.orphanMediaIds,
    );
  }

  Future<OrphanMediaCleanupResult> cleanupOrphanMediaFiles(
    Iterable<OrphanMediaFileEntry> files, {
    List<int> orphanStepIds = const [],
    List<int> orphanMediaIds = const [],
  }) async {
    var deletedStepRecords = 0;
    var deletedMediaRecords = 0;
    if (orphanStepIds.isNotEmpty || orphanMediaIds.isNotEmpty) {
      await isar.writeTxn(() async {
        if (orphanMediaIds.isNotEmpty) {
          deletedMediaRecords = await isar.stepMedias.deleteAll(orphanMediaIds);
        }
        if (orphanStepIds.isNotEmpty) {
          deletedStepRecords = await isar.grenadeSteps.deleteAll(orphanStepIds);
        }
      });
    }

    final fileList = files.toList(growable: false);
    if (fileList.isNotEmpty) {
      await MediaHandleService.releasePaths(fileList.map((e) => e.path));
    }

    final deletedFiles = <OrphanMediaFileEntry>[];
    final failedFiles = <OrphanMediaFileEntry>[];

    for (final item in fileList) {
      final ok = await deleteMediaFile(item.path);
      if (ok) {
        deletedFiles.add(item);
      } else {
        failedFiles.add(item);
      }
    }

    return OrphanMediaCleanupResult(
      deletedFiles: deletedFiles,
      failedFiles: failedFiles,
      deletedStepRecords: deletedStepRecords,
      deletedMediaRecords: deletedMediaRecords,
    );
  }

  Future<int> deleteGrenades(
    List<Grenade> grenades, {
    bool recordSyncTombstones = true,
  }) async {
    if (grenades.isEmpty) return 0;

    final tombstones = <LanSyncGrenadeTombstoneEntry>[];
    final mediaPathsToCleanup = <String>{};
    for (final grenade in grenades) {
      await grenade.steps.load();
      for (final step in grenade.steps) {
        await step.medias.load();
      }
      await grenade.layer.load();
      final layer = grenade.layer.value;
      if (layer == null) continue;
      await layer.map.load();
      final map = layer.map.value;
      final uniqueId = (grenade.uniqueId ?? '').trim();
      final mapName = map?.name.trim() ?? '';
      if (recordSyncTombstones && uniqueId.isNotEmpty && mapName.isNotEmpty) {
        tombstones.add(LanSyncGrenadeTombstoneEntry(
          uniqueId: uniqueId,
          mapName: mapName,
          deletedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }

    for (final grenade in grenades) {
      for (final step in grenade.steps) {
        for (final media in step.medias) {
          final path = media.localPath.trim();
          if (path.isNotEmpty) {
            mediaPathsToCleanup.add(path);
          }
        }
      }
    }

    await isar.writeTxn(() async {
      for (final grenade in grenades) {
        for (final step in grenade.steps) {
          await isar.stepMedias
              .deleteAll(step.medias.map((media) => media.id).toList());
        }
        await isar.grenadeSteps
            .deleteAll(grenade.steps.map((step) => step.id).toList());
        await isar.grenades.delete(grenade.id);
      }
    });

    await deleteMediaFilesIfUnused(mediaPathsToCleanup);

    if (recordSyncTombstones && tombstones.isNotEmpty) {
      await LanSyncLocalStore().upsertGrenadeTombstones(tombstones);
    }
    return grenades.length;
  }

  Future<int> deleteAllGrenadesForMap(GameMap map) async {
    await map.layers.load();
    final grenades = <Grenade>[];
    for (final layer in map.layers) {
      await layer.grenades.load();
      grenades.addAll(layer.grenades.toList());
    }
    return deleteGrenades(grenades);
  }

  Future<void> deleteImpactGroup(
    ImpactGroup group, {
    bool recordSyncTombstone = true,
  }) async {
    MapLayer? layer;
    GameMap? map;
    if (recordSyncTombstone) {
      layer = await isar.mapLayers.get(group.layerId);
      if (layer != null) {
        await layer.map.load();
        map = layer.map.value;
      }
    }

    final grenades =
        await isar.grenades.filter().impactGroupIdEqualTo(group.id).findAll();
    await isar.writeTxn(() async {
      for (final g in grenades) {
        g.impactGroupId = null;
        g.updatedAt = DateTime.now();
        await isar.grenades.put(g);
      }
      await isar.impactGroups.delete(group.id);
    });

    if (recordSyncTombstone && map != null && layer != null) {
      final entityKey = buildImpactGroupTombstoneKey(
        mapName: map.name,
        layerName: layer.name,
        type: group.type,
        name: group.name,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
      );
      await LanSyncLocalStore().upsertEntityTombstones([
        LanSyncEntityTombstoneEntry(
          entityType: LanSyncEntityTombstoneType.impactGroup,
          entityKey: entityKey,
          mapName: map.name,
          deletedAt: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'name': group.name,
            'layerName': layer.name,
            'type': group.type,
            'impactXRatio': group.impactXRatio,
            'impactYRatio': group.impactYRatio,
          },
        ),
      ]);
    }
  }
}
