import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import '../lan_sync/lan_sync_local_store.dart';
import 'data_package_models.dart';
import 'data_sync_and_media_models.dart';
import 'lan_sync_package_builder.dart';
import 'package_sync_helpers.dart';

class PackageConflictCollector {
  final Isar isar;
  final LanSyncPackageBuilder lanSyncBuilder;

  PackageConflictCollector(this.isar, this.lanSyncBuilder);

  Future<ImportConflictBundle> collectTagConflicts(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds,
  ) async {
    if (preview.schemaVersion < 2 || preview.tagsByUuid.isEmpty) {
      return const ImportConflictBundle(tagConflicts: [], localTagByUuid: {});
    }

    final usedUuids = collectImportTagUuids(preview, selectedUniqueIds);
    if (usedUuids.isEmpty) {
      return const ImportConflictBundle(tagConflicts: [], localTagByUuid: {});
    }

    final tagMapNames = <String>{};
    for (final uuid in usedUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared != null && shared.mapName.isNotEmpty) {
        tagMapNames.add(shared.mapName);
      }
    }

    final context = await buildLocalTagContext(isar, tagMapNames);
    final conflicts = <TagConflictItem>[];

    for (final uuid in usedUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared == null) continue;
      final localByUuid = context.localByUuid[uuid];
      if (localByUuid != null) {
        final contentDifferent = isTagDifferent(localByUuid, shared);
        if (requiresManualConflictResolution(
          sharedUpdatedAtMs: shared.updatedAt,
          localUpdatedAtMs: localByUuid.updatedAt.millisecondsSinceEpoch,
          contentDifferent: contentDifferent,
        )) {
          conflicts.add(TagConflictItem(
            type: TagConflictType.uuidMismatch,
            sharedTag: shared,
            localTag: localByUuid,
          ));
        }
        continue;
      }

      final map = context.mapByName[shared.mapName];
      if (map == null) continue;
      final semanticKey = semanticTagKey(map.id, shared.dimension, shared.name);
      final semanticTag = context.localBySemantic[semanticKey];
      if (semanticTag != null) {
        final contentDifferent =
            isTagDifferent(semanticTag, shared) || semanticTag.tagUuid != uuid;
        if (requiresManualConflictResolution(
          sharedUpdatedAtMs: shared.updatedAt,
          localUpdatedAtMs: semanticTag.updatedAt.millisecondsSinceEpoch,
          contentDifferent: contentDifferent,
        )) {
          conflicts.add(TagConflictItem(
            type: TagConflictType.semanticMatch,
            sharedTag: shared,
            localTag: semanticTag,
          ));
        }
      }
    }

    return ImportConflictBundle(
      tagConflicts: conflicts,
      localTagByUuid: context.localByUuid,
    );
  }

  Future<List<AreaConflictGroup>> collectAreaConflicts(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    required Map<String, ImportTagConflictResolution> tagResolutions,
  }) async {
    if (preview.schemaVersion < 2 ||
        preview.areas.isEmpty ||
        preview.tagsByUuid.isEmpty) {
      return const [];
    }

    final usedUuids = collectImportTagUuids(preview, selectedUniqueIds)
      ..removeWhere((uuid) {
        final shared = preview.tagsByUuid[uuid];
        return shared == null || shared.dimension != TagDimension.area;
      });
    if (usedUuids.isEmpty) return const [];

    final tagMapNames = <String>{};
    for (final uuid in usedUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared != null && shared.mapName.isNotEmpty) {
        tagMapNames.add(shared.mapName);
      }
    }
    final context = await buildLocalTagContext(isar, tagMapNames);

    final groupLayers = <String, Set<String>>{};

    for (final tagUuid in usedUuids) {
      final sharedTag = preview.tagsByUuid[tagUuid];
      if (sharedTag == null) continue;

      Tag? localTag = context.localByUuid[tagUuid];
      final map = context.mapByName[sharedTag.mapName];
      if (map == null) continue;

      if (localTag == null) {
        final semanticKey =
            semanticTagKey(map.id, sharedTag.dimension, sharedTag.name);
        final semanticTag = context.localBySemantic[semanticKey];
        if (semanticTag != null) {
          final resolution = tagResolutions[tagUuid];
          if (resolution == ImportTagConflictResolution.local ||
              resolution == ImportTagConflictResolution.shared) {
            localTag = semanticTag;
          }
        }
      }
      if (localTag == null) continue;

      await map.layers.load();
      final layerIdByName = <String, int>{
        for (final l in map.layers) l.name: l.id,
      };

      final existingAreas = await isar.mapAreas
          .filter()
          .mapIdEqualTo(map.id)
          .tagIdEqualTo(localTag.id)
          .findAll();

      final tagAreas = preview.areas.where((a) =>
          a.tagUuid == tagUuid &&
          a.mapName == sharedTag.mapName &&
          a.layerName.isNotEmpty);
      for (final area in tagAreas) {
        final layerId = layerIdByName[area.layerName];
        if (layerId == null) continue;
        final sameLayerAreas = existingAreas
            .where((a) => a.layerId == layerId)
            .toList(growable: false);
        if (sameLayerAreas.isEmpty) continue;
        final hasEquivalent = sameLayerAreas.any(
          (localArea) => isSharedAreaEquivalent(localArea, area),
        );
        if (hasEquivalent) continue;

        sameLayerAreas.sort((a, b) {
          if (a.updatedAt.isAfter(b.updatedAt)) return -1;
          if (a.updatedAt.isBefore(b.updatedAt)) return 1;
          return b.id.compareTo(a.id);
        });
        final target = sameLayerAreas.first;
        final contentDifferent = !isSharedAreaEquivalent(target, area);
        if (!requiresManualConflictResolution(
          sharedUpdatedAtMs: area.updatedAt,
          localUpdatedAtMs: target.updatedAt.millisecondsSinceEpoch,
          contentDifferent: contentDifferent,
        )) {
          continue;
        }

        final key = '$tagUuid|${sharedTag.name}|${sharedTag.mapName}';
        groupLayers.putIfAbsent(key, () => <String>{}).add(area.layerName);
      }
    }

    final groups = <AreaConflictGroup>[];
    for (final entry in groupLayers.entries) {
      final parts = entry.key.split('|');
      groups.add(AreaConflictGroup(
        tagUuid: parts[0],
        tagName: parts[1],
        mapName: parts[2],
        layers: (entry.value.toList()..sort()),
      ));
    }
    groups.sort((a, b) => a.tagName.compareTo(b.tagName));
    return groups;
  }

  Future<ImportConflictNotice> collectImportConflictNotice(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    ImportPackageMode mode = ImportPackageMode.normal,
  }) async {
    final allowAppliedTombstones =
        mode == ImportPackageMode.lanSync && preview.canApplyTombstones;
    final newerLocalGrenades = <GrenadePreviewItem>[];
    for (final mapItems in preview.grenadesByMap.values) {
      for (final item in mapItems) {
        if (!selectedUniqueIds.contains(item.uniqueId)) continue;
        if (item.status == ImportStatus.skip) {
          newerLocalGrenades.add(item);
        }
      }
    }

    final newerLocalDeleteConflicts = <GrenadePreviewItem>[];
    if (allowAppliedTombstones && preview.grenadeTombstones.isNotEmpty) {
      final localItems =
          await lanSyncBuilder.loadLocalGrenadePreviewItemsByUniqueIds(
        preview.grenadeTombstones.map((e) => e.uniqueId),
      );
      for (final tombstone in preview.grenadeTombstones) {
        final local = localItems[tombstone.uniqueId];
        if (local == null) continue;
        final deletedAt =
            DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
        if (local.updatedAt.isAfter(deletedAt)) {
          newerLocalDeleteConflicts.add(local);
        }
      }
    }

    final newerLocalFavoriteFolderDeletes = <String>[];
    final favoriteFolderTombstones = allowAppliedTombstones
        ? preview.entityTombstones
            .where((e) =>
                e.entityType == LanSyncEntityTombstoneType.favoriteFolder)
            .toList(growable: false)
        : const <PackageEntityTombstoneData>[];
    if (favoriteFolderTombstones.isNotEmpty) {
      final mapNames =
          favoriteFolderTombstones.map((e) => e.mapName).toSet().toList();
      final mapByName = <String, GameMap>{};
      for (final mapName in mapNames) {
        final map =
            await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
        if (map != null) {
          mapByName[mapName] = map;
        }
      }
      for (final tombstone in favoriteFolderTombstones) {
        final map = mapByName[tombstone.mapName];
        final nameKey = normalizeFolderNameKey(
            tombstone.payload['nameKey'] as String? ?? '');
        if (map == null || nameKey.isEmpty) continue;
        final folders =
            await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
        final local = folders.where((folder) {
          final localKey = folder.nameKey.trim().isEmpty
              ? normalizeFolderNameKey(folder.name)
              : normalizeFolderNameKey(folder.nameKey);
          return localKey == nameKey;
        }).firstOrNull;
        if (local == null) continue;
        final deletedAt =
            DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
        if (local.updatedAt.isAfter(deletedAt)) {
          newerLocalFavoriteFolderDeletes
              .add('${tombstone.mapName} / ${local.name}');
        }
      }
    }

    return ImportConflictNotice(
      newerLocalGrenades: newerLocalGrenades,
      newerLocalDeleteConflicts: newerLocalDeleteConflicts,
      newerLocalFavoriteFolderDeletes: newerLocalFavoriteFolderDeletes,
    );
  }
}
