import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../models/grenade_tag.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import 'lan_sync/lan_sync_local_store.dart';
import 'tag/builtin_area_importer.dart';
import 'tag/system_tag_ensurer.dart';
import 'tag/tag_sync_models.dart';
import 'tag_uuid_service.dart';

export 'tag/tag_sync_models.dart'
    show
        DefaultAreaTagReimportSummary,
        AreaTagSyncDetail,
        EnsureSystemTagSummary,
        ObsoleteSystemTagUsageInfo,
        TagUuidMigrationSummary,
        TagUuidMigrationDetail;

class TagService {
  final Isar isar;
  late final SystemTagEnsurer _systemEnsurer = SystemTagEnsurer(isar);
  late final BuiltinAreaImporter _areaImporter = BuiltinAreaImporter(isar);

  TagService(this.isar);

  Future<void> _touchGrenadeForTagRelationChange(int grenadeId) async {
    final grenade = await isar.grenades.get(grenadeId);
    if (grenade == null) return;
    grenade.updatedAt = DateTime.now();
    grenade.hasLocalEdits = true;
    await isar.writeTxn(() async {
      await isar.grenades.put(grenade);
    });
  }

  Future<void> clearDeletedSystemTagRecordsForMap(int mapId) {
    return _systemEnsurer.clearDeletedRecordsForMap(mapId);
  }

  /// 初始化地图的系统标签并首次导入内置区域几何数据。
  Future<void> initializeSystemTags(int mapId, String mapName) async {
    final map = await isar.gameMaps.get(mapId);
    if (map == null) return;

    await _systemEnsurer.ensureForMap(map, mapNameFallback: mapName);
    await _areaImporter.importMissingAreasForMap(map);
  }

  Future<EnsureSystemTagSummary> ensureSystemTagsForAllMaps({
    bool cleanupObsoleteSystemTags = true,
  }) {
    return _systemEnsurer.ensureForAllMaps(
      cleanupObsoleteSystemTags: cleanupObsoleteSystemTags,
    );
  }

  /// 为所有地图补齐内置区域标签与区域几何数据（非破坏性）。
  Future<DefaultAreaTagReimportSummary>
      initializeBuiltinAreaMetadataForAllMaps() {
    return _areaImporter.initializeForAllMaps();
  }

  Future<Map<int, List<Tag>>> getTagsByDimension(int mapId) async {
    final tags = await getAllTags(mapId);
    final grouped = <int, List<Tag>>{};
    for (final tag in tags) {
      grouped.putIfAbsent(tag.dimension, () => []).add(tag);
    }
    return grouped;
  }

  Future<List<Tag>> getAllTags(int mapId) {
    return isar.tags.filter().mapIdEqualTo(mapId).sortBySortOrder().findAll();
  }

  Future<Tag> createTag(
    int mapId,
    String name,
    int color, {
    int dimension = TagDimension.custom,
  }) async {
    final maxOrder = await isar.tags
        .filter()
        .mapIdEqualTo(mapId)
        .sortBySortOrderDesc()
        .findFirst();
    final now = DateTime.now();
    final tag = Tag(
      tagUuid: TagUuidService.newRandomUuid(),
      name: name,
      colorValue: color,
      dimension: dimension,
      isSystem: false,
      sortOrder: (maxOrder?.sortOrder ?? 0) + 1,
      mapId: mapId,
      updated: now,
    );
    await isar.writeTxn(() async {
      tag.updatedAt = DateTime.now();
      await isar.tags.put(tag);
    });
    return tag;
  }

  Future<void> updateTag(Tag tag) async {
    final original = await isar.tags.get(tag.id);
    String? deletedSystemUuidToMark;
    final now = DateTime.now();
    if (original != null && original.isSystem) {
      final renamed = original.name.trim() != tag.name.trim();
      final dimensionChanged = original.dimension != tag.dimension;
      // 系统标签一旦改名或换维度则转为自定义标签，并记录原系统 UUID 防复活。
      if (renamed || dimensionChanged) {
        deletedSystemUuidToMark = original.tagUuid;
        tag.isSystem = false;
        tag.tagUuid = TagUuidService.newRandomUuid();
      }
    }

    await isar.writeTxn(() async {
      tag.updatedAt = now;
      await isar.tags.put(tag);

      final linkedAreas =
          await isar.mapAreas.filter().tagIdEqualTo(tag.id).findAll();
      if (linkedAreas.isEmpty) return;

      final areasToUpdate = <MapArea>[];
      for (final area in linkedAreas) {
        var changed = false;
        if (area.name != tag.name) {
          area.name = tag.name;
          changed = true;
        }
        if (area.colorValue != tag.colorValue) {
          area.colorValue = tag.colorValue;
          changed = true;
        }
        if (changed) {
          area.updatedAt = now;
          areasToUpdate.add(area);
        }
      }

      if (areasToUpdate.isNotEmpty) {
        await isar.mapAreas.putAll(areasToUpdate);
      }
    });

    if (deletedSystemUuidToMark != null) {
      await _systemEnsurer.markDeletedSystemTagUuid(
        tag.mapId,
        deletedSystemUuidToMark,
      );
    }
  }

  Future<TagUuidMigrationSummary> ensureTagUuids() {
    return _systemEnsurer.ensureTagUuids();
  }

  Future<void> deleteTag(int tagId, {bool deleteRelatedAreas = false}) async {
    final tag = await isar.tags.get(tagId);
    final tombstones = <LanSyncEntityTombstoneEntry>[];
    if (tag != null) {
      final map = await isar.gameMaps.get(tag.mapId);
      final mapName = map?.name.trim() ?? '';
      final tagUuid = tag.tagUuid.trim();
      final deletedAt = DateTime.now().millisecondsSinceEpoch;
      if (mapName.isNotEmpty && tagUuid.isNotEmpty) {
        tombstones.add(
          LanSyncEntityTombstoneEntry(
            entityType: LanSyncEntityTombstoneType.tag,
            entityKey: tagUuid,
            mapName: mapName,
            deletedAt: deletedAt,
            payload: {
              'tagUuid': tagUuid,
              'tagName': tag.name,
              'dimension': tag.dimension,
              'colorValue': tag.colorValue,
              'deleteRelatedAreas': deleteRelatedAreas,
            },
          ),
        );
      }
      if (deleteRelatedAreas && map != null && tagUuid.isNotEmpty) {
        await map.layers.load();
        final layerNameById = <int, String>{
          for (final layer in map.layers) layer.id: layer.name,
        };
        final areas =
            await isar.mapAreas.filter().tagIdEqualTo(tagId).findAll();
        for (final area in areas) {
          final layerName = area.layerId == null
              ? 'Default'
              : (layerNameById[area.layerId!] ?? 'Default');
          tombstones.add(
            LanSyncEntityTombstoneEntry(
              entityType: LanSyncEntityTombstoneType.area,
              entityKey: '$tagUuid|${layerName.trim().toLowerCase()}',
              mapName: mapName,
              deletedAt: deletedAt,
              payload: {
                'tagUuid': tagUuid,
                'tagName': tag.name,
                'layerName': layerName,
              },
            ),
          );
        }
      }
    }

    await isar.writeTxn(() async {
      await isar.grenadeTags.filter().tagIdEqualTo(tagId).deleteAll();
      if (deleteRelatedAreas) {
        await isar.mapAreas.filter().tagIdEqualTo(tagId).deleteAll();
      }
      await isar.tags.delete(tagId);
    });

    if (tombstones.isNotEmpty) {
      await LanSyncLocalStore().upsertEntityTombstones(tombstones);
    }
    if (tag != null && tag.isSystem) {
      await _systemEnsurer.markDeletedSystemTagUuid(tag.mapId, tag.tagUuid);
    }
  }

  Future<void> addTagToGrenade(int grenadeId, int tagId) async {
    final exists = await isar.grenadeTags
        .filter()
        .grenadeIdEqualTo(grenadeId)
        .and()
        .tagIdEqualTo(tagId)
        .findFirst();
    if (exists != null) return;
    await isar.writeTxn(() async {
      await isar.grenadeTags
          .put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
    });
    await _touchGrenadeForTagRelationChange(grenadeId);
  }

  Future<void> removeTagFromGrenade(int grenadeId, int tagId) async {
    var changed = false;
    await isar.writeTxn(() async {
      final removed = await isar.grenadeTags
          .filter()
          .grenadeIdEqualTo(grenadeId)
          .and()
          .tagIdEqualTo(tagId)
          .deleteAll();
      changed = removed > 0;
    });
    if (changed) {
      await _touchGrenadeForTagRelationChange(grenadeId);
    }
  }

  Future<Set<int>> getGrenadeTagIds(int grenadeId) async {
    final grenadeTags =
        await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).findAll();
    return grenadeTags.map((gt) => gt.tagId).toSet();
  }

  Future<List<Tag>> getGrenadeTags(int grenadeId) async {
    final tagIds = await getGrenadeTagIds(grenadeId);
    if (tagIds.isEmpty) return [];
    final tags = await isar.tags.getAll(tagIds.toList(growable: false));
    return tags.whereType<Tag>().toList();
  }

  /// 按选中标签并集筛选道具。
  Future<List<Grenade>> filterByTags(
    List<Grenade> grenades,
    Set<int> selectedTagIds,
  ) async {
    if (selectedTagIds.isEmpty) return grenades;
    final result = <Grenade>[];
    for (final grenade in grenades) {
      final grenadeTags = await getGrenadeTagIds(grenade.id);
      if (selectedTagIds.any(grenadeTags.contains)) {
        result.add(grenade);
      }
    }
    return result;
  }

  Future<Map<String, List<Grenade>>> getTacticalPackages(
    List<Grenade> grenades,
  ) async {
    final packages = <String, List<Grenade>>{};
    for (final grenade in grenades) {
      final tagIds = await getGrenadeTagIds(grenade.id);
      if (tagIds.isEmpty) continue;
      final key = (tagIds.toList()..sort()).join(',');
      packages.putIfAbsent(key, () => []).add(grenade);
    }
    return packages;
  }

  Future<void> setGrenadeTags(int grenadeId, Set<int> tagIds) async {
    final existingLinks =
        await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).findAll();
    final existingTagIds = existingLinks.map((e) => e.tagId).toSet();
    final normalizedTagIds = Set<int>.from(tagIds);
    if (setEquals(existingTagIds, normalizedTagIds)) {
      return;
    }
    await isar.writeTxn(() async {
      await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).deleteAll();
      for (final tagId in normalizedTagIds) {
        await isar.grenadeTags
            .put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
      }
    });
    await _touchGrenadeForTagRelationChange(grenadeId);
  }
}
