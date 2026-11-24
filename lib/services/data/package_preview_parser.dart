import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import '../../models.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import '../lan_sync/lan_sync_local_store.dart';
import 'data_package_models.dart';
import 'lan_sync_package_builder.dart';
import 'package_archive_codec.dart';
import 'package_sync_helpers.dart';

class PackagePreviewParser {
  final Isar isar;
  final LanSyncPackageBuilder lanSyncBuilder;

  PackagePreviewParser(this.isar, this.lanSyncBuilder);

  Future<PackagePreviewResult?> previewPackage(
    String filePath, {
    ImportPackageMode mode = ImportPackageMode.normal,
    bool requireTrustedPackage = false,
  }) async {
    if (!filePath.toLowerCase().endsWith('.cs2pkg')) {
      return null;
    }

    final file = File(filePath);
    if (!file.existsSync()) return null;
    if (file.lengthSync() > maxImportPackageSizeBytes) {
      return null;
    }

    return withOpenedCs2PackageArchive(filePath, (archive) async {
      if (archive == null) return null;
      final archiveFiles =
          archive.where((entry) => entry.isFile).toList(growable: false);

      final archiveFilesByName = <String, ArchiveFile>{};
      var expandedSize = 0;
      for (final archiveFile in archiveFiles) {
        final fileName = p.basename(archiveFile.name).trim();
        if (fileName.isEmpty) return null;
        if (archiveFilesByName.containsKey(fileName)) {
          return null;
        }
        if (archiveFile.size < 0 ||
            archiveFile.size > maxImportPackageEntrySizeBytes) {
          return null;
        }
        expandedSize += archiveFile.size;
        if (expandedSize > maxImportPackageExpandedSizeBytes) {
          return null;
        }
        archiveFilesByName[fileName] = archiveFile;
      }
      final importableFileCount = archiveFilesByName.keys
          .where((name) =>
              name != packageDataFileName && name != packageManifestFileName)
          .length;
      if (importableFileCount > maxImportPackageFileCount) {
        return null;
      }

      List<int>? dataBytes;
      var packageType = packageTypeExport;
      var schemaVersion = 1;
      var isTrustedPackage = false;
      var isLegacyPackage = true;
      final availablePackageFiles = <String>{};
      final packageFileHashes = <String, String>{};
      final packageFileSizes = <String, int>{};

      final manifestArchiveFile = archiveFilesByName[packageManifestFileName];
      if (manifestArchiveFile != null) {
        final manifestDecoded =
            jsonDecode(utf8.decode(manifestArchiveFile.content));
        if (manifestDecoded is! Map<String, dynamic>) {
          return null;
        }
        final manifest = PackageManifestData.fromJson(manifestDecoded);
        if (!manifest.isValid) return null;

        final manifestNames = manifest.files.map((entry) => entry.path).toSet();
        final actualNames = archiveFilesByName.keys
            .where((name) => name != packageManifestFileName)
            .toSet();
        if (manifest.files.length != manifestNames.length) {
          return null;
        }
        if (actualNames.length != manifestNames.length ||
            !actualNames.containsAll(manifestNames) ||
            !manifestNames.containsAll(actualNames)) {
          return null;
        }

        final manifestFilesJson = <Map<String, dynamic>>[];
        for (final entry in manifest.files) {
          final archiveFile = archiveFilesByName[entry.path];
          if (archiveFile == null) return null;
          if (archiveFile.size != entry.sizeBytes) {
            return null;
          }
          final contentBytes = archiveFile.content;
          final digest = sha256BytesHex(contentBytes);
          if (digest != entry.sha256) {
            return null;
          }
          manifestFilesJson.add(entry.toJson());
          if (entry.path == packageDataFileName) {
            dataBytes = contentBytes;
          } else {
            availablePackageFiles.add(entry.path);
            packageFileHashes[entry.path] = digest;
            packageFileSizes[entry.path] = entry.sizeBytes;
          }
          archiveFile.clear();
        }

        if (dataBytes == null) {
          return null;
        }

        final expectedHmac = computePackageContentHmac(
          schemaVersion: manifest.schemaVersion,
          packageType: manifest.packageType,
          createdAtMs: manifest.createdAt,
          files: manifestFilesJson,
        );
        if (expectedHmac != manifest.contentHmac) {
          return null;
        }

        schemaVersion = manifest.schemaVersion;
        packageType = manifest.packageType;
        isTrustedPackage = true;
        isLegacyPackage = false;
      } else {
        if (requireTrustedPackage) {
          return null;
        }
        final dataArchiveFile = archiveFilesByName[packageDataFileName];
        if (dataArchiveFile == null) {
          return null;
        }
        dataBytes = dataArchiveFile.content;
        for (final entry in archiveFilesByName.entries) {
          if (entry.key == packageDataFileName) continue;
          if (entry.key == packageManifestFileName) continue;
          availablePackageFiles.add(entry.key);
          packageFileSizes[entry.key] = entry.value.size;
          final entryBytes = entry.value.content;
          packageFileHashes[entry.key] = sha256BytesHex(entryBytes);
          entry.value.clear();
        }
      }

      if (requireTrustedPackage && !isTrustedPackage) {
        return null;
      }

      List<dynamic> grenadesData = [];
      final tagsByUuid = <String, PackageTagData>{};
      final areas = <PackageAreaData>[];
      final favoriteFolders = <PackageFavoriteFolderData>[];
      final impactGroups = <PackageImpactGroupData>[];
      final maps = <PackageMapData>[];
      final grenadeTombstones = <PackageGrenadeTombstoneData>[];
      final entityTombstones = <PackageEntityTombstoneData>[];
      final decoded = jsonDecode(utf8.decode(dataBytes));
      if (decoded is Map<String, dynamic>) {
        schemaVersion = decoded['schemaVersion'] as int? ?? schemaVersion;
        final grenadesRaw = decoded['grenades'];
        if (grenadesRaw is List) {
          grenadesData = grenadesRaw;
        }
        final tagsRaw = decoded['tags'];
        if (tagsRaw is List) {
          for (final raw in tagsRaw) {
            if (raw is! Map<String, dynamic>) continue;
            final tag = PackageTagData.fromJson(raw);
            if (tag.tagUuid.isEmpty) continue;
            tagsByUuid[tag.tagUuid] = tag;
          }
        }
        final areasRaw = decoded['areas'];
        if (areasRaw is List) {
          for (final raw in areasRaw) {
            if (raw is! Map<String, dynamic>) continue;
            final area = PackageAreaData.fromJson(raw);
            if (area.tagUuid.isEmpty) continue;
            areas.add(area);
          }
        }
        final favoriteFoldersRaw = decoded['favoriteFolders'];
        if (favoriteFoldersRaw is List) {
          for (final raw in favoriteFoldersRaw) {
            if (raw is! Map<String, dynamic>) continue;
            final folder = PackageFavoriteFolderData.fromJson(raw);
            if (folder.mapName.isEmpty || folder.nameKey.isEmpty) continue;
            favoriteFolders.add(folder);
          }
        }
        final impactGroupsRaw = decoded['impactGroups'];
        if (impactGroupsRaw is List) {
          for (final raw in impactGroupsRaw) {
            if (raw is! Map<String, dynamic>) continue;
            final group = PackageImpactGroupData.fromJson(raw);
            if (group.mapName.isEmpty ||
                group.layerName.isEmpty ||
                group.name.isEmpty) {
              continue;
            }
            impactGroups.add(group);
          }
        }
        final mapsRaw = decoded['maps'];
        if (mapsRaw is List) {
          final byName = <String, PackageMapData>{};
          for (final raw in mapsRaw) {
            if (raw is! Map) continue;
            final mapData = PackageMapData.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (mapData.mapName.isEmpty) continue;
            byName[mapData.mapName] = mapData;
          }
          maps.addAll(byName.values);
        }
        final allowTombstonesInPreview =
            mode == ImportPackageMode.lanSync && isTrustedPackage;
        final grenadeTombstonesRaw = decoded['grenadeTombstones'];
        if (allowTombstonesInPreview && grenadeTombstonesRaw is List) {
          for (final raw in grenadeTombstonesRaw) {
            if (raw is! Map<String, dynamic>) continue;
            final tombstone = PackageGrenadeTombstoneData.fromJson(raw);
            if (tombstone.uniqueId.isEmpty || tombstone.mapName.isEmpty) {
              continue;
            }
            grenadeTombstones.add(tombstone);
          }
        }
        final entityTombstonesRaw = decoded['entityTombstones'];
        if (allowTombstonesInPreview && entityTombstonesRaw is List) {
          for (final raw in entityTombstonesRaw) {
            if (raw is! Map<String, dynamic>) continue;
            final tombstone = PackageEntityTombstoneData.fromJson(raw);
            if (!LanSyncEntityTombstoneType.values
                    .contains(tombstone.entityType) ||
                tombstone.entityKey.isEmpty ||
                tombstone.mapName.isEmpty) {
              continue;
            }
            entityTombstones.add(tombstone);
          }
        }
      } else if (decoded is List) {
        grenadesData = decoded;
        schemaVersion = 1;
      }

      if (grenadesData.isEmpty &&
          tagsByUuid.isEmpty &&
          areas.isEmpty &&
          favoriteFolders.isEmpty &&
          impactGroups.isEmpty &&
          maps.isEmpty &&
          grenadeTombstones.isEmpty &&
          entityTombstones.isEmpty) {
        return null;
      }

      // 过滤本地已有的内置地图，避免预览和同步触碰客户端内置资源
      if (maps.isNotEmpty) {
        final filteredMaps = <PackageMapData>[];
        for (final mapData in maps) {
          final local = await isar.gameMaps
              .filter()
              .nameEqualTo(mapData.mapName)
              .findFirst();
          if (local != null && isBuiltinAssetMap(local)) continue;
          filteredMaps.add(mapData);
        }
        maps
          ..clear()
          ..addAll(filteredMaps);
      }

      final grenadesByMap = <String, List<GrenadePreviewItem>>{};

      for (final item in grenadesData) {
        final mapName = item['mapName'] as String? ?? 'Unknown';
        final layerName = item['layerName'] as String? ?? 'Default';
        final title = item['title'] as String? ?? '';
        final type = item['type'] as int? ?? 0;
        final author = item['author'] as String?;
        final importedUniqueId = item['uniqueId'] as String?;
        final xRatio = (item['x'] as num?)?.toDouble() ?? 0.0;
        final yRatio = (item['y'] as num?)?.toDouble() ?? 0.0;
        final importedUpdatedAt = item['updatedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
            : DateTime.now();

        final uniqueId =
            importedUniqueId ?? '${mapName}_${title}_${xRatio}_$yRatio';
        var status = ImportStatus.newItem;

        final map =
            await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
        if (map != null) {
          final layer = await resolveTargetLayerForImport(map, layerName);
          if (layer != null) {
            final existing = await findExistingGrenadeForImport(
              isar,
              layer,
              importedUniqueId: importedUniqueId,
              title: title,
              xRatio: xRatio,
              yRatio: yRatio,
            );
            if (existing != null) {
              if (await lanSyncBuilder.shouldImportGrenadeOverLocal(
                existing,
                item,
                packageFileHashes,
              )) {
                status = ImportStatus.update;
              } else {
                status = ImportStatus.skip;
              }
            }
          }
        }

        final previewItem = GrenadePreviewItem(
          rawData: item,
          uniqueId: uniqueId,
          title: title,
          type: type,
          mapName: mapName,
          layerName: layerName,
          author: author,
          status: status,
          updatedAt: importedUpdatedAt,
        );

        grenadesByMap.putIfAbsent(mapName, () => []);
        grenadesByMap[mapName]!.add(previewItem);
      }

      final metadataPreviewCounts = await _buildMetadataPreviewCounts(
        tagsByUuid: tagsByUuid,
        areas: areas,
        favoriteFolders: favoriteFolders,
        impactGroups: impactGroups,
        maps: maps,
        packageFileHashes: packageFileHashes,
      );

      return PackagePreviewResult(
        grenadesByMap: grenadesByMap,
        filePath: filePath,
        memoryImages: const {},
        schemaVersion: schemaVersion,
        packageType: packageType,
        isTrustedPackage: isTrustedPackage,
        isLegacyPackage: isLegacyPackage,
        packageFileHashes: packageFileHashes,
        packageFileSizes: packageFileSizes,
        availablePackageFiles: availablePackageFiles,
        tagsByUuid: tagsByUuid,
        areas: areas,
        favoriteFolders: favoriteFolders,
        impactGroups: impactGroups,
        maps: maps,
        grenadeTombstones: grenadeTombstones,
        entityTombstones: entityTombstones,
        changedTagCount: metadataPreviewCounts.tags,
        changedAreaCount: metadataPreviewCounts.areas,
        changedFavoriteFolderCount: metadataPreviewCounts.favoriteFolders,
        changedImpactGroupCount: metadataPreviewCounts.impactGroups,
        changedMapCount: metadataPreviewCounts.maps,
      );
    });
  }

  Future<MetadataPreviewCounts> _buildMetadataPreviewCounts({
    required Map<String, PackageTagData> tagsByUuid,
    required List<PackageAreaData> areas,
    required List<PackageFavoriteFolderData> favoriteFolders,
    required List<PackageImpactGroupData> impactGroups,
    required List<PackageMapData> maps,
    required Map<String, String> packageFileHashes,
  }) async {
    final changedTags = await _countChangedPreviewTags(tagsByUuid);
    final changedAreas = await _countChangedPreviewAreas(areas);
    final changedFavoriteFolders =
        await _countChangedPreviewFavoriteFolders(favoriteFolders);
    final changedImpactGroups =
        await _countChangedPreviewImpactGroups(impactGroups);
    final changedMaps = await _countChangedPreviewMaps(
      maps,
      packageFileHashes: packageFileHashes,
    );
    return MetadataPreviewCounts(
      tags: changedTags,
      areas: changedAreas,
      favoriteFolders: changedFavoriteFolders,
      impactGroups: changedImpactGroups,
      maps: changedMaps,
    );
  }

  Future<int> _countChangedPreviewTags(
    Map<String, PackageTagData> tagsByUuid,
  ) async {
    if (tagsByUuid.isEmpty) return 0;
    final mapNames = tagsByUuid.values
        .map((e) => e.mapName.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final context = await buildLocalTagContext(isar, mapNames);
    var count = 0;
    for (final shared in tagsByUuid.values) {
      if (shared.tagUuid.trim().isEmpty || shared.mapName.trim().isEmpty) {
        continue;
      }
      final map = context.mapByName[shared.mapName];
      if (map == null) {
        count++;
        continue;
      }
      final localByUuid = context.localByUuid[shared.tagUuid];
      if (localByUuid != null) {
        final contentDifferent = isTagDifferent(localByUuid, shared);
        if (requiresManualConflictResolution(
              sharedUpdatedAtMs: shared.updatedAt,
              localUpdatedAtMs: localByUuid.updatedAt.millisecondsSinceEpoch,
              contentDifferent: contentDifferent,
            ) ||
            (shared.updatedAt > localByUuid.updatedAt.millisecondsSinceEpoch &&
                contentDifferent)) {
          count++;
        }
        continue;
      }
      final semanticTag = context.localBySemantic[
          semanticTagKey(map.id, shared.dimension, shared.name)];
      if (semanticTag != null) {
        final contentDifferent = isTagDifferent(semanticTag, shared) ||
            semanticTag.tagUuid != shared.tagUuid;
        if (requiresManualConflictResolution(
              sharedUpdatedAtMs: shared.updatedAt,
              localUpdatedAtMs: semanticTag.updatedAt.millisecondsSinceEpoch,
              contentDifferent: contentDifferent,
            ) ||
            (shared.updatedAt > semanticTag.updatedAt.millisecondsSinceEpoch &&
                contentDifferent)) {
          count++;
        }
        continue;
      }
      count++;
    }
    return count;
  }

  Future<int> _countChangedPreviewAreas(
    List<PackageAreaData> areas,
  ) async {
    if (areas.isEmpty) return 0;
    final dedupedShared = <String, PackageAreaData>{};
    for (final area in areas) {
      final key = '${area.tagUuid}|${area.mapName}|${area.layerName}';
      final previous = dedupedShared[key];
      if (previous == null || area.updatedAt >= previous.updatedAt) {
        dedupedShared[key] = area;
      }
    }

    final mapNames = dedupedShared.values
        .map((e) => e.mapName.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final mapByName = <String, GameMap>{};
    final layerIdByMapAndName = <String, int>{};
    for (final name in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(name).findFirst();
      if (map == null) continue;
      mapByName[name] = map;
      await map.layers.load();
      for (final layer in map.layers) {
        layerIdByMapAndName['${map.name}|${layer.name}'] = layer.id;
      }
    }
    final localTagByUuid = <String, Tag>{};
    final allTags = await isar.tags.where().findAll();
    for (final tag in allTags) {
      final uuid = tag.tagUuid.trim();
      if (uuid.isNotEmpty) {
        localTagByUuid[uuid] = tag;
      }
    }

    final existingAreasByMapAndTag = <String, List<MapArea>>{};
    var count = 0;
    for (final shared in dedupedShared.values) {
      final map = mapByName[shared.mapName];
      final localTag = localTagByUuid[shared.tagUuid];
      final layerId =
          layerIdByMapAndName['${shared.mapName}|${shared.layerName}'];
      if (map == null ||
          localTag == null ||
          localTag.mapId != map.id ||
          layerId == null) {
        count++;
        continue;
      }
      final cacheKey = '${map.id}|${localTag.id}';
      final existing = existingAreasByMapAndTag[cacheKey] ??
          await isar.mapAreas
              .filter()
              .mapIdEqualTo(map.id)
              .tagIdEqualTo(localTag.id)
              .findAll();
      existingAreasByMapAndTag[cacheKey] = existing;
      final sameLayer =
          existing.where((a) => a.layerId == layerId).toList(growable: false);
      if (sameLayer.isEmpty) {
        count++;
        continue;
      }
      sameLayer.sort((a, b) {
        if (a.updatedAt.isAfter(b.updatedAt)) return -1;
        if (a.updatedAt.isBefore(b.updatedAt)) return 1;
        return b.id.compareTo(a.id);
      });
      final target = sameLayer.first;
      final contentDifferent = !isSharedAreaEquivalent(target, shared);
      if (requiresManualConflictResolution(
            sharedUpdatedAtMs: shared.updatedAt,
            localUpdatedAtMs: target.updatedAt.millisecondsSinceEpoch,
            contentDifferent: contentDifferent,
          ) ||
          (shared.updatedAt > target.updatedAt.millisecondsSinceEpoch &&
              contentDifferent)) {
        count++;
      }
    }
    return count;
  }

  Future<int> _countChangedPreviewFavoriteFolders(
    List<PackageFavoriteFolderData> favoriteFolders,
  ) async {
    if (favoriteFolders.isEmpty) return 0;
    final sharedByKey = <String, PackageFavoriteFolderData>{};
    for (final folder in favoriteFolders) {
      final nameKey = folder.nameKey.trim().isEmpty
          ? normalizeFolderNameKey(folder.name)
          : normalizeFolderNameKey(folder.nameKey);
      if (folder.mapName.trim().isEmpty || nameKey.isEmpty) continue;
      final key = favoriteFolderRefKey(
        mapName: folder.mapName,
        nameKey: nameKey,
      );
      final previous = sharedByKey[key];
      if (previous == null || folder.updatedAt >= previous.updatedAt) {
        sharedByKey[key] = folder;
      }
    }

    final mapByName = <String, GameMap>{};
    final localByMapIdAndNameKey = <String, FavoriteFolder>{};
    for (final mapName in sharedByKey.values.map((e) => e.mapName).toSet()) {
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map == null) continue;
      mapByName[mapName] = map;
      final folders =
          await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
      for (final folder in folders) {
        final nameKey = folder.nameKey.trim().isEmpty
            ? normalizeFolderNameKey(folder.name)
            : normalizeFolderNameKey(folder.nameKey);
        localByMapIdAndNameKey['${map.id}|$nameKey'] = folder;
      }
    }

    var count = 0;
    for (final entry in sharedByKey.entries) {
      final shared = entry.value;
      final map = mapByName[shared.mapName];
      if (map == null) {
        count++;
        continue;
      }
      final normalizedNameKey = shared.nameKey.trim().isEmpty
          ? normalizeFolderNameKey(shared.name)
          : normalizeFolderNameKey(shared.nameKey);
      final local = localByMapIdAndNameKey['${map.id}|$normalizedNameKey'];
      if (local == null) {
        count++;
        continue;
      }
      final nextName = shared.name.isEmpty ? local.name : shared.name;
      final contentDifferent = local.name != nextName ||
          local.nameKey != normalizedNameKey ||
          local.sortOrder != shared.sortOrder;
      if (contentDifferent &&
          shouldApplyIncomingUpdate(
            sharedUpdatedAtMs: shared.updatedAt,
            localUpdatedAtMs: local.updatedAt.millisecondsSinceEpoch,
            contentDifferent: true,
          )) {
        count++;
      }
    }
    return count;
  }

  Future<int> _countChangedPreviewImpactGroups(
    List<PackageImpactGroupData> impactGroups,
  ) async {
    if (impactGroups.isEmpty) return 0;
    final sharedByKey = <String, PackageImpactGroupData>{};
    for (final group in impactGroups) {
      final key = impactGroupSemanticKey(
        mapName: group.mapName,
        layerName: group.layerName,
        type: group.type,
        name: group.name,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
      );
      final previous = sharedByKey[key];
      if (previous == null || group.updatedAt >= previous.updatedAt) {
        sharedByKey[key] = group;
      }
    }

    final layerByMapAndName = <String, MapLayer>{};
    for (final shared in sharedByKey.values) {
      final map =
          await isar.gameMaps.filter().nameEqualTo(shared.mapName).findFirst();
      if (map == null) continue;
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

    var count = 0;
    for (final entry in sharedByKey.entries) {
      final layer =
          layerByMapAndName['${entry.value.mapName}|${entry.value.layerName}'];
      if (layer == null || !localBySemanticKey.containsKey(entry.key)) {
        count++;
      }
    }
    return count;
  }

  Future<int> _countChangedPreviewMaps(
    List<PackageMapData> maps, {
    required Map<String, String> packageFileHashes,
  }) async {
    if (maps.isEmpty) return 0;
    var count = 0;
    for (final shared in maps) {
      final local =
          await isar.gameMaps.filter().nameEqualTo(shared.mapName).findFirst();
      if (local != null && isBuiltinAssetMap(local)) continue;
      if (local == null ||
          !await isSharedMapEquivalentToLocal(
            shared,
            local,
            packageFileHashes: packageFileHashes,
          )) {
        count++;
      }
    }
    return count;
  }
}
