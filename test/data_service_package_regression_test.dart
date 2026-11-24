import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/services/data_service.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

Future<void> _initIsarCoreForTest() async {
  final libraries = <Abi, String>{};
  final packageConfigFile =
      File(p.join(Directory.current.path, '.dart_tool', 'package_config.json'));
  if (await packageConfigFile.exists()) {
    final decoded = jsonDecode(await packageConfigFile.readAsString());
    if (decoded is Map && decoded['packages'] is List) {
      for (final pkg in decoded['packages'] as List) {
        if (pkg is Map && pkg['name'] == 'isar_community_flutter_libs') {
          final rootUri = pkg['rootUri'] as String?;
          if (rootUri != null && rootUri.isNotEmpty) {
            final rootPath = Uri.parse(rootUri).toFilePath();
            final winDll = File(p.join(rootPath, 'windows', 'libisar.dll'));
            if (await winDll.exists()) {
              libraries[Abi.windowsX64] = winDll.path;
            }
          }
          break;
        }
      }
    }
  }
  await Isar.initializeIsarCore(libraries: libraries);
}

Future<Isar> _openTestIsar(Directory dir, String name) {
  return Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema,
      ImportHistorySchema,
      ImpactGroupSchema,
      FavoriteFolderSchema,
      TagSchema,
      GrenadeTagSchema,
      MapAreaSchema,
    ],
    directory: dir.path,
    name: name,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _initIsarCoreForTest();
  });

  test('formatBytes 与 normalizeMediaPath 行为保持一致', () {
    expect(DataService.formatBytes(0), '0 B');
    expect(DataService.formatBytes(512), '512 B');
    expect(DataService.formatBytes(1023), '1023 B');
    expect(DataService.formatBytes(1024), '1.0 KB');
    expect(DataService.formatBytes(1536), '1.5 KB');
    expect(DataService.formatBytes(100 * 1024), '100 KB');
    expect(DataService.formatBytes(1024 * 1024), '1.0 MB');
    expect(DataService.formatBytes(1024 * 1024 * 1024), '1.0 GB');

    expect(DataService.normalizeMediaPath('   '), '');
    final samplePath = p.join('temp_media', 'dir', '..', 'shot.jpg');
    final normalized = DataService.normalizeMediaPath('  $samplePath  ');
    expect(
        normalized, endsWith(p.join('temp_media', 'shot.jpg').toLowerCase()));
  });

  test('实体墓碑 Key 构造方法规范化并保持确定性', () async {
    final tempDir = await Directory.systemTemp.createTemp('gh_keys_test_');
    final isar = await _openTestIsar(tempDir, 'keys_test');
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final service = DataService(isar);
    expect(
      service.entityTombstoneKey(entityType: ' tag ', entityKey: ' uuid-1 '),
      'tag|uuid-1',
    );
    expect(
      service.buildAreaEntityKey(tagUuid: ' abc ', layerName: ' Upper '),
      'abc|upper',
    );
    expect(
      service.buildFavoriteFolderEntityKey(
        mapName: ' Mirage ',
        nameKey: ' A_Execute ',
      ),
      'mirage|a_execute',
    );
    final keyA = service.buildImpactGroupEntityKey(
      mapName: ' Mirage ',
      layerName: ' Default ',
      type: GrenadeType.smoke,
      name: '  CT   Smoke  ',
      impactXRatio: 0.1234,
      impactYRatio: 0.5678,
    );
    final keyB = service.buildImpactGroupEntityKey(
      mapName: 'mirage',
      layerName: 'default',
      type: GrenadeType.smoke,
      name: 'ct smoke',
      impactXRatio: 0.1231,
      impactYRatio: 0.5682,
    );
    expect(keyA, 'mirage|default|0|ct smoke|0.123|0.568');
    expect(keyB, keyA);
  });

  test('estimateExportPackage 空列表与带媒体道具估算结果准确', () async {
    final tempDir = await Directory.systemTemp.createTemp('gh_estimate_test_');
    final isar = await _openTestIsar(tempDir, 'estimate_test');
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final service = DataService(isar);
    final emptyEstimate = await service.estimateExportPackage(const []);
    expect(emptyEstimate.grenadeCount, 0);
    expect(emptyEstimate.mediaFileCount, 0);
    expect(emptyEstimate.estimatedPackageBytes, 0);
    expect(emptyEstimate.exceedsLimit, isFalse);

    final mediaFile = File(p.join(tempDir.path, 'lineup.jpg'))
      ..writeAsBytesSync(List<int>.generate(256, (i) => i % 256));
    final map = GameMap(
      name: 'Mirage',
      backgroundPath: 'assets/backgrounds/mirage_bg.webp',
      iconPath: 'assets/icons/mirage_icon.svg',
    );
    final layer = MapLayer(
        name: 'Default', assetPath: 'assets/maps/mirage.png', sortOrder: 0);
    final grenade = Grenade(
      title: 'Stairs Smoke',
      type: GrenadeType.smoke,
      xRatio: 0.4,
      yRatio: 0.6,
      uniqueId: 'g-est-1',
    );
    final step = GrenadeStep(title: 'Aim', description: 'Hold D', stepIndex: 0);
    final media = StepMedia(localPath: mediaFile.path, type: MediaType.image);

    await isar.writeTxn(() async {
      await isar.gameMaps.put(map);
      await isar.mapLayers.put(layer);
      map.layers.add(layer);
      await map.layers.save();
      await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
      await isar.grenadeSteps.put(step);
      grenade.steps.add(step);
      await grenade.steps.save();
      await isar.stepMedias.put(media);
      step.medias.add(media);
      await step.medias.save();
    });

    final estimate = await service.estimateExportPackage([grenade]);
    expect(estimate.grenadeCount, 1);
    expect(estimate.mediaFileCount, 1);
    expect(estimate.mediaBytes, 256);
    expect(estimate.dataJsonBytes, greaterThan(0));
    expect(estimate.manifestJsonBytes, greaterThan(0));
    expect(estimate.estimatedPackageBytes, greaterThan(256));
    expect(estimate.limitBytes, DataService.maxExportPackageSizeBytes);
    expect(estimate.exceedsLimit, isFalse);
  });

  test('小型 cs2pkg 临时打包 -> previewPackage -> importFromPreview 往返一致', () async {
    final rootDir = await Directory.systemTemp.createTemp('gh_pkg_roundtrip_');
    final sourceDir = Directory(p.join(rootDir.path, 'source'))..createSync();
    final targetDir = Directory(p.join(rootDir.path, 'target'))..createSync();
    final tempWorkDir = Directory(p.join(rootDir.path, 'tmp'))..createSync();

    // 拦截 path_provider 通道，确保临时包输出在测试可控目录内
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempWorkDir.path;
      }
      return tempWorkDir.path;
    });

    final sourceIsar = await _openTestIsar(sourceDir, 'pkg_src');
    final targetIsar = await _openTestIsar(targetDir, 'pkg_dst');
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      await sourceIsar.close(deleteFromDisk: true);
      await targetIsar.close(deleteFromDisk: true);
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    final sourceMediaBytes = List<int>.generate(128, (i) => (i * 7) % 256);
    final sourceMediaFile = File(p.join(sourceDir.path, 'smoke_spot.jpg'))
      ..writeAsBytesSync(sourceMediaBytes);

    final srcMap = GameMap(
      name: 'Inferno',
      backgroundPath: 'assets/backgrounds/inferno_bg.webp',
      iconPath: 'assets/icons/inferno_icon.svg',
    );
    final srcLayer = MapLayer(
      name: 'Default',
      assetPath: 'assets/maps/inferno.png',
      sortOrder: 0,
    );
    final dstMap = GameMap(
      name: 'Inferno',
      backgroundPath: 'assets/backgrounds/inferno_bg.webp',
      iconPath: 'assets/icons/inferno_icon.svg',
    );
    final dstLayer = MapLayer(
      name: 'Default',
      assetPath: 'assets/maps/inferno.png',
      sortOrder: 0,
    );

    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    late Tag srcTag;
    late MapArea srcArea;
    late FavoriteFolder srcFolder;
    late ImpactGroup srcGroup;
    late Grenade srcGrenade;

    await sourceIsar.writeTxn(() async {
      await sourceIsar.gameMaps.put(srcMap);
      await sourceIsar.mapLayers.put(srcLayer);
      srcMap.layers.add(srcLayer);
      await srcMap.layers.save();

      srcTag = Tag(
        tagUuid: 'tag-area-banana',
        name: 'Banana',
        colorValue: 0xFF4CAF50,
        dimension: TagDimension.area,
        mapId: srcMap.id,
        updated: now,
      );
      await sourceIsar.tags.put(srcTag);

      srcArea = MapArea(
        name: 'Banana',
        colorValue: 0xFF4CAF50,
        strokes: '[{"x":0.1,"y":0.2}]',
        mapId: srcMap.id,
        layerId: srcLayer.id,
        tagId: srcTag.id,
        createdAt: now,
        updated: now,
      );
      await sourceIsar.mapAreas.put(srcArea);

      srcFolder = FavoriteFolder(
        mapId: srcMap.id,
        name: 'B Execute',
        nameKey: 'b execute',
        sortOrder: 1,
        created: now,
        updated: now,
      );
      await sourceIsar.favoriteFolders.put(srcFolder);

      srcGroup = ImpactGroup(
        name: 'CT Smoke',
        type: GrenadeType.smoke,
        impactXRatio: 0.45,
        impactYRatio: 0.35,
        layerId: srcLayer.id,
        created: now,
        updated: now,
      );
      await sourceIsar.impactGroups.put(srcGroup);

      srcGrenade = Grenade(
        title: 'CT Coffin Smoke',
        type: GrenadeType.smoke,
        team: TeamType.t,
        isFavorite: true,
        favoriteFolderId: srcFolder.id,
        xRatio: 0.25,
        yRatio: 0.75,
        uniqueId: 'grenade-roundtrip-1',
        created: now,
        updated: now,
      )
        ..author = 'tester'
        ..impactXRatio = 0.45
        ..impactYRatio = 0.35
        ..impactGroupId = srcGroup.id;
      await sourceIsar.grenades.put(srcGrenade);
      srcGrenade.layer.value = srcLayer;
      await srcGrenade.layer.save();

      final step =
          GrenadeStep(title: 'Stand', description: 'Jump throw', stepIndex: 0);
      await sourceIsar.grenadeSteps.put(step);
      step.grenade.value = srcGrenade;
      await step.grenade.save();
      srcGrenade.steps.add(step);
      await srcGrenade.steps.save();

      final media =
          StepMedia(localPath: sourceMediaFile.path, type: MediaType.image);
      await sourceIsar.stepMedias.put(media);
      media.step.value = step;
      await media.step.save();
      step.medias.add(media);
      await step.medias.save();

      await sourceIsar.grenadeTags
          .put(GrenadeTag(grenadeId: srcGrenade.id, tagId: srcTag.id));
    });

    await targetIsar.writeTxn(() async {
      await targetIsar.gameMaps.put(dstMap);
      await targetIsar.mapLayers.put(dstLayer);
      dstMap.layers.add(dstLayer);
      await dstMap.layers.save();
    });

    final sourceService = DataService(sourceIsar);
    final packagePath = await sourceService.buildLanSyncPackageToTemp(
      scopeType: 0,
      singleGrenade: srcGrenade,
    );
    addTearDown(() async {
      final pkgFile = File(packagePath);
      if (await pkgFile.exists()) {
        await pkgFile.delete();
      }
      final lanTempDir =
          Directory(p.join(p.dirname(packagePath), 'lan_sync_export_temp'));
      if (await lanTempDir.exists()) {
        await lanTempDir.delete(recursive: true);
      }
    });
    expect(File(packagePath).existsSync(), isTrue);

    final targetService = DataService(targetIsar);
    expect(await targetService.previewPackage('invalid.txt'), isNull);

    final preview = await targetService.previewPackage(
      packagePath,
      mode: ImportPackageMode.lanSync,
      requireTrustedPackage: true,
    );
    expect(preview, isNotNull);
    expect(preview!.isTrustedPackage, isTrue);
    expect(preview.isLegacyPackage, isFalse);
    expect(preview.schemaVersion, 7);
    expect(preview.canApplyTombstones, isTrue);
    expect(preview.totalCount, 1);
    expect(preview.tagsByUuid.keys, contains('tag-area-banana'));
    expect(preview.areas.length, 1);
    expect(preview.favoriteFolders.length, 1);
    expect(preview.impactGroups.length, 1);

    final item = preview.grenadesByMap['Inferno']!.single;
    expect(item.status, ImportStatus.newItem);
    expect(item.title, 'CT Coffin Smoke');

    final readBytes = await DataService.readPackageMediaBytes(
      packageFilePath: packagePath,
      packageMediaPath: 'smoke_spot.jpg',
      expectedSha256: preview.packageFileHashes['smoke_spot.jpg'],
      expectedSizeBytes: preview.packageFileSizes['smoke_spot.jpg'],
    );
    expect(readBytes, equals(sourceMediaBytes));

    final summary = await targetService.importFromPreview(
      preview,
      {item.uniqueId},
      mode: ImportPackageMode.lanSync,
    );
    expect(summary, contains('新增 1 个'));

    final importedGrenades = await targetIsar.grenades.where().findAll();
    expect(importedGrenades.length, 1);
    final imported = importedGrenades.single;
    expect(imported.uniqueId, 'grenade-roundtrip-1');
    expect(imported.title, 'CT Coffin Smoke');
    expect(imported.isFavorite, isTrue);
    expect(imported.favoriteFolderId, isNotNull);
    expect(imported.impactGroupId, isNotNull);

    await imported.steps.load();
    expect(imported.steps.length, 1);
    final importedStep = imported.steps.single;
    await importedStep.medias.load();
    expect(importedStep.medias.length, 1);
    final copiedMediaFile = File(importedStep.medias.single.localPath);
    expect(copiedMediaFile.existsSync(), isTrue);
    expect(copiedMediaFile.readAsBytesSync(), equals(sourceMediaBytes));

    final importedTags = await targetIsar.tags.where().findAll();
    final importedAreas = await targetIsar.mapAreas.where().findAll();
    final importedFolders = await targetIsar.favoriteFolders.where().findAll();
    final importedGroups = await targetIsar.impactGroups.where().findAll();
    final importedHistories = await targetIsar.importHistorys.where().findAll();
    expect(importedTags.map((e) => e.tagUuid), contains('tag-area-banana'));
    expect(importedAreas.length, 1);
    expect(importedFolders.single.nameKey, 'b execute');
    expect(importedGroups.single.name, 'CT Smoke');
    expect(importedHistories.single.newCount, 1);

    // 验证全量导出 DTO 均可通过 data_service.dart 访问
    const manifestEntry = PackageManifestFileEntry(
      path: 'data.json',
      kind: 'data',
      sizeBytes: 1,
      sha256: 'abc',
    );
    const manifestData = PackageManifestData(
      manifestVersion: 1,
      schemaVersion: 3,
      packageType: 'export',
      createdAt: 0,
      files: [manifestEntry],
      contentHmac: 'hmac',
    );
    const tagConflictType = TagConflictType.uuidMismatch;
    const tagResolution = ImportTagConflictResolution.shared;
    const areaResolution = ImportAreaConflictResolution.overwriteShared;
    const conflictBundle =
        ImportConflictBundle(tagConflicts: [], localTagByUuid: {});
    final tagConflictItem = TagConflictItem(
      type: tagConflictType,
      sharedTag: const PackageTagData(
        tagUuid: 'u',
        mapName: 'Inferno',
        name: 'n',
        dimension: 0,
        colorValue: 0,
        isSystem: false,
        updatedAt: 0,
      ),
      localTag: Tag(
        tagUuid: 'u',
        name: 'n',
        colorValue: 0,
        dimension: 0,
        mapId: 1,
      ),
    );
    const conflictNotice = ImportConflictNotice();
    const tombstoneResult =
        EntityTombstoneApplyResult(deletedCount: 0, skippedCount: 0);
    const orphanEntry = OrphanMediaFileEntry(path: 'a.jpg', sizeBytes: 1);
    const orphanScan = OrphanMediaScanResult(orphanFiles: [orphanEntry]);
    const orphanClean =
        OrphanMediaCleanupResult(deletedFiles: [], failedFiles: []);
    const manifestBundle = LanSyncManifestBundle();
    const manifestItem = LanSyncManifestItem(
      key: 'k',
      mapName: 'Inferno',
      digest: 'd',
      updatedAtMs: 0,
    );
    const pkgTag = PackageTagData(
      tagUuid: 'u',
      mapName: 'Inferno',
      name: 'n',
      dimension: 0,
      colorValue: 0,
      isSystem: false,
      updatedAt: 0,
    );
    const pkgArea = PackageAreaData(
      tagUuid: 'u',
      mapName: 'Inferno',
      layerName: 'Default',
      name: 'n',
      colorValue: 0,
      strokes: '[]',
      createdAt: 0,
      updatedAt: 0,
    );
    const pkgFolder = PackageFavoriteFolderData(
      mapName: 'Inferno',
      name: 'n',
      nameKey: 'n',
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
    );
    const pkgGroup = PackageImpactGroupData(
      mapName: 'Inferno',
      layerName: 'Default',
      name: 'n',
      type: 0,
      impactXRatio: 0,
      impactYRatio: 0,
      createdAt: 0,
      updatedAt: 0,
    );
    const pkgLayer = PackageMapLayerData(
      name: 'Default',
      assetPath: 'assets/maps/inferno.png',
      sortOrder: 0,
    );
    const pkgMap = PackageMapData(
      mapName: 'Inferno',
      backgroundPath: '',
      iconPath: '',
      layers: [pkgLayer],
    );
    expect(manifestData.isValid, isTrue);
    expect(tagConflictType, TagConflictType.uuidMismatch);
    expect(tagResolution, ImportTagConflictResolution.shared);
    expect(areaResolution, ImportAreaConflictResolution.overwriteShared);
    expect(conflictBundle.tagConflicts, isEmpty);
    expect(tagConflictItem.type, TagConflictType.uuidMismatch);
    expect(conflictNotice.hasConflicts, isFalse);
    expect(tombstoneResult.deletedCount, 0);
    expect(orphanScan.hasAnythingToClean, isTrue);
    expect(orphanClean.deletedBytes, 0);
    expect(manifestBundle.grenades, isEmpty);
    expect(manifestItem.key, 'k');
    expect(pkgTag.tagUuid, 'u');
    expect(pkgArea.layerName, 'Default');
    expect(pkgFolder.nameKey, 'n');
    expect(pkgGroup.name, 'n');
    expect(pkgMap.layers.length, 1);
  });
}
