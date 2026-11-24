import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/data/map_area_presets.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/services/area_service.dart';
import 'package:grenade_helper/services/favorite_folder_service.dart';
import 'package:grenade_helper/services/settings_service.dart';
import 'package:grenade_helper/services/tag_service.dart';
import 'package:grenade_helper/services/tag_uuid_service.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _initIsarCoreForTest() async {
  final libraries = <Abi, String>{};
  final packageConfigFile = File(
    p.join(Directory.current.path, '.dart_tool', 'package_config.json'),
  );
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
  setUpAll(() async {
    await _initIsarCoreForTest();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TagUuidService 确定性 UUID 计算', () {
    test('相同系统标签语义输入跨大小写、空白与图标别名生成同一 UUID', () {
      final uuidA = TagUuidService.buildSystemTagUuid(
        mapName: 'Mirage',
        mapIconPath: 'assets/icons/mirage_icon.svg',
        dimension: TagDimension.area,
        tagName: '  A1   跳台 ',
      );
      final uuidB = TagUuidService.buildSystemTagUuid(
        mapName: '荒漠迷城',
        mapIconPath: r'assets\icons\MIRAGE_icon.svg',
        dimension: TagDimension.area,
        tagName: 'a1 跳台',
      );

      expect(uuidA, equals(uuidB));
      expect(uuidA, hasLength(36));
    });

    test('无标准图标路径时回退到地图名，且不同维度或标签生成不同 UUID', () {
      final fallbackA = TagUuidService.buildSystemTagUuid(
        mapName: '  Custom   Map ',
        mapIconPath: 'assets/custom/map.png',
        dimension: TagDimension.role,
        tagName: 'CT方',
      );
      final fallbackB = TagUuidService.buildSystemTagUuid(
        mapName: 'custom map',
        mapIconPath: null,
        dimension: TagDimension.role,
        tagName: 'ct方',
      );
      final otherDimension = TagUuidService.buildSystemTagUuid(
        mapName: 'custom map',
        mapIconPath: null,
        dimension: TagDimension.purpose,
        tagName: 'ct方',
      );

      expect(fallbackA, equals(fallbackB));
      expect(fallbackA, isNot(equals(otherDimension)));
      expect(
        TagUuidService.newRandomUuid(),
        isNot(equals(TagUuidService.newRandomUuid())),
      );
    });
  });

  group('TagService 系统标签初始化与迁移幂等性', () {
    test('initializeSystemTags 与 ensureSystemTagsForAllMaps 保持幂等并尊重删除记录',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('gh_tag_service_reg_');
      final isar = await _openTestIsar(tempDir, 'tag_reg_test');
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final map = GameMap(
        name: 'Mirage',
        backgroundPath: 'assets/backgrounds/mirage.webp',
        iconPath: 'assets/icons/mirage_icon.svg',
      );
      final layer = MapLayer(
        name: 'Default',
        assetPath: 'assets/maps/mirage.png',
        sortOrder: 0,
      );
      await isar.writeTxn(() async {
        await isar.gameMaps.put(map);
        await isar.mapLayers.put(layer);
        map.layers.add(layer);
        await map.layers.save();
      });

      final tagService = TagService(isar);
      await tagService.initializeSystemTags(map.id, map.name);

      final firstTags = await tagService.getAllTags(map.id);
      final expectedAreaCount = mapAreaPresets['mirage']
              ?.map((e) => e.trim().toLowerCase())
              .toSet()
              .length ??
          0;
      final expectedCommonCount = commonSystemTags.values.fold<int>(
        0,
        (sum, list) =>
            sum + list.map((e) => e.trim().toLowerCase()).toSet().length,
      );
      expect(firstTags.length, expectedAreaCount + expectedCommonCount);
      expect(
          firstTags.every((t) => t.isSystem && t.tagUuid.isNotEmpty), isTrue);

      final firstAreaCount = await isar.mapAreas.count();
      expect(firstAreaCount, greaterThan(0));

      // 重复初始化与全局校验不应产生重复标签或多余修改。
      await tagService.initializeSystemTags(map.id, map.name);
      final summary = await tagService.ensureSystemTagsForAllMaps();
      expect(summary.processedMaps, 1);
      expect(summary.addedTags, 0);
      expect(summary.updatedTags, 0);
      expect(summary.removedObsoleteTags, 0);
      expect(await isar.tags.count(), firstTags.length);
      expect(await isar.mapAreas.count(), firstAreaCount);

      // 删除系统标签后不应自动复活，清除记录后应恢复。
      final targetTag = firstTags.first;
      await tagService.deleteTag(targetTag.id);
      final afterDelete = await tagService.ensureSystemTagsForAllMaps();
      expect(afterDelete.addedTags, 0);

      await tagService.clearDeletedSystemTagRecordsForMap(map.id);
      final afterClear = await tagService.ensureSystemTagsForAllMaps();
      expect(afterClear.addedTags, 1);
      expect(await isar.tags.count(), firstTags.length);
    });

    test('ensureTagUuids 补齐空 UUID 与冲突 UUID 并保留唯一性', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('gh_tag_uuid_migrate_');
      final isar = await _openTestIsar(tempDir, 'tag_uuid_migrate');
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final map = GameMap(
        name: 'Dust2',
        backgroundPath: '',
        iconPath: 'assets/icons/dust2_icon.svg',
      );
      late Tag sysEmpty;
      late Tag customDupA;
      late Tag customDupB;
      await isar.writeTxn(() async {
        await isar.gameMaps.put(map);
        sysEmpty = Tag(
          tagUuid: '',
          name: 'CT方',
          colorValue: 0xFF9C27B0,
          dimension: TagDimension.role,
          isSystem: true,
          mapId: map.id,
        );
        customDupA = Tag(
          tagUuid: 'dup-uuid-1',
          name: '自定义A',
          colorValue: 0xFF607D8B,
          dimension: TagDimension.custom,
          isSystem: false,
          mapId: map.id,
        );
        customDupB = Tag(
          tagUuid: 'dup-uuid-1',
          name: '自定义B',
          colorValue: 0xFF607D8B,
          dimension: TagDimension.custom,
          isSystem: false,
          mapId: map.id,
        );
        await isar.tags.putAll([sysEmpty, customDupA, customDupB]);
      });

      final result = await TagService(isar).ensureTagUuids();
      expect(result.migratedCount, 2);

      final updated = await isar.tags.where().findAll();
      final uuids = updated.map((e) => e.tagUuid).toSet();
      expect(uuids, hasLength(3));
      expect(
        updated.firstWhere((e) => e.id == sysEmpty.id).tagUuid,
        TagUuidService.buildSystemTagUuid(
          mapName: map.name,
          mapIconPath: map.iconPath,
          dimension: TagDimension.role,
          tagName: 'CT方',
        ),
      );
    });
  });

  group('SettingsService 热键序列化与默认值校验', () {
    test('HotkeyConfig 序列化往返、显示文案与修饰键归一化冲突检测', () {
      final config = HotkeyConfig(
        key: LogicalKeyboardKey.keyK,
        modifiers: {
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.shiftRight,
        },
      );

      final restored = HotkeyConfig.fromJson(config.toJson());
      expect(restored.key, LogicalKeyboardKey.keyK);
      expect(
        restored.modifiers,
        {LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftRight},
      );
      expect(restored.toDisplayString(), 'Ctrl + Shift + K');

      final equivalent = HotkeyConfig(
        key: LogicalKeyboardKey.keyK,
        modifiers: {LogicalKeyboardKey.control, LogicalKeyboardKey.shift},
      );
      expect(config.conflictsWith(equivalent), isTrue);

      final nonConflict = HotkeyConfig(
        key: LogicalKeyboardKey.keyK,
        modifiers: {LogicalKeyboardKey.alt},
      );
      expect(config.conflictsWith(nonConflict), isFalse);
    });

    test('SettingsService 默认设置值与热键保存、冲突拦截及重置流程保持一致', () async {
      final settings = SettingsService();
      final defaults = settings.getHotkeys();

      expect(defaults.length, HotkeyAction.values.length);
      expect(
        defaults[HotkeyAction.toggleOverlay]?.toDisplayString(),
        'Alt + G',
      );
      expect(
        defaults[HotkeyAction.toggleWallbang]?.toDisplayString(),
        'Alt + 0',
      );
      expect(settings.getOverlayOpacity(), 0.9);
      expect(settings.getOverlaySize(), 1);
      expect(SettingsService.calculateSizePixels(0), (500.0, 800.0));
      expect(SettingsService.calculateSizePixels(1), (550.0, 850.0));
      expect(SettingsService.calculateSizePixels(2), (600.0, 950.0));
      expect(settings.getCloseToTray(), isTrue);
      expect(settings.getOverlayX(), isNull);
      expect(settings.getOverlayY(), isNull);
      expect(settings.getOverlayNavSpeed(), 3);
      expect(settings.getThemeMode(), 2);
      expect(settings.getMarkerMoveMode(), 0);
      expect(settings.getGrenadeCreateMode(), 0);
      expect(settings.getShowMapGrenadeList(), isFalse);
      expect(settings.getHighDensityClusterMode(), isTrue);
      expect(settings.getMapMarkerUseEmoji(), isFalse);
      expect(settings.getJoystickOpacity(), 0.8);
      expect(settings.getJoystickSpeed(), 3);
      expect(settings.getLaunchCount(), 0);
      expect(settings.isDonationDialogShown(), isFalse);
      expect(settings.getMapLineColor(), 0xFFE040FB);
      expect(settings.getMapLineOpacity(), 0.6);
      expect(settings.getImpactAreaOpacity(), 0.4);

      final customBinding = HotkeyConfig(
        key: LogicalKeyboardKey.keyF,
        modifiers: {LogicalKeyboardKey.control, LogicalKeyboardKey.alt},
      );
      await settings.saveHotkey(HotkeyAction.nextGrenade, customBinding);

      final updated = settings.getHotkeys();
      expect(updated[HotkeyAction.nextGrenade]?.key, LogicalKeyboardKey.keyF);
      expect(
        updated[HotkeyAction.nextGrenade]?.modifiers,
        {LogicalKeyboardKey.control, LogicalKeyboardKey.alt},
      );

      await expectLater(
        () => settings.saveHotkey(
          HotkeyAction.prevGrenade,
          HotkeyConfig(
            key: LogicalKeyboardKey.keyF,
            modifiers: {
              LogicalKeyboardKey.controlLeft,
              LogicalKeyboardKey.altRight,
            },
          ),
        ),
        throwsA(isA<HotkeyConflictException>()),
      );

      await settings.resetHotkeys();
      final reset = settings.getHotkeys();
      expect(
        reset[HotkeyAction.nextGrenade]?.key,
        LogicalKeyboardKey.pageDown,
      );
    });
  });

  group('AreaService 与 FavoriteFolderService 核心纯逻辑回归', () {
    test('AreaService 支持多边形区域、方形笔刷与橡皮擦覆盖判定', () async {
      final tempDir = await Directory.systemTemp.createTemp('gh_area_geo_reg_');
      final isar = await _openTestIsar(tempDir, 'area_geo_reg');
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final areaService = AreaService(isar);
      final shapeArea = MapArea(
        name: 'ShapeArea',
        colorValue: 0xFF4CAF50,
        mapId: 1,
        tagId: 1,
        createdAt: DateTime.now(),
        strokes: jsonEncode([
          {
            'isShape': true,
            'points': [
              {'x': 0.2, 'y': 0.2},
              {'x': 0.6, 'y': 0.2},
              {'x': 0.6, 'y': 0.6},
              {'x': 0.2, 'y': 0.6},
            ],
          },
          {
            'isEraser': true,
            'brushShape': 1,
            'widthRatio': 0.08,
            'points': [
              {'x': 0.4, 'y': 0.4},
            ],
          },
        ]),
      );

      expect(areaService.isPointInArea(0.25, 0.25, shapeArea), isTrue);
      expect(areaService.isPointInArea(0.42, 0.42, shapeArea), isFalse);
      expect(areaService.isPointInArea(0.8, 0.8, shapeArea), isFalse);
    });

    test('FavoriteFolderService 默认收藏夹唯一且空名称拒绝创建', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('gh_fav_folder_reg_');
      final isar = await _openTestIsar(tempDir, 'fav_folder_reg');
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final folderService = FavoriteFolderService(isar);
      final defaultA = await folderService.getOrCreateDefaultFolder(1);
      final defaultB = await folderService.getOrCreateDefaultFolder(1);

      expect(defaultA.id, defaultB.id);
      expect(folderService.isDefaultFolder(defaultA), isTrue);
      await expectLater(
        () => folderService.createFolder(1, '   '),
        throwsStateError,
      );
    });
  });
}
