import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../models.dart';
import '../../models/grenade_tag.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import 'data_package_models.dart';
import 'package_archive_codec.dart';
import 'package_sync_helpers.dart';

class PackageExportEngine {
  final Isar isar;

  PackageExportEngine(this.isar);

  Future<int> ensureExportTagUuids(Iterable<int> tagIds) async {
    final toFix = <Tag>[];
    final occupied = <String>{};
    final tags = <Tag>[];

    for (final tagId in tagIds) {
      final tag = await isar.tags.get(tagId);
      if (tag != null) {
        tags.add(tag);
      }
    }

    for (final tag in tags) {
      final uuid = tag.tagUuid.trim();
      if (uuid.isNotEmpty) {
        occupied.add(uuid);
      }
    }

    const uuid = Uuid();
    for (final tag in tags) {
      if (tag.tagUuid.trim().isNotEmpty) continue;
      String value;
      do {
        value = uuid.v4();
      } while (occupied.contains(value));
      tag.tagUuid = value;
      occupied.add(value);
      toFix.add(tag);
    }

    if (toFix.isEmpty) return 0;
    await isar.writeTxn(() async {
      await isar.tags.putAll(toFix);
    });
    return toFix.length;
  }

  Future<PackageMapData?> buildPackageMapData(
    GameMap map, {
    Set<String>? filesToZip,
  }) async {
    final mapName = map.name.trim();
    if (mapName.isEmpty) return null;
    await map.layers.load();
    final layers = map.layers.toList(growable: false)
      ..sort((a, b) {
        final orderCompare = a.sortOrder.compareTo(b.sortOrder);
        if (orderCompare != 0) return orderCompare;
        return a.name.compareTo(b.name);
      });
    final layerPayloads = <PackageMapLayerData>[];
    for (final layer in layers) {
      final layerName = layer.name.trim();
      if (layerName.isEmpty) continue;
      final assetPath = layer.assetPath.trim();
      layerPayloads.add(PackageMapLayerData(
        name: layerName,
        assetPath: assetPath,
        sortOrder: layer.sortOrder,
      ));
      if (filesToZip != null) {
        addMapFileToZipIfNeeded(assetPath, filesToZip);
      }
    }

    final backgroundPath = map.backgroundPath.trim();
    final iconPath = map.iconPath.trim();
    if (filesToZip != null) {
      addMapFileToZipIfNeeded(backgroundPath, filesToZip);
      addMapFileToZipIfNeeded(iconPath, filesToZip);
    }
    return PackageMapData(
      mapName: mapName,
      backgroundPath: backgroundPath,
      iconPath: iconPath,
      layers: layerPayloads,
    );
  }

  Future<
      ({
        List<Map<String, dynamic>> payloads,
        Map<int, Map<String, dynamic>> refById,
      })> buildFavoriteFoldersAndRefs(
    Iterable<int> folderIds, {
    Map<int, GameMap>? mapCache,
  }) async {
    final mapById = mapCache ?? <int, GameMap>{};
    final payloads = <Map<String, dynamic>>[];
    final refById = <int, Map<String, dynamic>>{};

    for (final folderId in folderIds) {
      final folder = await isar.favoriteFolders.get(folderId);
      if (folder == null) continue;
      final map =
          mapById[folder.mapId] ?? await isar.gameMaps.get(folder.mapId);
      if (map == null) continue;
      mapById[folder.mapId] = map;
      final nameKey = folder.nameKey.trim().isEmpty
          ? normalizeFolderNameKey(folder.name)
          : normalizeFolderNameKey(folder.nameKey);
      payloads.add(PackageFavoriteFolderData(
        mapName: map.name,
        name: folder.name,
        nameKey: nameKey,
        sortOrder: folder.sortOrder,
        createdAt: folder.createdAt.millisecondsSinceEpoch,
        updatedAt: folder.updatedAt.millisecondsSinceEpoch,
      ).toJson());
      refById[folder.id] = {
        'mapName': map.name,
        'nameKey': nameKey,
      };
    }

    return (payloads: payloads, refById: refById);
  }

  Future<
      ({
        List<Map<String, dynamic>> payloads,
        Map<int, Map<String, dynamic>> refById,
      })> buildImpactGroupsAndRefs(Iterable<int> groupIds) async {
    final payloads = <Map<String, dynamic>>[];
    final refById = <int, Map<String, dynamic>>{};
    final seenSemanticKeys = <String>{};

    for (final groupId in groupIds) {
      final group = await isar.impactGroups.get(groupId);
      if (group == null) continue;
      final layer = await isar.mapLayers.get(group.layerId);
      if (layer == null) continue;
      await layer.map.load();
      final map = layer.map.value;
      if (map == null) continue;
      final payload = PackageImpactGroupData(
        mapName: map.name,
        layerName: layer.name,
        name: group.name,
        type: group.type,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
        createdAt: group.createdAt.millisecondsSinceEpoch,
        updatedAt: group.updatedAt.millisecondsSinceEpoch,
      );
      final semanticKey = impactGroupSemanticKey(
        mapName: payload.mapName,
        layerName: payload.layerName,
        type: payload.type,
        name: payload.name,
        impactXRatio: payload.impactXRatio,
        impactYRatio: payload.impactYRatio,
      );
      if (seenSemanticKeys.add(semanticKey)) {
        payloads.add(payload.toJson());
      }
      refById[group.id] = {
        'mapName': payload.mapName,
        'layerName': payload.layerName,
        'name': payload.name,
        'type': payload.type,
        'impactXRatio': payload.impactXRatio,
        'impactYRatio': payload.impactYRatio,
      };
    }

    return (payloads: payloads, refById: refById);
  }

  void applyFolderAndGroupRefsToGrenades(
    List<Grenade> grenades,
    List<Map<String, dynamic>> exportList,
    Map<int, Map<String, dynamic>> folderRefById,
    Map<int, Map<String, dynamic>> impactGroupRefById,
  ) {
    for (var i = 0; i < exportList.length; i++) {
      final item = exportList[i];
      final grenade = grenades[i];
      if (grenade.isFavorite && grenade.favoriteFolderId != null) {
        item['favoriteFolderRef'] = folderRefById[grenade.favoriteFolderId!];
      }
      if (grenade.impactGroupId != null) {
        item['impactGroupRef'] = impactGroupRefById[grenade.impactGroupId!];
      }
    }
  }

  Future<ExportBundle> buildExportBundle(List<Grenade> grenades) async {
    final exportList = <Map<String, dynamic>>[];
    final filesToZip = <String>{};
    final usedMapIds = <int>{};
    final usedFolderIds = <int>{};
    final usedImpactGroupIds = <int>{};

    for (final g in grenades) {
      g.layer.loadSync();
      g.layer.value?.map.loadSync();
      g.steps.loadSync();

      final stepsData = <Map<String, dynamic>>[];
      for (final s in g.steps) {
        s.medias.loadSync();
        final mediaData = <Map<String, dynamic>>[];
        for (final m in s.medias) {
          mediaData.add({'path': p.basename(m.localPath), 'type': m.type});
          filesToZip.add(m.localPath);
        }
        stepsData.add({
          'title': s.title,
          'description': s.description,
          'index': s.stepIndex,
          'medias': mediaData,
        });
      }

      if (g.layer.value?.map.value != null) {
        usedMapIds.add(g.layer.value!.map.value!.id);
      }
      if (g.isFavorite && g.favoriteFolderId != null) {
        usedFolderIds.add(g.favoriteFolderId!);
      }
      if (g.impactGroupId != null) {
        usedImpactGroupIds.add(g.impactGroupId!);
      }

      exportList.add({
        'uniqueId': g.uniqueId,
        'mapName': g.layer.value?.map.value?.name ?? 'Unknown',
        'layerName': g.layer.value?.name ?? 'Default',
        'title': g.title,
        'type': g.type,
        'team': g.team,
        'author': g.author,
        'sourceUrl': g.sourceUrl,
        'sourceNote': g.sourceNote,
        'x': g.xRatio,
        'y': g.yRatio,
        'impactX': g.impactXRatio,
        'impactY': g.impactYRatio,
        'impactAreaStrokes': g.impactAreaStrokes,
        'tagUuids': <String>[],
        'isFavorite': g.isFavorite,
        'favoriteFolderRef': null,
        'impactGroupRef': null,
        'steps': stepsData,
        'createdAt': g.createdAt.millisecondsSinceEpoch,
        'updatedAt': g.updatedAt.millisecondsSinceEpoch,
      });
    }

    final mapById = <int, GameMap>{};
    for (final id in usedMapIds) {
      final map = await isar.gameMaps.get(id);
      if (map != null) {
        mapById[id] = map;
      }
    }

    final usedTagIds = <int>{};
    for (final map in mapById.values) {
      final tags = await isar.tags.filter().mapIdEqualTo(map.id).findAll();
      for (final tag in tags) {
        usedTagIds.add(tag.id);
      }
    }

    await ensureExportTagUuids(usedTagIds);

    final tagById = <int, Tag>{};
    for (final id in usedTagIds) {
      final tag = await isar.tags.get(id);
      if (tag != null) {
        tagById[id] = tag;
      }
    }

    final grenadeTagIdsByGrenadeId = <int, Set<int>>{};
    for (final g in grenades) {
      final grenadeTags =
          await isar.grenadeTags.filter().grenadeIdEqualTo(g.id).findAll();
      grenadeTagIdsByGrenadeId[g.id] =
          grenadeTags.map((gt) => gt.tagId).toSet();
    }

    for (var i = 0; i < exportList.length; i++) {
      final item = exportList[i];
      final grenade = grenades[i];
      final tagIds = grenadeTagIdsByGrenadeId[grenade.id] ?? const <int>{};
      final uuids = <String>[];
      for (final tagId in tagIds) {
        final tag = tagById[tagId];
        if (tag == null || tag.tagUuid.trim().isEmpty) continue;
        uuids.add(tag.tagUuid.trim());
      }
      final tagUuids = uuids.toSet().toList(growable: false)..sort();
      item['tagUuids'] = tagUuids;
    }

    final tagsData = <Map<String, dynamic>>[];
    final usedTagUuids = <String>{};
    for (final tag in tagById.values) {
      final uuid = tag.tagUuid.trim();
      if (uuid.isEmpty || usedTagUuids.contains(uuid)) continue;
      usedTagUuids.add(uuid);
      final mapName = mapById[tag.mapId]?.name ?? '';
      tagsData.add({
        'tagUuid': uuid,
        'mapName': mapName,
        'name': tag.name,
        'dimension': tag.dimension,
        'colorValue': tag.colorValue,
        'groupName': tag.groupName,
        'isSystem': tag.isSystem,
        'updatedAt': tag.updatedAt.millisecondsSinceEpoch,
      });
    }

    final areasData = <Map<String, dynamic>>[];
    if (mapById.isNotEmpty) {
      final mapLayerNameById = <int, String>{};
      final maps = mapById.values.toList();
      for (final map in maps) {
        await map.layers.load();
        for (final layer in map.layers) {
          mapLayerNameById[layer.id] = layer.name;
        }
      }

      final areas = await isar.mapAreas.where().findAll();
      for (final area in areas) {
        if (!usedMapIds.contains(area.mapId)) continue;
        final tag = tagById[area.tagId];
        if (tag == null) continue;
        final tagUuid = tag.tagUuid.trim();
        if (tagUuid.isEmpty) continue;
        final mapName = mapById[area.mapId]?.name ?? '';
        final layerName = area.layerId == null
            ? 'Default'
            : (mapLayerNameById[area.layerId!] ?? 'Default');
        areasData.add({
          'tagUuid': tagUuid,
          'mapName': mapName,
          'layerName': layerName,
          'name': area.name,
          'colorValue': area.colorValue,
          'strokes': area.strokes,
          'createdAt': area.createdAt.millisecondsSinceEpoch,
          'updatedAt': area.updatedAt.millisecondsSinceEpoch,
        });
      }
    }

    final mapsData = <Map<String, dynamic>>[];
    final orderedMaps = mapById.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final map in orderedMaps) {
      if (isBuiltinAssetMap(map)) continue;
      final payload = await buildPackageMapData(map, filesToZip: filesToZip);
      if (payload == null) continue;
      mapsData.add(payload.toJson());
    }

    final neededFolderIds = <int>{...usedFolderIds};
    for (final map in mapById.values) {
      final folders =
          await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
      for (final folder in folders) {
        neededFolderIds.add(folder.id);
      }
    }
    final folderBundle =
        await buildFavoriteFoldersAndRefs(neededFolderIds, mapCache: mapById);

    final neededImpactGroupIds = <int>{...usedImpactGroupIds};
    for (final map in mapById.values) {
      await map.layers.load();
      for (final layer in map.layers) {
        final groups =
            await isar.impactGroups.filter().layerIdEqualTo(layer.id).findAll();
        for (final group in groups) {
          neededImpactGroupIds.add(group.id);
        }
      }
    }
    final groupBundle = await buildImpactGroupsAndRefs(neededImpactGroupIds);

    applyFolderAndGroupRefsToGrenades(
      grenades,
      exportList,
      folderBundle.refById,
      groupBundle.refById,
    );

    return ExportBundle(
      grenades: exportList,
      tags: tagsData,
      areas: areasData,
      maps: mapsData,
      favoriteFolders: folderBundle.payloads,
      impactGroups: groupBundle.payloads,
      filesToZip: filesToZip,
    );
  }

  Future<ExportPackageEstimate> estimateExportPackage(
    List<Grenade> grenades,
  ) async {
    if (grenades.isEmpty) {
      return const ExportPackageEstimate(
        grenadeCount: 0,
        mediaFileCount: 0,
        mediaBytes: 0,
        dataJsonBytes: 0,
        manifestJsonBytes: 0,
        estimatedPackageBytes: 0,
      );
    }
    final exportBundle = await buildExportBundle(grenades);
    return estimateExportPackageFromBundle(
      exportBundle,
      grenadeCount: grenades.length,
      schemaVersion: exportSchemaVersion,
      packageType: packageTypeExport,
    );
  }

  Future<ExportPackageEstimate> estimateExportPackageFromBundle(
    ExportBundle exportBundle, {
    required int grenadeCount,
    required int schemaVersion,
    required String packageType,
  }) async {
    final dataJson = jsonEncode(exportBundle.toJson());
    final dataJsonBytes = utf8.encode(dataJson).length;
    final manifestFiles = <Map<String, dynamic>>[
      {
        'path': packageDataFileName,
        'kind': 'data',
        'sizeBytes': dataJsonBytes,
        'sha256': placeholderSha256Hex,
      },
    ];

    int mediaBytes = 0;
    int mediaFileCount = 0;
    final addedNames = <String>{packageDataFileName};
    for (final filePath in exportBundle.filesToZip) {
      final file = File(filePath);
      if (!await file.exists()) continue;
      final fileName = p.basename(filePath);
      if (!addedNames.add(fileName)) continue;
      final sizeBytes = await file.length();
      mediaBytes += sizeBytes;
      mediaFileCount++;
      manifestFiles.add({
        'path': fileName,
        'kind': 'media',
        'sizeBytes': sizeBytes,
        'sha256': placeholderSha256Hex,
      });
    }

    final manifest = PackageManifestData(
      manifestVersion: packageManifestVersion,
      schemaVersion: schemaVersion,
      packageType: packageType,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      files: manifestFiles
          .map((raw) => PackageManifestFileEntry.fromJson(raw))
          .toList(growable: false),
      contentHmac: placeholderSha256Hex,
    );
    final manifestJson =
        jsonEncode(canonicalizePackageJsonValue(manifest.toJson()));
    final manifestJsonBytes = utf8.encode(manifestJson).length;
    final estimatedPackageBytes = mediaBytes +
        dataJsonBytes +
        manifestJsonBytes +
        estimatedArchiveBaseOverheadBytes +
        (manifestFiles.length + 1) * estimatedArchiveEntryOverheadBytes;

    return ExportPackageEstimate(
      grenadeCount: grenadeCount,
      mediaFileCount: mediaFileCount,
      mediaBytes: mediaBytes,
      dataJsonBytes: dataJsonBytes,
      manifestJsonBytes: manifestJsonBytes,
      estimatedPackageBytes: estimatedPackageBytes,
    );
  }

  void assertExportEstimateWithinLimit(ExportPackageEstimate estimate) {
    if (!estimate.exceedsLimit) return;
    throw StateError(
      '预计导出包体 ${formatPackageBytes(estimate.estimatedPackageBytes)}，'
      '已超过上限 ${formatPackageBytes(estimate.limitBytes)}，请减少媒体或分批导出',
    );
  }

  Future<void> exportSelectedGrenades(
    BuildContext context,
    List<Grenade> grenades,
  ) async {
    if (grenades.isEmpty) return;
    await _exportGrenadesInternal(context, grenades);
  }

  Future<void> exportData(
    BuildContext context, {
    required int scopeType,
    Grenade? singleGrenade,
    GameMap? singleMap,
  }) async {
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

    if (grenades.isEmpty) return;
    await _exportGrenadesInternal(context, grenades);
  }

  Future<void> _exportGrenadesInternal(
    BuildContext context,
    List<Grenade> grenades,
  ) async {
    final exportBundle = await buildExportBundle(grenades);
    final exportEstimate = await estimateExportPackageFromBundle(
      exportBundle,
      grenadeCount: grenades.length,
      schemaVersion: exportSchemaVersion,
      packageType: packageTypeExport,
    );
    assertExportEstimateWithinLimit(exportEstimate);

    final tempDir = await getTemporaryDirectory();
    final exportDirPath = p.join(tempDir.path, 'export_temp');
    final zipPath = p.join(tempDir.path, 'share_data.cs2pkg');

    await compute(
      packageFilesInIsolate,
      PackageParams(
        exportDirPath: exportDirPath,
        zipPath: zipPath,
        jsonData: jsonEncode(exportBundle.toJson()),
        filesToCopy: exportBundle.filesToZip.toList(),
        schemaVersion: exportSchemaVersion,
        packageType: packageTypeExport,
      ),
    );

    final exportedFile = File(zipPath);
    if (await exportedFile.exists()) {
      final actualSize = await exportedFile.length();
      if (actualSize > maxExportPackageSizeBytes) {
        try {
          await exportedFile.delete();
        } catch (_) {}
        throw StateError(
          '导出包体 ${formatPackageBytes(actualSize)} 已超过上限 '
          '${formatPackageBytes(maxExportPackageSizeBytes)}，请减少媒体或分批导出',
        );
      }
    }

    if (!context.mounted) return;

    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (isDesktop) {
      await _saveToFolderWithCustomName(context, zipPath);
    } else {
      await _showMobileExportSheet(context, zipPath);
    }
  }

  Future<void> _showMobileExportSheet(
    BuildContext context,
    String zipPath,
  ) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: 200,
        decoration: const BoxDecoration(
          color: Color(0xFF2A2D33),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Text('选择导出方式',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.blueAccent),
              title: const Text('系统分享 (微信/QQ)',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(
                    ShareParams(files: [XFile(zipPath)], text: 'CS2 道具数据分享'));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.folder_open, color: Colors.orangeAccent),
              title:
                  const Text('保存到文件夹', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                await _saveToFolderWithCustomName(context, zipPath);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToFolderWithCustomName(
    BuildContext context,
    String sourcePath,
  ) async {
    final defaultFileName =
        'cs2_tactics_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}';

    final fileNameController = TextEditingController(text: defaultFileName);
    final customFileName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入文件名：'),
            const SizedBox(height: 16),
            TextField(
              controller: fileNameController,
              decoration: const InputDecoration(
                suffixText: '.cs2pkg',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, fileNameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('选择位置'),
          ),
        ],
      ),
    );

    if (customFileName == null || customFileName.isEmpty) return;
    if (!context.mounted) return;

    final outputDirectory =
        await FilePicker.platform.getDirectoryPath(dialogTitle: '请选择保存位置');
    if (outputDirectory == null) return;

    try {
      final fileName = '$customFileName.cs2pkg';
      final destination = p.join(outputDirectory, fileName);

      final sourceFile = File(sourcePath);
      await sourceFile.copy(destination);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('文件已保存至:\n$destination'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red));
      }
    }
  }
}
