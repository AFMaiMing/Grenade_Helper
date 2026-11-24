import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import 'data_package_models.dart';
import 'data_sync_and_media_models.dart';
import 'package_archive_codec.dart';
import 'package_export_engine.dart';
import 'package_sync_helpers.dart';

class LanSyncPackageBuilder {
  final Isar isar;
  final PackageExportEngine exportEngine;

  LanSyncPackageBuilder(this.isar, this.exportEngine);

  Future<Map<String, GameMap>> _resolveScopeMaps(Set<String> mapKeys) async {
    final normalized =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const {};
    final maps = await isar.gameMaps.where().findAll();
    return {
      for (final map in maps)
        if (normalized.contains(map.name.trim())) map.name.trim(): map,
    };
  }

  Future<List<Grenade>> _loadScopedGrenades(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const [];
    final grenades = <Grenade>[];
    for (final map in scopedMaps.values) {
      await map.layers.load();
      for (final layer in map.layers) {
        await layer.grenades.load();
        grenades.addAll(layer.grenades);
      }
    }
    return grenades;
  }

  Future<Set<String>> _collectGrenadeFilesToZip(Grenade grenade) async {
    await grenade.steps.load();
    final files = <String>{};
    for (final step in grenade.steps) {
      await step.medias.load();
      for (final media in step.medias) {
        final path = media.localPath.trim();
        if (path.isNotEmpty) {
          files.add(path);
        }
      }
    }
    return files;
  }

  Future<Map<int, String>> _buildLayerNameById(
    Iterable<GameMap> maps,
  ) async {
    final result = <int, String>{};
    for (final map in maps) {
      await map.layers.load();
      for (final layer in map.layers) {
        result[layer.id] = layer.name;
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildGrenadeManifestItems(
    List<Grenade> grenades,
  ) async {
    if (grenades.isEmpty) return const {};
    final syncBundle = await buildLanSyncBundle(grenades);
    final result = <String, LanSyncManifestItem>{};
    for (var i = 0; i < grenades.length; i++) {
      final grenade = grenades[i];
      final rawData = Map<String, dynamic>.from(syncBundle.grenades[i]);
      final uniqueId = (rawData['uniqueId'] as String? ?? '').trim();
      final mapName = (rawData['mapName'] as String? ?? '').trim();
      if (uniqueId.isEmpty || mapName.isEmpty) continue;
      final filesToZip = await _collectGrenadeFilesToZip(grenade);
      result[uniqueId] = LanSyncManifestItem(
        key: uniqueId,
        mapName: mapName,
        digest: await buildLocalGrenadeDigest(grenade),
        updatedAtMs: grenade.updatedAt.millisecondsSinceEpoch,
        rawData: rawData,
        filesToZip: filesToZip,
      );
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildTagManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final result = <String, LanSyncManifestItem>{};
    for (final map in scopedMaps.values) {
      final tags = await isar.tags.filter().mapIdEqualTo(map.id).findAll();
      for (final tag in tags) {
        final tagUuid = tag.tagUuid.trim();
        if (tagUuid.isEmpty) continue;
        final payload = PackageTagData(
          tagUuid: tagUuid,
          mapName: map.name,
          name: tag.name,
          dimension: tag.dimension,
          colorValue: tag.colorValue,
          groupName: tag.groupName,
          isSystem: tag.isSystem,
          updatedAt: tag.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        result[tagUuid] = LanSyncManifestItem(
          key: tagUuid,
          mapName: map.name,
          digest: digestJsonValue(normalizePayloadForSyncDigest(payload)),
          updatedAtMs: tag.updatedAt.millisecondsSinceEpoch,
          rawData: payload,
        );
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildAreaManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final tagsById = <int, Tag>{};
    final layerNameById = await _buildLayerNameById(scopedMaps.values);
    final result = <String, LanSyncManifestItem>{};
    for (final map in scopedMaps.values) {
      final areas = await isar.mapAreas.filter().mapIdEqualTo(map.id).findAll();
      for (final area in areas) {
        final tag = tagsById[area.tagId] ?? await isar.tags.get(area.tagId);
        if (tag == null) continue;
        tagsById[area.tagId] = tag;
        final tagUuid = tag.tagUuid.trim();
        if (tagUuid.isEmpty) continue;
        final layerName = area.layerId == null
            ? 'Default'
            : (layerNameById[area.layerId!] ?? 'Default');
        final payload = PackageAreaData(
          tagUuid: tagUuid,
          mapName: map.name,
          layerName: layerName,
          name: area.name,
          colorValue: area.colorValue,
          strokes: area.strokes,
          createdAt: area.createdAt.millisecondsSinceEpoch,
          updatedAt: area.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        final key =
            buildAreaTombstoneKey(tagUuid: tagUuid, layerName: layerName);
        final current = result[key];
        final updatedAtMs = area.updatedAt.millisecondsSinceEpoch;
        if (current == null || updatedAtMs >= current.updatedAtMs) {
          result[key] = LanSyncManifestItem(
            key: key,
            mapName: map.name,
            digest: digestJsonValue(normalizePayloadForSyncDigest(payload)),
            updatedAtMs: updatedAtMs,
            rawData: payload,
          );
        }
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildMapManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final result = <String, LanSyncManifestItem>{};
    for (final map in scopedMaps.values) {
      if (isBuiltinAssetMap(map)) continue;
      final filesToZip = <String>{};
      final packageMap = await exportEngine.buildPackageMapData(
        map,
        filesToZip: filesToZip,
      );
      if (packageMap == null) continue;
      final mapName = packageMap.mapName.trim();
      if (mapName.isEmpty) continue;
      final payload = packageMap.toJson();
      final digestPayload = await _buildMapDigestPayload(packageMap);
      result[mapName] = LanSyncManifestItem(
        key: mapName,
        mapName: mapName,
        digest: digestJsonValue(normalizePayloadForSyncDigest(digestPayload)),
        updatedAtMs: 0,
        rawData: payload,
        filesToZip: filesToZip,
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> _buildMapDigestPayload(
    PackageMapData mapData,
  ) async {
    final layerDigests = <Map<String, dynamic>>[];
    for (final layer in mapData.layers) {
      layerDigests.add({
        'name': layer.name,
        'sortOrder': layer.sortOrder,
        'assetDigest': await _buildMapMediaDigestToken(layer.assetPath),
      });
    }
    return {
      'mapName': mapData.mapName,
      'backgroundDigest':
          await _buildMapMediaDigestToken(mapData.backgroundPath),
      'iconDigest': await _buildMapMediaDigestToken(mapData.iconPath),
      'layers': layerDigests,
    };
  }

  Future<String> _buildMapMediaDigestToken(String rawPath) async {
    final normalized = rawPath.trim();
    if (normalized.isEmpty) return '';
    if (isAssetPath(normalized)) return 'asset:$normalized';
    final hash = await sha256FileHex(normalized);
    if (hash.isNotEmpty) return 'sha256:$hash';
    final fileName = extractArchiveFileNameFromPackagePath(normalized);
    return fileName.isEmpty ? 'missing' : 'missing:$fileName';
  }

  Future<Map<String, LanSyncManifestItem>> _buildFavoriteFolderManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final result = <String, LanSyncManifestItem>{};
    for (final map in scopedMaps.values) {
      final folders =
          await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
      for (final folder in folders) {
        final nameKey = folder.nameKey.trim().isEmpty
            ? normalizeFolderNameKey(folder.name)
            : normalizeFolderNameKey(folder.nameKey);
        if (nameKey.isEmpty) continue;
        final payload = PackageFavoriteFolderData(
          mapName: map.name,
          name: folder.name,
          nameKey: nameKey,
          sortOrder: folder.sortOrder,
          createdAt: folder.createdAt.millisecondsSinceEpoch,
          updatedAt: folder.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        final key = buildFavoriteFolderTombstoneKey(
            mapName: map.name, nameKey: nameKey);
        result[key] = LanSyncManifestItem(
          key: key,
          mapName: map.name,
          digest: digestJsonValue(normalizePayloadForSyncDigest(payload)),
          updatedAtMs: folder.updatedAt.millisecondsSinceEpoch,
          rawData: payload,
        );
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildImpactGroupManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final layerNameById = await _buildLayerNameById(scopedMaps.values);
    final mapNameByLayerId = <int, String>{};
    for (final map in scopedMaps.values) {
      await map.layers.load();
      for (final layer in map.layers) {
        mapNameByLayerId[layer.id] = map.name;
      }
    }
    final result = <String, LanSyncManifestItem>{};
    for (final entry in mapNameByLayerId.entries) {
      final groups =
          await isar.impactGroups.filter().layerIdEqualTo(entry.key).findAll();
      final mapName = entry.value;
      final layerName = layerNameById[entry.key] ?? 'Default';
      for (final group in groups) {
        final payload = PackageImpactGroupData(
          mapName: mapName,
          layerName: layerName,
          name: group.name,
          type: group.type,
          impactXRatio: group.impactXRatio,
          impactYRatio: group.impactYRatio,
          createdAt: group.createdAt.millisecondsSinceEpoch,
          updatedAt: group.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        final key = buildImpactGroupTombstoneKey(
          mapName: mapName,
          layerName: layerName,
          type: group.type,
          name: group.name,
          impactXRatio: group.impactXRatio,
          impactYRatio: group.impactYRatio,
        );
        result[key] = LanSyncManifestItem(
          key: key,
          mapName: mapName,
          digest: digestJsonValue(normalizePayloadForSyncDigest(payload)),
          updatedAtMs: group.updatedAt.millisecondsSinceEpoch,
          rawData: payload,
        );
      }
    }
    return result;
  }

  Future<LanSyncManifestBundle> buildLanSyncManifest({
    required Set<String> mapKeys,
  }) async {
    final scopedMaps = await _resolveScopeMaps(mapKeys);
    if (scopedMaps.isEmpty) {
      return const LanSyncManifestBundle();
    }
    final grenades = await _loadScopedGrenades(scopedMaps);
    final grenadeItems = await _buildGrenadeManifestItems(grenades);
    final tagItems = await _buildTagManifestItems(scopedMaps);
    final areaItems = await _buildAreaManifestItems(scopedMaps);
    final mapItems = await _buildMapManifestItems(scopedMaps);
    final favoriteFolderItems =
        await _buildFavoriteFolderManifestItems(scopedMaps);
    final impactGroupItems = await _buildImpactGroupManifestItems(scopedMaps);
    return LanSyncManifestBundle(
      grenades: grenadeItems,
      tags: tagItems,
      areas: areaItems,
      maps: mapItems,
      favoriteFolders: favoriteFolderItems,
      impactGroups: impactGroupItems,
    );
  }

  Future<List<Grenade>> _resolveExportGrenades({
    required int scopeType,
    Grenade? singleGrenade,
    GameMap? singleMap,
    List<Grenade>? explicitGrenades,
  }) async {
    if (explicitGrenades != null) return explicitGrenades;

    final grenades = <Grenade>[];
    if (scopeType == 0 && singleGrenade != null) {
      grenades.add(singleGrenade);
    } else if (scopeType == 1 && singleMap != null) {
      singleMap.layers.loadSync();
      for (final layer in singleMap.layers) {
        layer.grenades.loadSync();
        grenades.addAll(layer.grenades);
      }
    } else {
      grenades.addAll(isar.grenades.where().findAllSync());
    }
    return grenades;
  }

  Future<LanSyncExportBundle> buildLanSyncBundle(
    List<Grenade> grenades, {
    List<PackageGrenadeTombstoneData> grenadeTombstones = const [],
    List<PackageEntityTombstoneData> entityTombstones = const [],
  }) async {
    final base = await exportEngine.buildExportBundle(grenades);
    final grenadeItems = base.grenades
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    final usedFolderIds = <int>{};
    final usedImpactGroupIds = <int>{};

    for (var i = 0; i < grenades.length; i++) {
      final g = grenades[i];
      final item = grenadeItems[i];

      item['isFavorite'] = g.isFavorite;
      item['favoriteFolderRef'] = null;
      item['impactGroupRef'] = null;

      if (g.isFavorite && g.favoriteFolderId != null) {
        usedFolderIds.add(g.favoriteFolderId!);
      }
      if (g.impactGroupId != null) {
        usedImpactGroupIds.add(g.impactGroupId!);
      }
    }

    final folderBundle =
        await exportEngine.buildFavoriteFoldersAndRefs(usedFolderIds);
    final groupBundle =
        await exportEngine.buildImpactGroupsAndRefs(usedImpactGroupIds);

    exportEngine.applyFolderAndGroupRefsToGrenades(
      grenades,
      grenadeItems,
      folderBundle.refById,
      groupBundle.refById,
    );

    return LanSyncExportBundle(
      grenades: grenadeItems,
      tags: base.tags,
      areas: base.areas,
      maps: base.maps,
      favoriteFolders: folderBundle.payloads,
      impactGroups: groupBundle.payloads,
      grenadeTombstones:
          grenadeTombstones.map((e) => e.toJson()).toList(growable: false),
      entityTombstones:
          entityTombstones.map((e) => e.toJson()).toList(growable: false),
      filesToZip: base.filesToZip,
    );
  }

  // 构建局域网同步专用包（schemaVersion=7），与普通导出流隔离
  Future<String> buildLanSyncPackageToTemp({
    required int scopeType,
    Grenade? singleGrenade,
    GameMap? singleMap,
    List<Grenade>? explicitGrenades,
    List<Map<String, dynamic>> explicitGrenadePayloads = const [],
    List<Map<String, dynamic>> explicitTagPayloads = const [],
    List<Map<String, dynamic>> explicitAreaPayloads = const [],
    List<Map<String, dynamic>> explicitMapPayloads = const [],
    List<Map<String, dynamic>> explicitFavoriteFolderPayloads = const [],
    List<Map<String, dynamic>> explicitImpactGroupPayloads = const [],
    Set<String> explicitFilesToZip = const <String>{},
    List<PackageGrenadeTombstoneData> grenadeTombstones = const [],
    List<PackageEntityTombstoneData> entityTombstones = const [],
  }) async {
    final hasExplicitPayloads = explicitGrenadePayloads.isNotEmpty ||
        explicitTagPayloads.isNotEmpty ||
        explicitAreaPayloads.isNotEmpty ||
        explicitMapPayloads.isNotEmpty ||
        explicitFavoriteFolderPayloads.isNotEmpty ||
        explicitImpactGroupPayloads.isNotEmpty ||
        grenadeTombstones.isNotEmpty ||
        entityTombstones.isNotEmpty;
    final List<Grenade> grenades = hasExplicitPayloads
        ? const []
        : await _resolveExportGrenades(
            scopeType: scopeType,
            singleGrenade: singleGrenade,
            singleMap: singleMap,
            explicitGrenades: explicitGrenades,
          );
    if (!hasExplicitPayloads &&
        grenades.isEmpty &&
        grenadeTombstones.isEmpty &&
        entityTombstones.isEmpty) {
      throw StateError('没有可同步的道具');
    }

    final syncBundle = hasExplicitPayloads
        ? LanSyncExportBundle(
            grenades: explicitGrenadePayloads,
            tags: explicitTagPayloads,
            areas: explicitAreaPayloads,
            maps: explicitMapPayloads,
            favoriteFolders: explicitFavoriteFolderPayloads,
            impactGroups: explicitImpactGroupPayloads,
            grenadeTombstones: grenadeTombstones
                .map((e) => e.toJson())
                .toList(growable: false),
            entityTombstones:
                entityTombstones.map((e) => e.toJson()).toList(growable: false),
            filesToZip: explicitFilesToZip,
          )
        : await buildLanSyncBundle(
            grenades,
            grenadeTombstones: grenadeTombstones,
            entityTombstones: entityTombstones,
          );
    if (syncBundle.grenades.isEmpty &&
        syncBundle.tags.isEmpty &&
        syncBundle.areas.isEmpty &&
        syncBundle.maps.isEmpty &&
        syncBundle.favoriteFolders.isEmpty &&
        syncBundle.impactGroups.isEmpty &&
        grenadeTombstones.isEmpty &&
        entityTombstones.isEmpty) {
      throw StateError('当前范围没有可同步的增量变更');
    }
    final tempDir = await getTemporaryDirectory();
    final exportDirPath = p.join(tempDir.path, 'lan_sync_export_temp');
    final zipPath = p.join(tempDir.path, 'lan_sync_data.cs2pkg');

    await compute(
      packageFilesInIsolate,
      PackageParams(
        exportDirPath: exportDirPath,
        zipPath: zipPath,
        jsonData: jsonEncode(syncBundle.toJson()),
        filesToCopy: syncBundle.filesToZip.toList(),
        schemaVersion: lanSyncSchemaVersion,
        packageType: packageTypeLanSync,
      ),
    );

    return zipPath;
  }

  Future<List<Grenade>> loadGrenadesByUniqueIds(
    Iterable<String> uniqueIds,
  ) async {
    final normalized =
        uniqueIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const [];
    final all = await isar.grenades.where().findAll();
    return all
        .where((g) => normalized.contains((g.uniqueId ?? '').trim()))
        .toList(growable: false);
  }

  Future<Map<String, GrenadePreviewItem>>
      loadLocalGrenadePreviewItemsByUniqueIds(
    Iterable<String> uniqueIds,
  ) async {
    final normalized =
        uniqueIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const {};

    final all = await isar.grenades.where().findAll();
    final matched = all
        .where((g) => normalized.contains((g.uniqueId ?? '').trim()))
        .toList(growable: false);
    if (matched.isEmpty) return const {};

    final result = <String, GrenadePreviewItem>{};
    for (final grenade in matched) {
      final uniqueId = (grenade.uniqueId ?? '').trim();
      if (uniqueId.isEmpty) continue;

      await grenade.layer.load();
      final layer = grenade.layer.value;
      await layer?.map.load();
      final map = layer?.map.value;
      await grenade.steps.load();

      final stepsData = <Map<String, dynamic>>[];
      for (final step in grenade.steps) {
        await step.medias.load();
        final mediaData = <Map<String, dynamic>>[];
        for (final media in step.medias) {
          mediaData.add({
            'path': media.localPath,
            'type': media.type,
          });
        }
        stepsData.add({
          'title': step.title,
          'description': step.description,
          'index': step.stepIndex,
          'medias': mediaData,
        });
      }

      final rawData = <String, dynamic>{
        'uniqueId': uniqueId,
        'mapName': map?.name ?? '',
        'layerName': layer?.name ?? '',
        'title': grenade.title,
        'type': grenade.type,
        'team': grenade.team,
        'author': grenade.author,
        'sourceUrl': grenade.sourceUrl,
        'sourceNote': grenade.sourceNote,
        'hasLocalEdits': grenade.hasLocalEdits,
        'x': grenade.xRatio,
        'y': grenade.yRatio,
        'impactX': grenade.impactXRatio,
        'impactY': grenade.impactYRatio,
        'impactAreaStrokes': grenade.impactAreaStrokes,
        'steps': stepsData,
        'createdAt': grenade.createdAt.millisecondsSinceEpoch,
        'updatedAt': grenade.updatedAt.millisecondsSinceEpoch,
      };

      result[uniqueId] = GrenadePreviewItem(
        rawData: rawData,
        uniqueId: uniqueId,
        title: grenade.title,
        type: grenade.type,
        mapName: map?.name ?? '',
        layerName: layer?.name ?? '',
        author: grenade.author,
        status: ImportStatus.skip,
        updatedAt: grenade.updatedAt,
      );
    }

    return result;
  }

  Future<Map<String, Map<String, String>>> buildGrenadeDigestByMap({
    required Set<String> mapKeys,
  }) async {
    final normalized =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const {};

    final result = <String, Map<String, String>>{
      for (final mapKey in normalized) mapKey: <String, String>{},
    };

    final mapByName = <String, GameMap>{};
    final allMaps = await isar.gameMaps.where().findAll();
    for (final map in allMaps) {
      final name = map.name.trim();
      if (name.isNotEmpty && normalized.contains(name)) {
        mapByName[name] = map;
      }
    }

    final scopedGrenades = <Grenade>[];
    for (final mapKey in normalized) {
      final map = mapByName[mapKey];
      if (map == null) continue;
      await map.layers.load();
      for (final layer in map.layers) {
        await layer.grenades.load();
        scopedGrenades.addAll(layer.grenades);
      }
    }
    if (scopedGrenades.isEmpty) return result;

    final exportBundle = await exportEngine.buildExportBundle(scopedGrenades);
    for (final raw in exportBundle.grenades) {
      final item = Map<String, dynamic>.from(raw);
      final mapName = (item['mapName'] as String? ?? '').trim();
      if (!normalized.contains(mapName)) continue;
      final uniqueId = (item['uniqueId'] as String? ?? '').trim();
      if (uniqueId.isEmpty) continue;
      result.putIfAbsent(mapName, () => <String, String>{});
      result[mapName]![uniqueId] = digestJsonValue(item);
    }

    return result;
  }

  Future<String> buildLocalGrenadeDigest(
    Grenade grenade, {
    bool includeLanSyncRefs = true,
  }) async {
    final bundle = await buildLanSyncBundle([grenade]);
    if (bundle.grenades.isEmpty) return '';
    final raw = bundle.grenades.first;
    final normalized = normalizeGrenadePayloadForSync(raw);
    if (!includeLanSyncRefs) {
      normalized.remove('isFavorite');
      normalized.remove('favoriteFolderRef');
      normalized.remove('impactGroupRef');
    }
    await grenade.steps.load();
    final localSteps = grenade.steps.toList(growable: false);
    final sharedSteps = ((normalized['steps'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    for (var i = 0; i < sharedSteps.length; i++) {
      final medias =
          ((sharedSteps[i]['medias'] as List?) ?? const []).cast<dynamic>();
      if (i >= localSteps.length) continue;
      final localStep = localSteps[i];
      await localStep.medias.load();
      final localMedias = localStep.medias.toList(growable: false);
      final normalizedMedias = <Map<String, dynamic>>[];
      for (var j = 0; j < medias.length; j++) {
        final mediaMap = Map<String, dynamic>.from(medias[j] as Map);
        final mediaHash = j < localMedias.length
            ? await sha256FileHex(localMedias[j].localPath)
            : '';
        normalizedMedias.add({
          'type': mediaMap['type'],
          'contentHash': mediaHash,
        });
      }
      sharedSteps[i]['medias'] = normalizedMedias;
    }
    normalized['steps'] = sharedSteps;
    return digestJsonValue(normalized);
  }

  Future<bool> shouldImportGrenadeOverLocal(
    Grenade local,
    Map<String, dynamic> shared,
    Map<String, String> packageFileHashes,
  ) async {
    final sharedUpdatedAtMs = shared['updatedAt'] as int? ?? 0;
    final localUpdatedAtMs = local.updatedAt.millisecondsSinceEpoch;
    if (sharedUpdatedAtMs > localUpdatedAtMs) return true;
    if (sharedUpdatedAtMs < localUpdatedAtMs) return false;
    final includeLanSyncRefs = shared.containsKey('isFavorite') ||
        shared.containsKey('favoriteFolderRef') ||
        shared.containsKey('impactGroupRef');
    final localDigest = await buildLocalGrenadeDigest(
      local,
      includeLanSyncRefs: includeLanSyncRefs,
    );
    final sharedDigest = buildSharedGrenadeDigest(shared, packageFileHashes);
    return localDigest != sharedDigest;
  }
}
