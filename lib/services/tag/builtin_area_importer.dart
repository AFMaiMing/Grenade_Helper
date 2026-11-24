import 'dart:convert';

import 'package:isar_community/isar.dart';

import '../../data/builtin_area_region_presets.dart';
import '../../data/map_area_presets.dart';
import '../../models.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import '../tag_uuid_service.dart';
import 'tag_preset_resolver.dart';
import 'tag_sync_models.dart';

class BuiltinAreaImporter {
  final Isar isar;

  const BuiltinAreaImporter(this.isar);

  /// 为所有地图补齐内置区域标签与区域几何数据。
  Future<DefaultAreaTagReimportSummary> initializeForAllMaps() async {
    final maps = await isar.gameMaps.where().findAll();
    if (maps.isEmpty) {
      return const DefaultAreaTagReimportSummary(
        processedMaps: 0,
        mapsWithPresets: 0,
        addedTags: 0,
        updatedTags: 0,
        mapsWithAreaData: 0,
        addedAreas: 0,
        updatedAreas: 0,
        removedDuplicateAreas: 0,
        addedTagDetails: <AreaTagSyncDetail>[],
        updatedTagDetails: <AreaTagSyncDetail>[],
      );
    }

    final areaColor = dimensionColors[TagDimension.area] ?? 0xFF4CAF50;
    int mapsWithPresets = 0;
    int addedTags = 0;
    int updatedTags = 0;
    int mapsWithAreaData = 0;
    int addedAreas = 0;
    int updatedAreas = 0;
    int removedDuplicateAreas = 0;
    final addedTagDetails = <AreaTagSyncDetail>[];
    final updatedTagDetails = <AreaTagSyncDetail>[];

    for (final map in maps) {
      final presetNames =
          resolveMapPreset(map, mapAreaPresets) ?? const <String>[];
      final builtinAreaData = resolveMapPreset(map, builtinAreaRegionPresets) ??
          const <String, List<BuiltinAreaPreset>>{};

      final requiredNames = <String>{
        ...presetNames,
        ...builtinAreaData.values.expand((list) => list.map((e) => e.name)),
      };
      if (requiredNames.isEmpty) continue;

      if (presetNames.isNotEmpty) mapsWithPresets++;
      if (builtinAreaData.isNotEmpty) mapsWithAreaData++;

      final allMapTags =
          await isar.tags.filter().mapIdEqualTo(map.id).findAll();
      final existingAreaTags = allMapTags
          .where((tag) => tag.dimension == TagDimension.area)
          .toList();

      final maxOrderTag = await isar.tags
          .filter()
          .mapIdEqualTo(map.id)
          .sortBySortOrderDesc()
          .findFirst();
      int nextOrder = (maxOrderTag?.sortOrder ?? 0) + 1;

      final toCreate = <Tag>[];
      final toUpdate = <Tag>[];

      for (final name in requiredNames) {
        final expectedUuid = TagUuidService.buildSystemTagUuid(
          mapName: map.name,
          mapIconPath: map.iconPath,
          dimension: TagDimension.area,
          tagName: name,
        );
        final existing = _matchExistingAreaTag(
          existingAreaTags,
          name: name,
          expectedUuid: expectedUuid,
        );
        if (existing == null) {
          final created = Tag(
            tagUuid: expectedUuid,
            name: name,
            colorValue: areaColor,
            dimension: TagDimension.area,
            isSystem: true,
            sortOrder: nextOrder++,
            mapId: map.id,
          );
          toCreate.add(created);
          addedTagDetails.add(
            AreaTagSyncDetail(
              mapId: map.id,
              mapName: map.name,
              tagId: null,
              tagName: name,
              oldTagUuid: '',
              newTagUuid: created.tagUuid,
              oldColorValue: 0,
              newColorValue: created.colorValue,
            ),
          );
          continue;
        }

        if (existing.isSystem) {
          final uuidOccupiedByOther = allMapTags.any(
            (tag) => tag.id != existing.id && tag.tagUuid == expectedUuid,
          );
          final changed = existing.colorValue != areaColor ||
              (!uuidOccupiedByOther && existing.tagUuid != expectedUuid);
          if (changed) {
            final oldTagUuid = existing.tagUuid;
            final oldColorValue = existing.colorValue;
            existing.colorValue = areaColor;
            if (!uuidOccupiedByOther) {
              existing.tagUuid = expectedUuid;
            }
            existing.updatedAt = DateTime.now();
            toUpdate.add(existing);
            updatedTagDetails.add(
              AreaTagSyncDetail(
                mapId: map.id,
                mapName: map.name,
                tagId: existing.id,
                tagName: existing.name,
                oldTagUuid: oldTagUuid,
                newTagUuid: expectedUuid,
                oldColorValue: oldColorValue,
                newColorValue: areaColor,
              ),
            );
          }
        }
      }

      if (toCreate.isNotEmpty || toUpdate.isNotEmpty) {
        await isar.writeTxn(() async {
          for (final tag in toCreate) {
            await isar.tags.put(tag);
          }
          for (final tag in toUpdate) {
            await isar.tags.put(tag);
          }
        });
        addedTags += toCreate.length;
        updatedTags += toUpdate.length;
      }

      final upsertSummary = await _reimportAreaDataForMap(
        map,
        overwriteExisting: true,
      );
      addedAreas += upsertSummary.addedAreas;
      updatedAreas += upsertSummary.updatedAreas;
      removedDuplicateAreas += upsertSummary.removedDuplicateAreas;
    }

    return DefaultAreaTagReimportSummary(
      processedMaps: maps.length,
      mapsWithPresets: mapsWithPresets,
      addedTags: addedTags,
      updatedTags: updatedTags,
      mapsWithAreaData: mapsWithAreaData,
      addedAreas: addedAreas,
      updatedAreas: updatedAreas,
      removedDuplicateAreas: removedDuplicateAreas,
      addedTagDetails: addedTagDetails,
      updatedTagDetails: updatedTagDetails,
    );
  }

  Tag? _matchExistingAreaTag(
    List<Tag> existingAreaTags, {
    required String name,
    required String expectedUuid,
  }) {
    final sameNameTags = existingAreaTags.where((tag) => tag.name == name);
    return sameNameTags
            .where((tag) => tag.tagUuid == expectedUuid)
            .cast<Tag?>()
            .firstOrNull ??
        sameNameTags.where((tag) => tag.isSystem).cast<Tag?>().firstOrNull ??
        sameNameTags.cast<Tag?>().firstOrNull;
  }

  Future<void> importMissingAreasForMap(GameMap map) async {
    await _reimportAreaDataForMap(map, overwriteExisting: false);
  }

  Future<_BuiltinAreaUpsertSummary> _reimportAreaDataForMap(
    GameMap map, {
    required bool overwriteExisting,
  }) async {
    final presetByFloor = resolveMapPreset(map, builtinAreaRegionPresets);
    if (presetByFloor == null || presetByFloor.isEmpty) {
      return const _BuiltinAreaUpsertSummary(
        addedAreas: 0,
        updatedAreas: 0,
        removedDuplicateAreas: 0,
      );
    }

    await map.layers.load();
    final layers = map.layers.toList();
    if (layers.isEmpty) {
      return const _BuiltinAreaUpsertSummary(
        addedAreas: 0,
        updatedAreas: 0,
        removedDuplicateAreas: 0,
      );
    }

    final layerByFloorKey = <String, MapLayer>{};
    for (final layer in layers) {
      final fileName = extractPathFileName(layer.assetPath).toLowerCase();
      layerByFloorKey[fileName] = layer;
      layerByFloorKey[stripFileExtension(fileName)] = layer;
    }

    final areaTags = await isar.tags
        .filter()
        .mapIdEqualTo(map.id)
        .dimensionEqualTo(TagDimension.area)
        .findAll();
    final tagByName = <String, Tag>{for (final tag in areaTags) tag.name: tag};

    final existingAreas =
        await isar.mapAreas.filter().mapIdEqualTo(map.id).findAll();
    final grouped = <String, List<MapArea>>{};
    for (final area in existingAreas) {
      final layerId = area.layerId;
      if (layerId == null) continue;
      final key = '${area.tagId}:$layerId';
      grouped.putIfAbsent(key, () => []).add(area);
    }

    int addedAreas = 0;
    int updatedAreas = 0;
    final deleteIds = <int>{};
    final toPut = <MapArea>[];

    MapLayer? resolveLayer(String rawFloorKey) {
      final lower = rawFloorKey.toLowerCase();
      return layerByFloorKey[lower] ??
          layerByFloorKey[stripFileExtension(lower)];
    }

    void upsertPresetToLayer(
      BuiltinAreaPreset preset,
      MapLayer layer, {
      required String strokesJson,
    }) {
      final tag = tagByName[preset.name];
      if (tag == null) return;

      final key = '${tag.id}:${layer.id}';
      final currentList = grouped[key] ?? const <MapArea>[];

      MapArea? newest;
      if (currentList.isNotEmpty) {
        newest = currentList.reduce((a, b) => _isAreaNewer(a, b) ? a : b);
        for (final area in currentList) {
          if (area.id != newest.id) {
            deleteIds.add(area.id);
          }
        }
      }

      if (newest == null) {
        toPut.add(MapArea(
          name: preset.name,
          colorValue: preset.colorValue,
          strokes: strokesJson,
          mapId: map.id,
          layerId: layer.id,
          tagId: tag.id,
          createdAt: DateTime.now(),
          updated: DateTime.now(),
        ));
        addedAreas++;
        return;
      }

      if (!overwriteExisting) return;

      final changed = newest.name != preset.name ||
          newest.colorValue != preset.colorValue ||
          newest.strokes != strokesJson ||
          newest.layerId != layer.id ||
          newest.tagId != tag.id;

      if (changed) {
        newest.name = preset.name;
        newest.colorValue = preset.colorValue;
        newest.strokes = strokesJson;
        newest.layerId = layer.id;
        newest.tagId = tag.id;
        newest.updatedAt = DateTime.now();
        toPut.add(newest);
        updatedAreas++;
      }
    }

    for (final entry in presetByFloor.entries) {
      final floorKey = entry.key.toLowerCase();
      if (floorKey == '_merged') {
        for (final preset in entry.value) {
          final floorStrokeMap =
              _decodeFloorStrokesMap(preset.floorStrokesJson);
          if (floorStrokeMap.isNotEmpty) {
            for (final strokeEntry in floorStrokeMap.entries) {
              final layer = resolveLayer(strokeEntry.key);
              if (layer == null) continue;
              upsertPresetToLayer(preset, layer,
                  strokesJson: strokeEntry.value);
            }
            continue;
          }

          final presetFloorKey = (preset.floorKey ?? '').toLowerCase();
          final presetStrokes = preset.strokesJson;
          if (presetFloorKey.isEmpty || presetStrokes == null) continue;
          final layer = resolveLayer(presetFloorKey);
          if (layer == null) continue;
          upsertPresetToLayer(preset, layer, strokesJson: presetStrokes);
        }
        continue;
      }

      final layer = resolveLayer(floorKey);
      if (layer == null) continue;
      for (final preset in entry.value) {
        final presetStrokes = preset.strokesJson;
        if (presetStrokes == null) continue;
        upsertPresetToLayer(preset, layer, strokesJson: presetStrokes);
      }
    }

    if (toPut.isNotEmpty || deleteIds.isNotEmpty) {
      await isar.writeTxn(() async {
        for (final area in toPut) {
          await isar.mapAreas.put(area);
        }
        for (final id in deleteIds) {
          await isar.mapAreas.delete(id);
        }
      });
    }

    return _BuiltinAreaUpsertSummary(
      addedAreas: addedAreas,
      updatedAreas: updatedAreas,
      removedDuplicateAreas: deleteIds.length,
    );
  }

  bool _isAreaNewer(MapArea a, MapArea b) {
    if (a.updatedAt.isAfter(b.updatedAt)) return true;
    if (a.updatedAt.isBefore(b.updatedAt)) return false;
    if (a.createdAt.isAfter(b.createdAt)) return true;
    if (a.createdAt.isBefore(b.createdAt)) return false;
    return a.id > b.id;
  }

  Map<String, String> _decodeFloorStrokesMap(String? floorStrokesJson) {
    if (floorStrokesJson == null || floorStrokesJson.trim().isEmpty) {
      return const <String, String>{};
    }
    try {
      final decoded = jsonDecode(floorStrokesJson);
      if (decoded is! Map) return const <String, String>{};

      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        if (key is! String || key.trim().isEmpty) continue;
        final value = entry.value;
        result[key] = value is String ? value : jsonEncode(value);
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }
}

class _BuiltinAreaUpsertSummary {
  final int addedAreas;
  final int updatedAreas;
  final int removedDuplicateAreas;

  const _BuiltinAreaUpsertSummary({
    required this.addedAreas,
    required this.updatedAreas,
    required this.removedDuplicateAreas,
  });
}
