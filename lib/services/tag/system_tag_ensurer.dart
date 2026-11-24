import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/map_area_presets.dart';
import '../../models.dart';
import '../../models/grenade_tag.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import '../tag_uuid_service.dart';
import 'tag_preset_resolver.dart';
import 'tag_sync_models.dart';

class SystemTagEnsurer {
  static const String _deletedSystemTagPrefsPrefix =
      'tag_service.deleted_system_tag_uuids.v1';

  final Isar isar;

  const SystemTagEnsurer(this.isar);

  String _deletedSystemTagPrefsKey(int mapId) =>
      '$_deletedSystemTagPrefsPrefix.$mapId';

  Future<Set<String>> _loadDeletedSystemTagUuids(int mapId) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_deletedSystemTagPrefsKey(mapId)) ??
        const <String>[];
    return values.map(normalizeTagUuid).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> markDeletedSystemTagUuid(int mapId, String tagUuid) async {
    final normalized = normalizeTagUuid(tagUuid);
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _deletedSystemTagPrefsKey(mapId);
    final current = (prefs.getStringList(key) ?? const <String>[])
        .map(normalizeTagUuid)
        .where((e) => e.isNotEmpty)
        .toSet();
    if (!current.add(normalized)) return;
    await prefs.setStringList(key, current.toList()..sort());
  }

  Future<void> _clearDeletedSystemTagUuid(int mapId, String tagUuid) async {
    final normalized = normalizeTagUuid(tagUuid);
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _deletedSystemTagPrefsKey(mapId);
    final current = (prefs.getStringList(key) ?? const <String>[])
        .map(normalizeTagUuid)
        .where((e) => e.isNotEmpty)
        .toSet();
    if (!current.remove(normalized)) return;
    if (current.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setStringList(key, current.toList()..sort());
  }

  Future<void> clearDeletedRecordsForMap(int mapId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deletedSystemTagPrefsKey(mapId));
  }

  Future<EnsureSystemTagSummary> ensureForAllMaps({
    bool cleanupObsoleteSystemTags = true,
  }) async {
    final maps = await isar.gameMaps.where().findAll();
    if (maps.isEmpty) {
      return const EnsureSystemTagSummary(
        processedMaps: 0,
        addedTags: 0,
        updatedTags: 0,
        removedObsoleteTags: 0,
        keptObsoleteTagsInUse: 0,
        keptObsoleteTagDetails: <ObsoleteSystemTagUsageInfo>[],
      );
    }

    int added = 0;
    int updated = 0;
    int removed = 0;
    int keptInUse = 0;
    final keptDetails = <ObsoleteSystemTagUsageInfo>[];
    for (final map in maps) {
      final result = await _ensureForMap(
        map,
        cleanupObsoleteSystemTags: cleanupObsoleteSystemTags,
      );
      added += result.addedTags;
      updated += result.updatedTags;
      removed += result.removedObsoleteTags;
      keptInUse += result.keptObsoleteTagsInUse;
      keptDetails.addAll(result.keptObsoleteTagDetails);
    }
    return EnsureSystemTagSummary(
      processedMaps: maps.length,
      addedTags: added,
      updatedTags: updated,
      removedObsoleteTags: removed,
      keptObsoleteTagsInUse: keptInUse,
      keptObsoleteTagDetails: keptDetails,
    );
  }

  Future<void> ensureForMap(
    GameMap map, {
    String? mapNameFallback,
  }) async {
    await _ensureForMap(map, mapNameFallback: mapNameFallback);
  }

  Future<_EnsureSystemTagForMapResult> _ensureForMap(
    GameMap map, {
    String? mapNameFallback,
    bool cleanupObsoleteSystemTags = false,
  }) async {
    final mapName = map.name.trim().isNotEmpty
        ? map.name
        : (mapNameFallback?.trim().isNotEmpty == true
            ? mapNameFallback!.trim()
            : 'unknown');
    final required = _buildRequiredSystemTagDefs(map);
    if (required.isEmpty) {
      return const _EnsureSystemTagForMapResult(
        addedTags: 0,
        updatedTags: 0,
        removedObsoleteTags: 0,
        keptObsoleteTagsInUse: 0,
      );
    }

    final existingTags =
        await isar.tags.filter().mapIdEqualTo(map.id).findAll();
    final byAnyKey = <String, Tag>{};
    final bySystemKey = <String, Tag>{};
    final bySystemUuid = <String, Tag>{};
    int nextOrder = 0;
    for (final tag in existingTags) {
      final key = buildSystemTagKey(tag.dimension, tag.name);
      byAnyKey.putIfAbsent(key, () => tag);
      if (tag.isSystem) {
        bySystemKey.putIfAbsent(key, () => tag);
        final normalizedUuid = normalizeTagUuid(tag.tagUuid);
        if (normalizedUuid.isNotEmpty) {
          bySystemUuid.putIfAbsent(normalizedUuid, () => tag);
        }
      }
      if (tag.sortOrder >= nextOrder) {
        nextOrder = tag.sortOrder + 1;
      }
    }

    final toCreate = <Tag>[];
    final toUpdate = <Tag>[];
    final requiredUuids = <String>{};
    final requiredKeys =
        required.map((e) => buildSystemTagKey(e.dimension, e.name)).toSet();
    final deletedSystemTagUuids = await _loadDeletedSystemTagUuids(map.id);

    for (final def in required) {
      final key = buildSystemTagKey(def.dimension, def.name);
      final expectedUuid = TagUuidService.buildSystemTagUuid(
        mapName: mapName,
        mapIconPath: map.iconPath,
        dimension: def.dimension,
        tagName: def.name,
      );
      final normalizedExpectedUuid = normalizeTagUuid(expectedUuid);
      requiredUuids.add(normalizedExpectedUuid);

      final uuidMatched = bySystemUuid[normalizedExpectedUuid];
      final keyMatched = bySystemKey[key] ?? byAnyKey[key];
      final existing = uuidMatched ?? keyMatched;

      // 尊重用户手动删除的系统标签记录，避免启动时自动复活。
      if (uuidMatched == null &&
          deletedSystemTagUuids.contains(normalizedExpectedUuid)) {
        continue;
      }

      if (existing == null) {
        final created = Tag(
          tagUuid: expectedUuid,
          name: def.name,
          colorValue: def.colorValue,
          dimension: def.dimension,
          isSystem: true,
          sortOrder: nextOrder++,
          mapId: map.id,
        );
        toCreate.add(created);
        byAnyKey[key] = created;
        bySystemKey[key] = created;
        continue;
      }

      var changed = false;
      if (!existing.isSystem) {
        existing.isSystem = true;
        changed = true;
      }
      final preserveUserOverrides = uuidMatched != null &&
          buildSystemTagKey(existing.dimension, existing.name) != key;
      if (!preserveUserOverrides && existing.colorValue != def.colorValue) {
        existing.colorValue = def.colorValue;
        changed = true;
      }
      if (!preserveUserOverrides && existing.tagUuid.trim() != expectedUuid) {
        existing.tagUuid = expectedUuid;
        changed = true;
      }
      if (changed) {
        existing.updatedAt = DateTime.now();
        toUpdate.add(existing);
      }

      await _clearDeletedSystemTagUuid(map.id, expectedUuid);
    }

    final staleDeleteIds = <int>{};
    int keptStaleInUse = 0;
    final keptStaleDetails = <ObsoleteSystemTagUsageInfo>[];
    if (cleanupObsoleteSystemTags) {
      final staleSystemTags = existingTags.where((tag) {
        if (!tag.isSystem) return false;
        final key = buildSystemTagKey(tag.dimension, tag.name);
        final normalizedUuid = normalizeTagUuid(tag.tagUuid);
        return !requiredKeys.contains(key) &&
            !requiredUuids.contains(normalizedUuid);
      });

      Map<int, String>? layerNameById;
      for (final stale in staleSystemTags) {
        final grenadeBindings =
            await isar.grenadeTags.filter().tagIdEqualTo(stale.id).findAll();
        final areas =
            await isar.mapAreas.filter().tagIdEqualTo(stale.id).findAll();
        if (grenadeBindings.isNotEmpty || areas.isNotEmpty) {
          keptStaleInUse++;
          if (areas.isNotEmpty && layerNameById == null) {
            await map.layers.load();
            layerNameById = {
              for (final layer in map.layers) layer.id: layer.name,
            };
          }
          keptStaleDetails.add(
            await _buildObsoleteSystemTagUsageInfo(
              map: map,
              tag: stale,
              grenadeBindings: grenadeBindings,
              areas: areas,
              layerNameById: layerNameById ?? const <int, String>{},
            ),
          );
          continue;
        }
        staleDeleteIds.add(stale.id);
      }
    }

    if (toCreate.isEmpty && toUpdate.isEmpty && staleDeleteIds.isEmpty) {
      return _EnsureSystemTagForMapResult(
        addedTags: 0,
        updatedTags: 0,
        removedObsoleteTags: 0,
        keptObsoleteTagsInUse: keptStaleInUse,
        keptObsoleteTagDetails: keptStaleDetails,
      );
    }

    await isar.writeTxn(() async {
      if (toCreate.isNotEmpty) {
        await isar.tags.putAll(toCreate);
      }
      if (toUpdate.isNotEmpty) {
        await isar.tags.putAll(toUpdate);
      }
      for (final tagId in staleDeleteIds) {
        await isar.tags.delete(tagId);
      }
    });

    return _EnsureSystemTagForMapResult(
      addedTags: toCreate.length,
      updatedTags: toUpdate.length,
      removedObsoleteTags: staleDeleteIds.length,
      keptObsoleteTagsInUse: keptStaleInUse,
      keptObsoleteTagDetails: keptStaleDetails,
    );
  }

  /// 为历史标签补齐或去重规范化 UUID。
  Future<TagUuidMigrationSummary> ensureTagUuids() async {
    final tags = await isar.tags.where().findAll();
    if (tags.isEmpty) {
      return const TagUuidMigrationSummary(migratedCount: 0);
    }

    final mapIds = tags.map((e) => e.mapId).toSet();
    final mapById = <int, GameMap>{};
    for (final mapId in mapIds) {
      final map = await isar.gameMaps.get(mapId);
      if (map != null) {
        mapById[mapId] = map;
      }
    }

    final ordered = tags.toList()
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) {
          return a.isSystem ? -1 : 1;
        }
        return a.id.compareTo(b.id);
      });

    final occupied = <String>{};
    final toFix = <Tag>[];
    final details = <TagUuidMigrationDetail>[];
    for (final tag in ordered) {
      final current = tag.tagUuid.trim();
      var candidate = current;
      String? reason;

      if (tag.isSystem && (current.isEmpty || occupied.contains(current))) {
        final map = mapById[tag.mapId];
        if (map != null) {
          candidate = TagUuidService.buildSystemTagUuid(
            mapName: map.name,
            mapIconPath: map.iconPath,
            dimension: tag.dimension,
            tagName: tag.name,
          );
          reason = current.isEmpty ? '系统标签UUID为空' : '系统标签UUID冲突';
        }
      }

      if (candidate.isEmpty || occupied.contains(candidate)) {
        final previous = candidate;
        do {
          candidate = TagUuidService.newRandomUuid();
        } while (occupied.contains(candidate));
        reason = previous.isEmpty ? 'UUID为空' : 'UUID冲突';
      }

      occupied.add(candidate);
      if (candidate != current) {
        tag.tagUuid = candidate;
        tag.updatedAt = DateTime.now();
        toFix.add(tag);
        final map = mapById[tag.mapId];
        details.add(
          TagUuidMigrationDetail(
            tagId: tag.id,
            mapId: tag.mapId,
            mapName: map?.name ?? 'unknown',
            tagName: tag.name,
            dimension: tag.dimension,
            isSystem: tag.isSystem,
            oldUuid: current,
            newUuid: candidate,
            reason: reason ?? (current.isEmpty ? 'UUID为空' : 'UUID冲突'),
          ),
        );
      }
    }

    if (toFix.isEmpty) {
      return const TagUuidMigrationSummary(migratedCount: 0);
    }
    await isar.writeTxn(() async {
      await isar.tags.putAll(toFix);
    });
    return TagUuidMigrationSummary(
      migratedCount: toFix.length,
      details: details,
    );
  }

  Future<ObsoleteSystemTagUsageInfo> _buildObsoleteSystemTagUsageInfo({
    required GameMap map,
    required Tag tag,
    required List<GrenadeTag> grenadeBindings,
    required List<MapArea> areas,
    required Map<int, String> layerNameById,
  }) async {
    final grenadeRefs = <String>[];
    for (final binding in grenadeBindings) {
      final grenade = await isar.grenades.get(binding.grenadeId);
      if (grenade == null) continue;
      grenadeRefs.add('${grenade.title}#${grenade.id}');
    }
    grenadeRefs.sort();

    final areaRefs = areas.map((area) {
      final layerName = area.layerId == null
          ? 'Default'
          : (layerNameById[area.layerId!] ?? '未知楼层');
      return '${area.name}@$layerName#${area.id}';
    }).toList()
      ..sort();

    return ObsoleteSystemTagUsageInfo(
      mapId: map.id,
      mapName: map.name,
      tagId: tag.id,
      tagName: tag.name,
      tagUuid: tag.tagUuid,
      dimension: tag.dimension,
      grenadeRefs: grenadeRefs,
      areaRefs: areaRefs,
    );
  }

  List<_SystemTagDef> _buildRequiredSystemTagDefs(GameMap map) {
    final result = <_SystemTagDef>[];
    final seenKeys = <String>{};

    void addDef(int dimension, String name, int colorValue) {
      final key = buildSystemTagKey(dimension, name);
      if (!seenKeys.add(key)) return;
      result.add(_SystemTagDef(
        dimension: dimension,
        name: name,
        colorValue: colorValue,
      ));
    }

    for (final entry in commonSystemTags.entries) {
      final color = dimensionColors[entry.key] ?? 0xFF607D8B;
      for (final name in entry.value) {
        addDef(entry.key, name, color);
      }
    }

    final areaNames = resolveMapPreset(map, mapAreaPresets) ?? const <String>[];
    final areaColor = dimensionColors[TagDimension.area] ?? 0xFF4CAF50;
    for (final name in areaNames) {
      addDef(TagDimension.area, name, areaColor);
    }

    return result;
  }
}

class _EnsureSystemTagForMapResult {
  final int addedTags;
  final int updatedTags;
  final int removedObsoleteTags;
  final int keptObsoleteTagsInUse;
  final List<ObsoleteSystemTagUsageInfo> keptObsoleteTagDetails;

  const _EnsureSystemTagForMapResult({
    required this.addedTags,
    required this.updatedTags,
    required this.removedObsoleteTags,
    required this.keptObsoleteTagsInUse,
    this.keptObsoleteTagDetails = const <ObsoleteSystemTagUsageInfo>[],
  });
}

class _SystemTagDef {
  final int dimension;
  final String name;
  final int colorValue;

  const _SystemTagDef({
    required this.dimension,
    required this.name,
    required this.colorValue,
  });
}
