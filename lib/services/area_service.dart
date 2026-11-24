import 'package:isar_community/isar.dart';

import '../models.dart';
import '../models/grenade_tag.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import 'area/area_geometry.dart';
import 'area/area_models.dart';
import 'lan_sync/lan_sync_local_store.dart';
import 'tag_uuid_service.dart';

export 'area/area_models.dart' show AutoTagSummary, AreaTagSyncSummary;

class AreaService {
  final Isar isar;

  AreaService(this.isar);

  Future<void> _touchGrenadesForTagRelationChanges(
    Iterable<int> grenadeIds,
  ) async {
    final ids = grenadeIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    final grenades = await isar.grenades.getAll(ids);
    final toUpdate = <Grenade>[];
    final now = DateTime.now();
    for (final grenade in grenades) {
      if (grenade == null) continue;
      grenade.updatedAt = now;
      grenade.hasLocalEdits = true;
      toUpdate.add(grenade);
    }
    if (toUpdate.isEmpty) return;
    await isar.writeTxn(() async {
      await isar.grenades.putAll(toUpdate);
    });
  }

  Future<List<MapArea>> getAreas(int mapId) {
    return isar.mapAreas.filter().mapIdEqualTo(mapId).findAll();
  }

  Future<MapArea> createArea({
    required String name,
    required int colorValue,
    required String strokes,
    required int mapId,
    int? layerId,
    int? existingTagId,
  }) async {
    final now = DateTime.now();
    final int tagId;
    if (existingTagId != null) {
      tagId = existingTagId;
      await isar.writeTxn(() async {
        final tag = await isar.tags.get(existingTagId);
        if (tag != null) {
          if (tag.tagUuid.trim().isEmpty) {
            tag.tagUuid = TagUuidService.newRandomUuid();
          }
          tag.updatedAt = now;
          tag.name = name;
          tag.colorValue = colorValue;
          await isar.tags.put(tag);
        }
      });
    } else {
      final tag = Tag(
        tagUuid: TagUuidService.newRandomUuid(),
        name: name,
        colorValue: colorValue,
        dimension: TagDimension.area,
        isSystem: false,
        sortOrder: 0,
        mapId: mapId,
      );
      await isar.writeTxn(() async {
        await isar.tags.put(tag);
      });
      tagId = tag.id;
    }

    final area = MapArea(
      name: name,
      colorValue: colorValue,
      strokes: strokes,
      mapId: mapId,
      layerId: layerId,
      tagId: tagId,
      createdAt: now,
      updated: now,
    );
    await isar.writeTxn(() async {
      await isar.mapAreas.put(area);
    });
    return area;
  }

  /// 删除区域；[deleteTag] 为 true 时连带删除对应区域标签与关联。
  Future<void> deleteArea(MapArea area, {bool deleteTag = true}) async {
    final tag = await isar.tags.get(area.tagId);
    final map = await isar.gameMaps.get(area.mapId);
    var layerName = 'Default';
    if (area.layerId != null) {
      final layer = await isar.mapLayers.get(area.layerId!);
      if (layer != null && layer.name.trim().isNotEmpty) {
        layerName = layer.name;
      }
    }

    final tombstones = <LanSyncEntityTombstoneEntry>[];
    final tagUuid = tag?.tagUuid.trim() ?? '';
    final mapName = map?.name.trim() ?? '';
    final deletedAt = DateTime.now().millisecondsSinceEpoch;
    if (tagUuid.isNotEmpty && mapName.isNotEmpty) {
      tombstones.add(
        LanSyncEntityTombstoneEntry(
          entityType: LanSyncEntityTombstoneType.area,
          entityKey: '$tagUuid|${layerName.trim().toLowerCase()}',
          mapName: mapName,
          deletedAt: deletedAt,
          payload: {
            'tagUuid': tagUuid,
            'tagName': tag?.name ?? area.name,
            'layerName': layerName,
          },
        ),
      );
      if (deleteTag) {
        tombstones.add(
          LanSyncEntityTombstoneEntry(
            entityType: LanSyncEntityTombstoneType.tag,
            entityKey: tagUuid,
            mapName: mapName,
            deletedAt: deletedAt,
            payload: {
              'tagUuid': tagUuid,
              'tagName': tag?.name ?? area.name,
              'dimension': tag?.dimension ?? TagDimension.area,
              'colorValue': tag?.colorValue ?? area.colorValue,
              'deleteRelatedAreas': true,
            },
          ),
        );
      }
    }

    await isar.writeTxn(() async {
      if (deleteTag) {
        await isar.grenadeTags.filter().tagIdEqualTo(area.tagId).deleteAll();
        await isar.tags.delete(area.tagId);
      }
      await isar.mapAreas.delete(area.id);
    });

    if (tombstones.isNotEmpty) {
      await LanSyncLocalStore().upsertEntityTombstones(tombstones);
    }
  }

  Future<void> updateArea({
    required MapArea area,
    required String name,
    required int colorValue,
    required String strokes,
    int? layerId,
  }) async {
    final now = DateTime.now();
    await isar.writeTxn(() async {
      final tag = await isar.tags.get(area.tagId);
      if (tag != null) {
        tag.updatedAt = now;
        tag.name = name;
        tag.colorValue = colorValue;
        await isar.tags.put(tag);
      }

      area.updatedAt = now;
      area.name = name;
      area.colorValue = colorValue;
      area.strokes = strokes;
      area.layerId = layerId;
      await isar.mapAreas.put(area);
    });
  }

  bool isPointInArea(double x, double y, MapArea area) {
    return isPointInAreaJson(x, y, area.strokes);
  }

  Future<List<MapArea>> getAreasForPoint(
    int mapId,
    double x,
    double y, {
    int? layerId,
  }) async {
    final areas = await getAreas(mapId);
    return areas.where((area) {
      // 指定楼层时严格按楼层过滤，防止旧数据 layerId 为 null 引起跨层误标。
      if (layerId != null && area.layerId != layerId) {
        return false;
      }
      return isPointInArea(x, y, area);
    }).toList();
  }

  Future<void> autoTagGrenade(
    Grenade grenade,
    int mapId, {
    int? layerId,
    bool syncExistingAreaTags = false,
    Set<int>? scopedAreaTagIds,
  }) async {
    final effectiveLayerId = layerId ?? await _resolveGrenadeLayerId(grenade);
    final areas = await getAreasForPoint(
      mapId,
      grenade.xRatio,
      grenade.yRatio,
      layerId: effectiveLayerId,
    );
    final matchedAreaTagIds = areas.map((a) => a.tagId).toSet();
    final allAreaTagIds = scopedAreaTagIds ??
        (syncExistingAreaTags ? await _getAreaTagIds(mapId) : const <int>{});
    var changed = false;

    await isar.writeTxn(() async {
      if (syncExistingAreaTags && allAreaTagIds.isNotEmpty) {
        final existingLinks = await isar.grenadeTags
            .filter()
            .grenadeIdEqualTo(grenade.id)
            .findAll();
        for (final link in existingLinks) {
          if (allAreaTagIds.contains(link.tagId) &&
              !matchedAreaTagIds.contains(link.tagId)) {
            await isar.grenadeTags.delete(link.id);
            changed = true;
          }
        }
      }

      for (final tagId in matchedAreaTagIds) {
        final existing = await isar.grenadeTags
            .filter()
            .grenadeIdEqualTo(grenade.id)
            .and()
            .tagIdEqualTo(tagId)
            .findFirst();
        if (existing == null) {
          await isar.grenadeTags
              .put(GrenadeTag(grenadeId: grenade.id, tagId: tagId));
          changed = true;
        }
      }
    });

    if (changed) {
      await _touchGrenadesForTagRelationChanges([grenade.id]);
    }
  }

  Future<AutoTagSummary> autoTagAllGrenades(
    int mapId, {
    bool useImpactPoint = false,
  }) async {
    final areas = await getAreas(mapId);
    final map = await isar.gameMaps.get(mapId);
    if (map == null) {
      return const AutoTagSummary(
        processedGrenades: 0,
        matchedGrenades: 0,
        addedLinks: 0,
        removedLinks: 0,
        areaMatches: {},
      );
    }

    await map.layers.load();
    final allGrenades = <Grenade>[];
    final grenadesByLayer = <int, List<Grenade>>{};
    for (final layer in map.layers) {
      final grenades = await isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(layer.id))
          .findAll();
      grenadesByLayer[layer.id] = grenades;
      allGrenades.addAll(grenades);
    }

    final processedGrenades = useImpactPoint
        ? allGrenades
            .where((g) => g.impactXRatio != null && g.impactYRatio != null)
            .length
        : allGrenades.length;

    if (areas.isEmpty || allGrenades.isEmpty || processedGrenades == 0) {
      return AutoTagSummary(
        processedGrenades: processedGrenades,
        matchedGrenades: 0,
        addedLinks: 0,
        removedLinks: 0,
        areaMatches: const {},
      );
    }

    final areaToGrenadeIds = <int, Set<int>>{};
    final matchedGrenadeIds = <int>{};
    final areaMatches = <String, int>{};

    for (final area in areas) {
      final candidatesRaw = area.layerId == null
          ? allGrenades
          : (grenadesByLayer[area.layerId!] ?? const <Grenade>[]);
      final candidates = _filterByCoordinateMode(
        candidatesRaw,
        useImpactPoint: useImpactPoint,
      );
      final parsedStrokes = parseAreaStrokes(area.strokes);
      final matchedIds = <int>{};
      for (final grenade in candidates) {
        final x = useImpactPoint ? grenade.impactXRatio! : grenade.xRatio;
        final y = useImpactPoint ? grenade.impactYRatio! : grenade.yRatio;
        if (isPointInParsedStrokes(x, y, parsedStrokes)) {
          matchedIds.add(grenade.id);
          matchedGrenadeIds.add(grenade.id);
        }
      }
      areaToGrenadeIds
          .putIfAbsent(area.tagId, () => <int>{})
          .addAll(matchedIds);
      areaMatches[area.name] =
          (areaMatches[area.name] ?? 0) + matchedIds.length;
    }

    int addedLinks = 0;
    int removedLinks = 0;
    final changedGrenadeIds = <int>{};
    await isar.writeTxn(() async {
      for (final entry in areaToGrenadeIds.entries) {
        final counts = await _syncTagLinksInTxn(
          tagId: entry.key,
          targetGrenadeIds: entry.value,
          changedGrenadeIds: changedGrenadeIds,
        );
        addedLinks += counts.added;
        removedLinks += counts.removed;
      }
    });
    await _touchGrenadesForTagRelationChanges(changedGrenadeIds);

    return AutoTagSummary(
      processedGrenades: processedGrenades,
      matchedGrenades: matchedGrenadeIds.length,
      addedLinks: addedLinks,
      removedLinks: removedLinks,
      areaMatches: areaMatches,
    );
  }

  Future<AreaTagSyncSummary> syncAreaTag(
    MapArea area, {
    bool useImpactPoint = false,
  }) async {
    final List<Grenade> grenades;
    if (area.layerId != null) {
      grenades = await isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(area.layerId!))
          .findAll();
    } else {
      final map = await isar.gameMaps.get(area.mapId);
      if (map == null) {
        return const AreaTagSyncSummary(
          processedGrenades: 0,
          matchedGrenades: 0,
          addedLinks: 0,
          removedLinks: 0,
        );
      }
      await map.layers.load();
      grenades = [];
      for (final layer in map.layers) {
        grenades.addAll(
          await isar.grenades
              .filter()
              .layer((q) => q.idEqualTo(layer.id))
              .findAll(),
        );
      }
    }

    final candidates = _filterByCoordinateMode(
      grenades,
      useImpactPoint: useImpactPoint,
    );
    final parsedStrokes = parseAreaStrokes(area.strokes);
    final matchedGrenadeIds = <int>{};
    for (final grenade in candidates) {
      final x = useImpactPoint ? grenade.impactXRatio! : grenade.xRatio;
      final y = useImpactPoint ? grenade.impactYRatio! : grenade.yRatio;
      if (isPointInParsedStrokes(x, y, parsedStrokes)) {
        matchedGrenadeIds.add(grenade.id);
      }
    }

    late ({int added, int removed}) counts;
    final changedGrenadeIds = <int>{};
    await isar.writeTxn(() async {
      counts = await _syncTagLinksInTxn(
        tagId: area.tagId,
        targetGrenadeIds: matchedGrenadeIds,
        changedGrenadeIds: changedGrenadeIds,
      );
    });
    await _touchGrenadesForTagRelationChanges(changedGrenadeIds);

    return AreaTagSyncSummary(
      processedGrenades: candidates.length,
      matchedGrenades: matchedGrenadeIds.length,
      addedLinks: counts.added,
      removedLinks: counts.removed,
    );
  }

  List<Grenade> _filterByCoordinateMode(
    List<Grenade> grenades, {
    required bool useImpactPoint,
  }) {
    if (!useImpactPoint) return grenades;
    return grenades
        .where((g) => g.impactXRatio != null && g.impactYRatio != null)
        .toList();
  }

  Future<({int added, int removed})> _syncTagLinksInTxn({
    required int tagId,
    required Set<int> targetGrenadeIds,
    required Set<int> changedGrenadeIds,
  }) async {
    final existingLinks =
        await isar.grenadeTags.filter().tagIdEqualTo(tagId).findAll();
    final existingIds = <int>{};
    final seen = <int>{};
    int added = 0;
    int removed = 0;

    for (final link in existingLinks) {
      final isDuplicate = !seen.add(link.grenadeId);
      if (isDuplicate || !targetGrenadeIds.contains(link.grenadeId)) {
        await isar.grenadeTags.delete(link.id);
        removed++;
        changedGrenadeIds.add(link.grenadeId);
      } else {
        existingIds.add(link.grenadeId);
      }
    }

    for (final grenadeId in targetGrenadeIds) {
      if (!existingIds.contains(grenadeId)) {
        await isar.grenadeTags
            .put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
        added++;
        changedGrenadeIds.add(grenadeId);
      }
    }

    return (added: added, removed: removed);
  }

  Future<int?> _resolveGrenadeLayerId(Grenade grenade) async {
    if (grenade.layer.value != null) {
      return grenade.layer.value!.id;
    }
    await grenade.layer.load();
    return grenade.layer.value?.id;
  }

  Future<Set<int>> _getAreaTagIds(int mapId) async {
    final areas = await getAreas(mapId);
    return areas.map((a) => a.tagId).toSet();
  }
}
