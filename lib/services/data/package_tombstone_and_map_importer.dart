import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/builtin_maps.dart';
import '../../models.dart';
import '../../models/grenade_tag.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import '../favorite_folder_service.dart';
import '../lan_sync/lan_sync_local_store.dart';
import 'data_package_models.dart';
import 'data_sync_and_media_models.dart';
import 'media_cleanup_delegate.dart';
import 'package_archive_codec.dart';
import 'package_sync_helpers.dart';

class PackageTombstoneAndMapImporter {
  final Isar isar;
  final MediaCleanupDelegate mediaCleanupDelegate;

  PackageTombstoneAndMapImporter(this.isar, this.mediaCleanupDelegate);

  Future<({int deletedCount, int skippedCount})> applyGrenadeTombstones(
    PackagePreviewResult preview,
  ) async {
    if (preview.grenadeTombstones.isEmpty) {
      return (deletedCount: 0, skippedCount: 0);
    }

    final allGrenades = await isar.grenades.where().findAll();
    final grenadeByUniqueId = <String, Grenade>{};
    for (final grenade in allGrenades) {
      final uniqueId = (grenade.uniqueId ?? '').trim();
      if (uniqueId.isNotEmpty) {
        grenadeByUniqueId[uniqueId] = grenade;
      }
    }

    final toDelete = <Grenade>[];
    var skippedCount = 0;
    for (final tombstone in preview.grenadeTombstones) {
      final grenade = grenadeByUniqueId[tombstone.uniqueId];
      if (grenade == null) continue;
      final deletedAt =
          DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
      if (grenade.updatedAt.isAfter(deletedAt)) {
        skippedCount++;
        continue;
      }
      toDelete.add(grenade);
    }

    final deletedCount = await mediaCleanupDelegate.deleteGrenades(
      toDelete,
      recordSyncTombstones: false,
    );
    return (deletedCount: deletedCount, skippedCount: skippedCount);
  }

  Future<EntityTombstoneApplyResult> applyEntityTombstones(
    PackagePreviewResult preview,
  ) async {
    if (preview.entityTombstones.isEmpty) {
      return const EntityTombstoneApplyResult(
        deletedCount: 0,
        skippedCount: 0,
      );
    }

    final deletedByType = <String, int>{};
    final skippedByType = <String, int>{};

    void markDeleted(String type) {
      deletedByType[type] = (deletedByType[type] ?? 0) + 1;
    }

    void markSkipped(String type) {
      skippedByType[type] = (skippedByType[type] ?? 0) + 1;
    }

    final mapByName = <String, GameMap>{};
    Future<GameMap?> resolveMap(String mapName) async {
      final key = mapName.trim();
      if (key.isEmpty) return null;
      final existing = mapByName[key];
      if (existing != null) return existing;
      final map = await isar.gameMaps.filter().nameEqualTo(key).findFirst();
      if (map != null) {
        mapByName[key] = map;
      }
      return map;
    }

    for (final tombstone in preview.entityTombstones) {
      switch (tombstone.entityType) {
        case LanSyncEntityTombstoneType.tag:
          final tagUuid =
              (tombstone.payload['tagUuid'] as String? ?? tombstone.entityKey)
                  .trim();
          if (tagUuid.isEmpty) continue;
          final tag =
              await isar.tags.filter().tagUuidEqualTo(tagUuid).findFirst();
          if (tag == null) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (tag.updatedAt.isAfter(deletedAt)) {
            markSkipped(tombstone.entityType);
            continue;
          }
          final deleteRelatedAreas =
              tombstone.payload['deleteRelatedAreas'] == true;
          await isar.writeTxn(() async {
            await isar.grenadeTags.filter().tagIdEqualTo(tag.id).deleteAll();
            if (deleteRelatedAreas) {
              await isar.mapAreas.filter().tagIdEqualTo(tag.id).deleteAll();
            }
            await isar.tags.delete(tag.id);
          });
          markDeleted(tombstone.entityType);
          break;
        case LanSyncEntityTombstoneType.area:
          final tagUuid =
              (tombstone.payload['tagUuid'] as String? ?? '').trim();
          final layerName =
              (tombstone.payload['layerName'] as String? ?? '').trim();
          final map = await resolveMap(tombstone.mapName);
          if (tagUuid.isEmpty || layerName.isEmpty || map == null) continue;
          final tag =
              await isar.tags.filter().tagUuidEqualTo(tagUuid).findFirst();
          if (tag == null || tag.mapId != map.id) continue;
          await map.layers.load();
          final layer = map.layers
              .where((item) => item.name.trim() == layerName)
              .firstOrNull;
          if (layer == null) continue;
          final matchedAreas = await isar.mapAreas
              .filter()
              .mapIdEqualTo(map.id)
              .tagIdEqualTo(tag.id)
              .and()
              .layerIdEqualTo(layer.id)
              .findAll();
          if (matchedAreas.isEmpty) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (matchedAreas.any((item) => item.updatedAt.isAfter(deletedAt))) {
            markSkipped(tombstone.entityType);
            continue;
          }
          await isar.writeTxn(() async {
            await isar.mapAreas
                .deleteAll(matchedAreas.map((item) => item.id).toList());
          });
          markDeleted(tombstone.entityType);
          break;
        case LanSyncEntityTombstoneType.favoriteFolder:
          final map = await resolveMap(tombstone.mapName);
          final nameKey = normalizeFolderNameKey(
              tombstone.payload['nameKey'] as String? ?? '');
          if (map == null || nameKey.isEmpty) continue;
          final folders = await isar.favoriteFolders
              .filter()
              .mapIdEqualTo(map.id)
              .findAll();
          final folder = folders.where((item) {
            final localKey = item.nameKey.trim().isEmpty
                ? normalizeFolderNameKey(item.name)
                : normalizeFolderNameKey(item.nameKey);
            return localKey == nameKey;
          }).firstOrNull;
          if (folder == null) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (folder.updatedAt.isAfter(deletedAt)) {
            markSkipped(tombstone.entityType);
            continue;
          }
          final folderService = FavoriteFolderService(isar);
          await folderService.deleteFolder(
            folder.id,
            FavoriteFolderDeleteStrategy.unfavorite,
            recordSyncTombstone: false,
          );
          markDeleted(tombstone.entityType);
          break;
        case LanSyncEntityTombstoneType.impactGroup:
          final map = await resolveMap(tombstone.mapName);
          final layerName =
              (tombstone.payload['layerName'] as String? ?? '').trim();
          final name = (tombstone.payload['name'] as String? ?? '').trim();
          final type = tombstone.payload['type'] as int?;
          final impactXRatio =
              (tombstone.payload['impactXRatio'] as num?)?.toDouble();
          final impactYRatio =
              (tombstone.payload['impactYRatio'] as num?)?.toDouble();
          if (map == null ||
              layerName.isEmpty ||
              name.isEmpty ||
              type == null ||
              impactXRatio == null ||
              impactYRatio == null) {
            continue;
          }
          await map.layers.load();
          final layer = map.layers
              .where((item) => item.name.trim() == layerName)
              .firstOrNull;
          if (layer == null) continue;
          final groups = await isar.impactGroups
              .filter()
              .layerIdEqualTo(layer.id)
              .findAll();
          final targetKey = buildImpactGroupTombstoneKey(
            mapName: map.name,
            layerName: layer.name,
            type: type,
            name: name,
            impactXRatio: impactXRatio,
            impactYRatio: impactYRatio,
          );
          final group = groups.where((item) {
            final currentKey = buildImpactGroupTombstoneKey(
              mapName: map.name,
              layerName: layer.name,
              type: item.type,
              name: item.name,
              impactXRatio: item.impactXRatio,
              impactYRatio: item.impactYRatio,
            );
            return currentKey == targetKey;
          }).firstOrNull;
          if (group == null) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (group.updatedAt.isAfter(deletedAt)) {
            markSkipped(tombstone.entityType);
            continue;
          }
          await mediaCleanupDelegate.deleteImpactGroup(
            group,
            recordSyncTombstone: false,
          );
          markDeleted(tombstone.entityType);
          break;
      }
    }

    final deletedCount =
        deletedByType.values.fold(0, (sum, item) => sum + item);
    final skippedCount =
        skippedByType.values.fold(0, (sum, item) => sum + item);
    return EntityTombstoneApplyResult(
      deletedCount: deletedCount,
      skippedCount: skippedCount,
      deletedByType: deletedByType,
      skippedByType: skippedByType,
    );
  }

  Future<String?> materializePackageMediaFile({
    required PackagePreviewResult preview,
    required Archive? packageArchive,
    required String packageMediaPath,
    required String dataPath,
    required Map<String, String> importedMediaPathCache,
  }) async {
    final cacheKey = normalizePackageMediaCacheKey(packageMediaPath);
    final fileName = extractArchiveFileNameFromPackagePath(packageMediaPath);
    if (fileName.isEmpty) return null;
    final extension = p.extension(fileName).toLowerCase();
    if (!trackedMediaExtensions.contains(extension)) {
      return null;
    }
    if (!preview.availablePackageFiles.contains(fileName)) {
      return null;
    }

    final cachedPath = importedMediaPathCache[cacheKey];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return cachedPath;
    }

    if (packageArchive == null) {
      return null;
    }

    final archiveFile =
        findArchiveFileByNameOrBasename(packageArchive, fileName);
    if (archiveFile == null || !archiveFile.isFile) {
      return null;
    }
    if (archiveFile.size < 0 ||
        archiveFile.size > maxImportPackageEntrySizeBytes) {
      return null;
    }

    final bytes = archiveFile.content;
    final expectedSize = preview.packageFileSizes[fileName];
    if (expectedSize != null && expectedSize != bytes.length) {
      return null;
    }
    final expectedHash = preview.packageFileHashes[fileName];
    if (expectedHash != null &&
        expectedHash.isNotEmpty &&
        sha256BytesHex(bytes) != expectedHash) {
      return null;
    }

    final savePath = p.join(dataPath, '${const Uuid().v4()}$extension');
    await File(savePath).writeAsBytes(bytes, flush: true);
    importedMediaPathCache[cacheKey] = savePath;
    archiveFile.clear();
    return savePath;
  }

  Future<String?> resolveImportedMapPath({
    required PackagePreviewResult preview,
    required Archive? packageArchive,
    required String rawPath,
    String currentLocalPath = '',
    required String dataPath,
    required Map<String, String> importedMediaPathCache,
  }) async {
    final normalized = normalizeLegacyBuiltinAssetPath(rawPath);
    if (normalized.isEmpty) return '';
    if (isAssetPath(normalized)) return normalized;
    if (await isLocalFileEquivalentToPackagePath(
      localPath: currentLocalPath,
      sharedRawPath: normalized,
      packageFileHashes: preview.packageFileHashes,
    )) {
      return currentLocalPath.trim();
    }
    if (dataPath.trim().isEmpty) return null;
    return materializePackageMediaFile(
      preview: preview,
      packageArchive: packageArchive,
      packageMediaPath: normalized,
      dataPath: dataPath,
      importedMediaPathCache: importedMediaPathCache,
    );
  }

  Future<int> upsertMapsForImport(
    PackagePreviewResult preview, {
    required Archive? packageArchive,
    required String dataPath,
    required Map<String, String> importedMediaPathCache,
  }) async {
    if (preview.maps.isEmpty) return 0;
    var changedCount = 0;
    final localByName = <String, GameMap>{};

    for (final shared in preview.maps) {
      final mapName = shared.mapName.trim();
      if (mapName.isEmpty) continue;
      final existing = localByName[mapName] ??
          await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (existing != null && isBuiltinAssetMap(existing)) {
        localByName[mapName] = existing;
        continue;
      }

      final nextBackgroundPath = await resolveImportedMapPath(
        preview: preview,
        packageArchive: packageArchive,
        rawPath: shared.backgroundPath,
        currentLocalPath: existing?.backgroundPath ?? '',
        dataPath: dataPath,
        importedMediaPathCache: importedMediaPathCache,
      );
      final nextIconPath = await resolveImportedMapPath(
        preview: preview,
        packageArchive: packageArchive,
        rawPath: shared.iconPath,
        currentLocalPath: existing?.iconPath ?? '',
        dataPath: dataPath,
        importedMediaPathCache: importedMediaPathCache,
      );

      if (existing == null) {
        final created = GameMap(
          name: mapName,
          backgroundPath: nextBackgroundPath ?? '',
          iconPath: nextIconPath ?? '',
        );
        final layersToCreate = <MapLayer>[];
        final sharedLayers = shared.layers.toList(growable: false)
          ..sort((a, b) {
            final orderCompare = a.sortOrder.compareTo(b.sortOrder);
            if (orderCompare != 0) return orderCompare;
            return a.name.compareTo(b.name);
          });
        final seenLayerNames = <String>{};
        for (final sharedLayer in sharedLayers) {
          final layerName = sharedLayer.name.trim();
          if (layerName.isEmpty || !seenLayerNames.add(layerName)) continue;
          final nextAssetPath = await resolveImportedMapPath(
            preview: preview,
            packageArchive: packageArchive,
            rawPath: sharedLayer.assetPath,
            currentLocalPath: '',
            dataPath: dataPath,
            importedMediaPathCache: importedMediaPathCache,
          );
          layersToCreate.add(MapLayer(
            name: layerName,
            assetPath: nextAssetPath ?? '',
            sortOrder: sharedLayer.sortOrder,
          ));
        }

        await isar.writeTxn(() async {
          await isar.gameMaps.put(created);
          if (layersToCreate.isNotEmpty) {
            await isar.mapLayers.putAll(layersToCreate);
            created.layers.addAll(layersToCreate);
            await created.layers.save();
          }
        });
        localByName[mapName] = created;
        changedCount++;
        continue;
      }

      localByName[mapName] = existing;
      final replacedMapAssetPaths = <String>{};
      var mapChanged = false;
      if (nextBackgroundPath != null &&
          existing.backgroundPath != nextBackgroundPath) {
        if (existing.backgroundPath.trim().isNotEmpty) {
          replacedMapAssetPaths.add(existing.backgroundPath.trim());
        }
        existing.backgroundPath = nextBackgroundPath;
        mapChanged = true;
      }
      if (nextIconPath != null && existing.iconPath != nextIconPath) {
        if (existing.iconPath.trim().isNotEmpty) {
          replacedMapAssetPaths.add(existing.iconPath.trim());
        }
        existing.iconPath = nextIconPath;
        mapChanged = true;
      }

      await existing.layers.load();
      final layerByName = <String, MapLayer>{
        for (final layer in existing.layers)
          if (layer.name.trim().isNotEmpty) layer.name.trim(): layer,
      };
      final toCreate = <MapLayer>[];
      final toUpdate = <MapLayer>[];
      final sharedLayers = shared.layers.toList(growable: false)
        ..sort((a, b) {
          final orderCompare = a.sortOrder.compareTo(b.sortOrder);
          if (orderCompare != 0) return orderCompare;
          return a.name.compareTo(b.name);
        });
      final seenLayerNames = <String>{};
      for (final sharedLayer in sharedLayers) {
        final layerName = sharedLayer.name.trim();
        if (layerName.isEmpty || !seenLayerNames.add(layerName)) continue;
        final localLayer = layerByName[layerName];
        final nextAssetPath = await resolveImportedMapPath(
          preview: preview,
          packageArchive: packageArchive,
          rawPath: sharedLayer.assetPath,
          currentLocalPath: localLayer?.assetPath ?? '',
          dataPath: dataPath,
          importedMediaPathCache: importedMediaPathCache,
        );
        if (localLayer == null) {
          toCreate.add(MapLayer(
            name: layerName,
            assetPath: nextAssetPath ?? '',
            sortOrder: sharedLayer.sortOrder,
          ));
          continue;
        }
        var layerChanged = false;
        if (nextAssetPath != null && localLayer.assetPath != nextAssetPath) {
          if (localLayer.assetPath.trim().isNotEmpty) {
            replacedMapAssetPaths.add(localLayer.assetPath.trim());
          }
          localLayer.assetPath = nextAssetPath;
          layerChanged = true;
        }
        if (localLayer.sortOrder != sharedLayer.sortOrder) {
          localLayer.sortOrder = sharedLayer.sortOrder;
          layerChanged = true;
        }
        if (layerChanged) {
          toUpdate.add(localLayer);
        }
      }

      if (!mapChanged && toCreate.isEmpty && toUpdate.isEmpty) {
        continue;
      }

      await isar.writeTxn(() async {
        if (mapChanged) {
          await isar.gameMaps.put(existing);
        }
        if (toCreate.isNotEmpty) {
          await isar.mapLayers.putAll(toCreate);
          existing.layers.addAll(toCreate);
          await existing.layers.save();
        }
        if (toUpdate.isNotEmpty) {
          await isar.mapLayers.putAll(toUpdate);
        }
      });
      await mediaCleanupDelegate
          .deleteMediaFilesIfUnused(replacedMapAssetPaths);
      changedCount++;
    }

    return changedCount;
  }
}
