import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import 'data_package_models.dart';
import 'data_sync_and_media_models.dart';
import 'package_sync_helpers.dart';

class PackageImportEntityUpserter {
  final Isar isar;

  PackageImportEntityUpserter(this.isar);

  Future<Map<String, int>> upsertFavoriteFoldersForImport(
    PackagePreviewResult preview,
  ) async {
    if (preview.schemaVersion < 3) {
      return const {};
    }

    final referencedKeys = <String>{};
    final referencedRefsByKey = <String, PackageFavoriteFolderRef>{};
    final referencedMapNames = <String>{};
    for (final folder in preview.favoriteFolders) {
      final nameKey = folder.nameKey.trim().isEmpty
          ? normalizeFolderNameKey(folder.name)
          : normalizeFolderNameKey(folder.nameKey);
      if (folder.mapName.trim().isEmpty || nameKey.isEmpty) continue;
      referencedMapNames.add(folder.mapName.trim());
      final key = favoriteFolderRefKey(
        mapName: folder.mapName,
        nameKey: nameKey,
      );
      referencedKeys.add(key);
      referencedRefsByKey[key] = PackageFavoriteFolderRef(
        mapName: folder.mapName.trim(),
        nameKey: nameKey,
      );
    }
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final previewItem in mapGrenades) {
        final ref = readFavoriteFolderRef(previewItem.rawData);
        if (ref == null) continue;
        referencedMapNames.add(ref.mapName);
        final key = favoriteFolderRefKey(
          mapName: ref.mapName,
          nameKey: ref.nameKey,
        );
        referencedKeys.add(key);
        referencedRefsByKey[key] = ref;
      }
    }
    if (referencedKeys.isEmpty) return const {};

    final sharedByKey = <String, PackageFavoriteFolderData>{};
    for (final folder in preview.favoriteFolders) {
      final nameKey = folder.nameKey.trim().isEmpty
          ? normalizeFolderNameKey(folder.name)
          : normalizeFolderNameKey(folder.nameKey);
      final key =
          favoriteFolderRefKey(mapName: folder.mapName, nameKey: nameKey);
      if (!referencedKeys.contains(key)) continue;
      final existing = sharedByKey[key];
      if (existing == null || folder.updatedAt >= existing.updatedAt) {
        sharedByKey[key] = folder;
      }
    }
    final mapNames = <String>{
      ...sharedByKey.values.map((e) => e.mapName),
      ...referencedMapNames,
    };
    final mapByName = <String, GameMap>{};
    for (final mapName in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map != null) {
        mapByName[mapName] = map;
      }
    }

    final foldersByMapIdAndNameKey = <String, FavoriteFolder>{};
    for (final map in mapByName.values) {
      final folders =
          await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
      for (final folder in folders) {
        final nameKey = folder.nameKey.trim().isEmpty
            ? normalizeFolderNameKey(folder.name)
            : normalizeFolderNameKey(folder.nameKey);
        foldersByMapIdAndNameKey['${map.id}|$nameKey'] = folder;
      }
    }

    final toCreate = <FavoriteFolder>[];
    final toUpdate = <FavoriteFolder>[];
    final result = <String, int>{};

    for (final entry in sharedByKey.entries) {
      final shared = entry.value;
      final map = mapByName[shared.mapName];
      if (map == null) continue;

      final normalizedNameKey = shared.nameKey.trim().isEmpty
          ? normalizeFolderNameKey(shared.name)
          : normalizeFolderNameKey(shared.nameKey);
      final localKey = '${map.id}|$normalizedNameKey';
      final local = foldersByMapIdAndNameKey[localKey];

      if (local == null) {
        final created = FavoriteFolder(
          mapId: map.id,
          name: shared.name.isEmpty ? normalizedNameKey : shared.name,
          nameKey: normalizedNameKey,
          sortOrder: shared.sortOrder,
          created: DateTime.fromMillisecondsSinceEpoch(shared.createdAt),
          updated: DateTime.fromMillisecondsSinceEpoch(shared.updatedAt),
        );
        toCreate.add(created);
        foldersByMapIdAndNameKey[localKey] = created;
        continue;
      }

      final sharedUpdated =
          DateTime.fromMillisecondsSinceEpoch(shared.updatedAt);
      if (shouldApplyIncomingUpdate(
        sharedUpdatedAtMs: shared.updatedAt,
        localUpdatedAtMs: local.updatedAt.millisecondsSinceEpoch,
        contentDifferent:
            local.name != (shared.name.isEmpty ? local.name : shared.name) ||
                local.nameKey != normalizedNameKey ||
                local.sortOrder != shared.sortOrder,
      )) {
        final nextName = shared.name.isEmpty ? local.name : shared.name;
        final changed = local.name != nextName ||
            local.nameKey != normalizedNameKey ||
            local.sortOrder != shared.sortOrder ||
            local.updatedAt != sharedUpdated;
        if (changed) {
          local.name = nextName;
          local.nameKey = normalizedNameKey;
          local.sortOrder = shared.sortOrder;
          local.updatedAt = sharedUpdated;
          toUpdate.add(local);
        }
      }
    }

    if (toCreate.isNotEmpty || toUpdate.isNotEmpty) {
      await isar.writeTxn(() async {
        if (toCreate.isNotEmpty) {
          await isar.favoriteFolders.putAll(toCreate);
        }
        if (toUpdate.isNotEmpty) {
          await isar.favoriteFolders.putAll(toUpdate);
        }
      });
    }

    for (final compositeKey in referencedKeys) {
      final ref = referencedRefsByKey[compositeKey];
      if (ref == null) continue;
      final map = mapByName[ref.mapName];
      if (map == null) continue;
      final local = foldersByMapIdAndNameKey['${map.id}|${ref.nameKey}'];
      if (local != null) {
        result[compositeKey] = local.id;
      }
    }
    for (final entry in sharedByKey.entries) {
      final shared = entry.value;
      final map = mapByName[shared.mapName];
      if (map == null) continue;
      final normalizedNameKey = shared.nameKey.trim().isEmpty
          ? normalizeFolderNameKey(shared.name)
          : normalizeFolderNameKey(shared.nameKey);
      final local = foldersByMapIdAndNameKey['${map.id}|$normalizedNameKey'];
      if (local != null) {
        result[entry.key] = local.id;
      }
    }

    return result;
  }

  Future<Map<String, int>> upsertImpactGroupsForImport(
    PackagePreviewResult preview,
  ) async {
    if (preview.schemaVersion < 3) {
      return const {};
    }

    final referencedKeys = <String>{};
    for (final group in preview.impactGroups) {
      referencedKeys.add(impactGroupSemanticKey(
        mapName: group.mapName,
        layerName: group.layerName,
        type: group.type,
        name: group.name,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
      ));
    }
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final previewItem in mapGrenades) {
        final ref = readImpactGroupRef(previewItem.rawData);
        if (ref == null) continue;
        referencedKeys.add(impactGroupSemanticKey(
          mapName: ref.mapName,
          layerName: ref.layerName,
          type: ref.type,
          name: ref.name,
          impactXRatio: ref.impactXRatio,
          impactYRatio: ref.impactYRatio,
        ));
      }
    }
    if (referencedKeys.isEmpty) return const {};

    final sharedByKey = <String, PackageImpactGroupData>{};
    for (final group in preview.impactGroups) {
      final key = impactGroupSemanticKey(
        mapName: group.mapName,
        layerName: group.layerName,
        type: group.type,
        name: group.name,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
      );
      if (!referencedKeys.contains(key)) continue;
      final previous = sharedByKey[key];
      if (previous == null || group.updatedAt >= previous.updatedAt) {
        sharedByKey[key] = group;
      }
    }
    final mapNames = <String>{
      ...sharedByKey.values.map((e) => e.mapName),
      ...preview.grenadesByMap.keys,
    };
    final mapByName = <String, GameMap>{};
    final layerByMapAndName = <String, MapLayer>{};
    for (final mapName in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map == null) continue;
      mapByName[mapName] = map;
      await map.layers.load();
      for (final layer in map.layers) {
        layerByMapAndName['${map.name}|${layer.name}'] = layer;
      }
    }

    final localBySemanticKey = <String, ImpactGroup>{};
    final neededLayerIds = <int>{};
    for (final shared in sharedByKey.values) {
      final layer = layerByMapAndName['${shared.mapName}|${shared.layerName}'];
      if (layer != null) neededLayerIds.add(layer.id);
    }
    for (final layerId in neededLayerIds) {
      final groups =
          await isar.impactGroups.filter().layerIdEqualTo(layerId).findAll();
      final layer = await isar.mapLayers.get(layerId);
      if (layer == null) continue;
      await layer.map.load();
      final map = layer.map.value;
      if (map == null) continue;
      for (final group in groups) {
        final key = impactGroupSemanticKey(
          mapName: map.name,
          layerName: layer.name,
          type: group.type,
          name: group.name,
          impactXRatio: group.impactXRatio,
          impactYRatio: group.impactYRatio,
        );
        localBySemanticKey[key] = group;
      }
    }

    final toCreate = <ImpactGroup>[];
    for (final entry in sharedByKey.entries) {
      if (localBySemanticKey.containsKey(entry.key)) continue;
      final shared = entry.value;
      final layer = layerByMapAndName['${shared.mapName}|${shared.layerName}'];
      if (layer == null) continue;
      final created = ImpactGroup(
        name: shared.name,
        type: shared.type,
        impactXRatio: shared.impactXRatio,
        impactYRatio: shared.impactYRatio,
        layerId: layer.id,
        created: DateTime.fromMillisecondsSinceEpoch(shared.createdAt),
        updated: DateTime.fromMillisecondsSinceEpoch(shared.updatedAt),
      );
      toCreate.add(created);
      localBySemanticKey[entry.key] = created;
    }

    if (toCreate.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.impactGroups.putAll(toCreate);
      });
    }

    final result = <String, int>{};
    for (final key in referencedKeys) {
      final local = localBySemanticKey[key];
      if (local != null) {
        result[key] = local.id;
      }
    }
    return result;
  }

  Future<Map<String, int>> upsertTagsForImport(
    PackagePreviewResult preview,
    Set<String> selectedTagUuids, {
    required Map<String, ImportTagConflictResolution> tagResolutions,
  }) async {
    if (selectedTagUuids.isEmpty) return const {};
    if (preview.tagsByUuid.isEmpty) {
      final localTagIdByUuid = <String, int>{};
      final allTags = await isar.tags.where().findAll();
      for (final tag in allTags) {
        final uuid = tag.tagUuid.trim();
        if (uuid.isEmpty || !selectedTagUuids.contains(uuid)) continue;
        localTagIdByUuid[uuid] = tag.id;
      }
      return localTagIdByUuid;
    }

    final tagMapNames = <String>{};
    for (final uuid in selectedTagUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared != null && shared.mapName.isNotEmpty) {
        tagMapNames.add(shared.mapName);
      }
    }
    final context = await buildLocalTagContext(isar, tagMapNames);

    final toPut = <Tag>[];
    final toCreate = <Tag>[];
    final tagIdByUuid = <String, int>{};

    for (final tagUuid in selectedTagUuids) {
      final shared = preview.tagsByUuid[tagUuid];
      if (shared == null || shared.mapName.isEmpty) continue;
      final sharedUpdatedAt = shared.updatedAt;

      final map = context.mapByName[shared.mapName];
      if (map == null) continue;

      final localByUuid = context.localByUuid[tagUuid];
      if (localByUuid != null) {
        final resolution = tagResolutions[tagUuid];
        final shouldApplyShared =
            resolution == ImportTagConflictResolution.shared ||
                (resolution == null &&
                    sharedUpdatedAt >
                        localByUuid.updatedAt.millisecondsSinceEpoch &&
                    isTagDifferent(localByUuid, shared));
        if (shouldApplyShared &&
            shouldApplyIncomingUpdate(
              sharedUpdatedAtMs: sharedUpdatedAt,
              localUpdatedAtMs: localByUuid.updatedAt.millisecondsSinceEpoch,
              contentDifferent: isTagDifferent(localByUuid, shared),
            )) {
          localByUuid.name = shared.name;
          localByUuid.dimension = shared.dimension;
          localByUuid.colorValue = shared.colorValue;
          localByUuid.groupName = shared.groupName;
          localByUuid.isSystem = shared.isSystem;
          localByUuid.updatedAt =
              DateTime.fromMillisecondsSinceEpoch(sharedUpdatedAt);
          toPut.add(localByUuid);
        }
        tagIdByUuid[tagUuid] = localByUuid.id;
        continue;
      }

      final semanticKey = semanticTagKey(map.id, shared.dimension, shared.name);
      final semanticTag = context.localBySemantic[semanticKey];
      if (semanticTag != null) {
        final resolution = tagResolutions[tagUuid];
        final contentDifferent = isTagDifferent(semanticTag, shared) ||
            semanticTag.tagUuid != tagUuid;
        final shouldApplyShared =
            resolution == ImportTagConflictResolution.shared ||
                (resolution == null &&
                    sharedUpdatedAt >
                        semanticTag.updatedAt.millisecondsSinceEpoch &&
                    contentDifferent);
        if (shouldApplyShared &&
            shouldApplyIncomingUpdate(
              sharedUpdatedAtMs: sharedUpdatedAt,
              localUpdatedAtMs: semanticTag.updatedAt.millisecondsSinceEpoch,
              contentDifferent: contentDifferent,
            )) {
          semanticTag.tagUuid = tagUuid;
          semanticTag.name = shared.name;
          semanticTag.dimension = shared.dimension;
          semanticTag.colorValue = shared.colorValue;
          semanticTag.groupName = shared.groupName;
          semanticTag.isSystem = shared.isSystem;
          semanticTag.updatedAt =
              DateTime.fromMillisecondsSinceEpoch(sharedUpdatedAt);
          toPut.add(semanticTag);
          context.localByUuid[tagUuid] = semanticTag;
        }
        tagIdByUuid[tagUuid] = semanticTag.id;
        continue;
      }

      final newTag = Tag(
        tagUuid: tagUuid,
        name: shared.name,
        colorValue: shared.colorValue,
        dimension: shared.dimension,
        groupName: shared.groupName,
        isSystem: shared.isSystem,
        sortOrder: 0,
        mapId: map.id,
        updated: DateTime.fromMillisecondsSinceEpoch(sharedUpdatedAt),
      );
      toCreate.add(newTag);
    }

    if (toPut.isNotEmpty || toCreate.isNotEmpty) {
      await isar.writeTxn(() async {
        if (toPut.isNotEmpty) {
          await isar.tags.putAll(toPut);
        }
        for (final tag in toCreate) {
          await isar.tags.put(tag);
        }
      });
    }

    for (final tag in toCreate) {
      if (tag.tagUuid.trim().isNotEmpty) {
        tagIdByUuid[tag.tagUuid.trim()] = tag.id;
      }
    }

    // 对未命中的 UUID 再兜底查询一次，确保拿到映射
    if (tagIdByUuid.length < selectedTagUuids.length) {
      final allTags = await isar.tags.where().findAll();
      for (final tag in allTags) {
        final uuid = tag.tagUuid.trim();
        if (uuid.isEmpty || !selectedTagUuids.contains(uuid)) continue;
        tagIdByUuid[uuid] = tag.id;
      }
    }

    return tagIdByUuid;
  }

  Future<void> upsertAreasForImport(
    PackagePreviewResult preview,
    Set<String> selectedTagUuids, {
    required Map<String, int> tagIdByUuid,
    required Map<String, ImportAreaConflictResolution> areaResolutions,
  }) async {
    if (preview.areas.isEmpty || selectedTagUuids.isEmpty) return;

    final mapNames = <String>{};
    for (final area in preview.areas) {
      if (selectedTagUuids.contains(area.tagUuid) && area.mapName.isNotEmpty) {
        mapNames.add(area.mapName);
      }
    }

    final mapByName = <String, GameMap>{};
    for (final name in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(name).findFirst();
      if (map != null) mapByName[name] = map;
    }

    final putAreas = <MapArea>[];
    final deleteAreaIds = <int>{};

    final dedupedShared = <String, PackageAreaData>{};
    for (final area in preview.areas) {
      if (!selectedTagUuids.contains(area.tagUuid)) continue;
      final key = '${area.tagUuid}|${area.mapName}|${area.layerName}';
      final previous = dedupedShared[key];
      if (previous == null || area.updatedAt >= previous.updatedAt) {
        dedupedShared[key] = area;
      }
    }

    for (final shared in dedupedShared.values) {
      final tagId = tagIdByUuid[shared.tagUuid];
      if (tagId == null) continue;
      final map = mapByName[shared.mapName];
      if (map == null) continue;
      await map.layers.load();

      MapLayer? layer;
      for (final l in map.layers) {
        if (l.name == shared.layerName) {
          layer = l;
          break;
        }
      }
      if (layer == null) continue;

      final existing = await isar.mapAreas
          .filter()
          .mapIdEqualTo(map.id)
          .tagIdEqualTo(tagId)
          .findAll();
      final layerId = layer.id;
      final sameLayer =
          existing.where((a) => a.layerId == layerId).toList(growable: false);
      if (sameLayer.isEmpty) {
        putAreas.add(MapArea(
          name: shared.name,
          colorValue: shared.colorValue,
          strokes: shared.strokes,
          mapId: map.id,
          layerId: layerId,
          tagId: tagId,
          createdAt: DateTime.fromMillisecondsSinceEpoch(shared.createdAt),
          updated: DateTime.fromMillisecondsSinceEpoch(shared.updatedAt),
        ));
        continue;
      }

      sameLayer.sort((a, b) {
        if (a.updatedAt.isAfter(b.updatedAt)) return -1;
        if (a.updatedAt.isBefore(b.updatedAt)) return 1;
        return b.id.compareTo(a.id);
      });
      final target = sameLayer.first;
      final resolution = areaResolutions[shared.tagUuid];
      final contentDifferent = !isSharedAreaEquivalent(target, shared);
      final shouldApplyShared =
          resolution == ImportAreaConflictResolution.overwriteShared ||
              (resolution == null &&
                  shared.updatedAt > target.updatedAt.millisecondsSinceEpoch &&
                  contentDifferent);
      if (!shouldApplyShared) {
        continue;
      }
      if (!shouldApplyIncomingUpdate(
        sharedUpdatedAtMs: shared.updatedAt,
        localUpdatedAtMs: target.updatedAt.millisecondsSinceEpoch,
        contentDifferent: contentDifferent,
      )) {
        continue;
      }
      target.name = shared.name;
      target.colorValue = shared.colorValue;
      target.strokes = shared.strokes;
      target.updatedAt = DateTime.fromMillisecondsSinceEpoch(shared.updatedAt);
      putAreas.add(target);
      for (final duplicate in sameLayer.skip(1)) {
        deleteAreaIds.add(duplicate.id);
      }
    }

    if (putAreas.isEmpty && deleteAreaIds.isEmpty) return;
    await isar.writeTxn(() async {
      if (putAreas.isNotEmpty) {
        await isar.mapAreas.putAll(putAreas);
      }
      for (final id in deleteAreaIds) {
        await isar.mapAreas.delete(id);
      }
    });
  }
}
