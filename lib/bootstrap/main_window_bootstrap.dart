import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../data/builtin_maps.dart';
import '../models.dart';
import '../models/grenade_tag.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import '../providers.dart';
import '../services/hotkey_service.dart';
import '../services/media_handle_service.dart';
import '../services/migration_service.dart';
import '../services/overlay_ipc_server.dart';
import '../services/settings_service.dart';
import '../services/tag_service.dart';
import '../services/window_service.dart';
import '../widgets/grenade_type_icon.dart';
import 'app_globals.dart';
import 'main_app_host.dart';

const Map<HotkeyAction, String> _simpleOverlayHotkeyCommands = {
  HotkeyAction.prevGrenade: 'prev_grenade',
  HotkeyAction.nextGrenade: 'next_grenade',
  HotkeyAction.prevStep: 'prev_step',
  HotkeyAction.nextStep: 'next_step',
  HotkeyAction.toggleSmoke: 'toggle_smoke',
  HotkeyAction.toggleFlash: 'toggle_flash',
  HotkeyAction.toggleMolotov: 'toggle_molotov',
  HotkeyAction.toggleHE: 'toggle_he',
  HotkeyAction.toggleWallbang: 'toggle_wallbang',
  HotkeyAction.togglePlayPause: 'toggle_play_pause',
  HotkeyAction.toggleMediaFullscreenPreview: 'toggle_media_fullscreen_preview',
  HotkeyAction.increaseNavSpeed: 'increase_nav_speed',
  HotkeyAction.decreaseNavSpeed: 'decrease_nav_speed',
  HotkeyAction.scrollUp: 'scroll_up',
  HotkeyAction.scrollDown: 'scroll_down',
};

const Map<HotkeyAction, String> _directionalOverlayNavActions = {
  HotkeyAction.navigateUp: 'up',
  HotkeyAction.navigateDown: 'down',
  HotkeyAction.navigateLeft: 'left',
  HotkeyAction.navigateRight: 'right',
};

// 运行主窗口
Future<void> runMainWindow() async {
  final dataPath = await _resolveDataPath();
  final dataDir = Directory(dataPath);
  if (!await dataDir.exists()) {
    await dataDir.create(recursive: true);
  }

  final isar = await Isar.open(
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
    directory: dataPath,
  );
  globalIsar = isar;

  await initMapData(isar);
  await _runStartupMigrations(isar);

  globalSettingsService = SettingsService();
  await globalSettingsService!.init();
  GrenadeTypeIcon.useLegacy = globalSettingsService!.getMapMarkerUseEmoji();

  if (SettingsService.isDesktop) {
    _initDesktopServices(isar);
  }

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const MainApp(),
    ),
  );
}

Future<String> _resolveDataPath() async {
  if (SettingsService.isDesktop) {
    return SettingsService.getDataPathBeforeInit();
  }
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

Future<void> _runStartupMigrations(Isar isar) async {
  final migrationService = MigrationService(isar);
  final mediaPathMigratedCount =
      await migrationService.migrateMediaPathsToCurrentDirectory();
  if (mediaPathMigratedCount > 0) {
    debugPrint('已修正 $mediaPathMigratedCount 条迁移后的媒体路径');
  }
  final migratedCount = await migrationService.migrateGrenadeUuids();
  if (migratedCount > 0) {
    debugPrint('已为 $migratedCount 个旧道具生成 UUID');
  }
  final favoriteMigratedCount = await migrationService.migrateFavoriteFolders();
  if (favoriteMigratedCount > 0) {
    debugPrint('已修复 $favoriteMigratedCount 个收藏夹归档数据');
  }

  final tagMigrationSummary = await migrationService.migrateTagUuids();
  _logTagUuidMigration(tagMigrationSummary);

  final tagService = TagService(isar);
  final ensuredSystemTagSummary = await tagService.ensureSystemTagsForAllMaps(
    cleanupObsoleteSystemTags: true,
  );
  _logEnsuredSystemTags(ensuredSystemTagSummary);

  final defaultAreaSummary =
      await tagService.initializeBuiltinAreaMetadataForAllMaps();
  _logDefaultAreaSummary(defaultAreaSummary);
}

void _logTagUuidMigration(TagUuidMigrationSummary summary) {
  if (summary.migratedCount <= 0) return;
  debugPrint('已为 ${summary.migratedCount} 个标签补齐 UUID');
  for (final detail in summary.details) {
    debugPrint(
      '  标签UUID补齐：地图=${detail.mapName}(id=${detail.mapId})，'
      '标签=${detail.tagName}(id=${detail.tagId})，'
      '维度=${detail.dimensionName}，'
      '系统标签=${detail.isSystem}，'
      '原因=${detail.reason}',
    );
    debugPrint(
      '  UUID：旧=[${detail.oldUuid.isEmpty ? "空" : detail.oldUuid}] -> '
      '新=[${detail.newUuid}]',
    );
  }
}

String _summarizeRefs(List<String> refs, {int maxItems = 5}) {
  if (refs.isEmpty) return '无';
  final visible = refs.take(maxItems).join('，');
  if (refs.length <= maxItems) return visible;
  return '$visible 等${refs.length}项';
}

void _logEnsuredSystemTags(EnsureSystemTagSummary summary) {
  if (summary.addedTags > 0 ||
      summary.updatedTags > 0 ||
      summary.removedObsoleteTags > 0) {
    debugPrint(
      '已校正系统标签：地图${summary.processedMaps}张，'
      '新增${summary.addedTags}个，'
      '更新${summary.updatedTags}个，'
      '清理${summary.removedObsoleteTags}个',
    );
  }
  if (summary.keptObsoleteTagsInUse <= 0) return;
  debugPrint(
    '检测到${summary.keptObsoleteTagsInUse}个废弃系统标签仍被引用，已跳过清理',
  );
  for (final detail in summary.keptObsoleteTagDetails) {
    debugPrint(
      '  来源：地图=${detail.mapName}(id=${detail.mapId})，'
      '标签=${detail.tagName}(id=${detail.tagId})，'
      '维度=${detail.dimensionName}，'
      'UUID=${detail.tagUuid}',
    );
    debugPrint(
      '  引用：道具${detail.grenadeRefs.length}个'
      ' [${_summarizeRefs(detail.grenadeRefs)}]；'
      '区域${detail.areaRefs.length}个'
      ' [${_summarizeRefs(detail.areaRefs)}]',
    );
  }
}

void _logDefaultAreaSummary(DefaultAreaTagReimportSummary summary) {
  if (summary.addedTags <= 0 &&
      summary.updatedTags <= 0 &&
      summary.addedAreas <= 0 &&
      summary.updatedAreas <= 0 &&
      summary.removedDuplicateAreas <= 0) {
    return;
  }
  debugPrint(
    '已初始化默认区域：地图${summary.processedMaps}张，'
    '区域标签新增${summary.addedTags}个，'
    '区域标签更新${summary.updatedTags}个，'
    '区域新增${summary.addedAreas}个，'
    '区域更新${summary.updatedAreas}个，'
    '去重${summary.removedDuplicateAreas}个',
  );
  for (final detail in summary.addedTagDetails) {
    debugPrint(
      '  区域标签新增：地图=${detail.mapName}(id=${detail.mapId})，'
      '标签=${detail.tagName}，'
      'UUID=${detail.newTagUuid}，'
      '颜色=${detail.newColorValue}',
    );
  }
  for (final detail in summary.updatedTagDetails) {
    debugPrint(
      '  区域标签更新：地图=${detail.mapName}(id=${detail.mapId})，'
      '标签=${detail.tagName}(id=${detail.tagId ?? -1})，'
      '原因=${detail.reasonSummary}',
    );
    debugPrint(
      '  变化：UUID=[${detail.oldTagUuid.isEmpty ? "空" : detail.oldTagUuid}] -> '
      '[${detail.newTagUuid}]；'
      '颜色=[${detail.oldColorValue}] -> [${detail.newColorValue}]',
    );
  }
}

void _initDesktopServices(Isar isar) {
  globalHotkeyService = HotkeyService(globalSettingsService!);
  globalWindowService = WindowService(globalSettingsService!);
  globalOverlayServer = OverlayIpcServer(
    isar: isar,
    settingsService: globalSettingsService!,
    onOverlayHidden: () {
      if (globalWindowService?.isOverlayVisible == true) {
        unawaited(globalWindowService!.hideOverlay());
      }
    },
  );
  MediaHandleService.externalReleaser = (paths) async {
    await globalOverlayServer?.releaseMediaFiles(paths);
  };

  globalWindowService!.setHotkeyService(globalHotkeyService!);
  globalWindowService!.onCloseDatabase = () async {
    if (globalIsar != null && globalIsar!.isOpen) {
      await globalIsar!.close();
      debugPrint('[Main] Isar database closed.');
    }
  };

  for (final entry in _simpleOverlayHotkeyCommands.entries) {
    globalHotkeyService!.registerHandler(entry.key, () {
      sendOverlayCommand(entry.value);
    });
  }
  for (final entry in _directionalOverlayNavActions.entries) {
    globalHotkeyService!.registerHandler(entry.key, () {
      sendOverlayCommand('start_navigation', {'direction': entry.value});
    });
    globalHotkeyService!.registerKeyUpHandler(entry.key, () {
      sendOverlayCommand('stop_navigation', {'direction': entry.value});
    });
  }
  globalHotkeyService!.registerHandler(HotkeyAction.hideOverlay, () {
    unawaited(globalWindowService!.hideOverlay());
  });
}

// 预填充内置地图并支持多楼层与旧路径迁移
Future<void> initMapData(Isar isar) async {
  final isFirstRun = await isar.gameMaps.count() == 0;
  if (isFirstRun) {
    debugPrint("检测到首次运行，正在写入地图数据...");
  }

  final addedCount = await ensureBuiltinMaps(isar);

  if (isFirstRun) {
    debugPrint("地图数据写入完成！");
  } else if (addedCount > 0) {
    debugPrint("已补充官方地图：$addedCount 张");
  }
}

Future<int> ensureBuiltinMaps(Isar isar) async {
  final existingMaps = await isar.gameMaps.where().findAll();
  final existingByKey = <String, List<GameMap>>{};
  for (final map in existingMaps) {
    final config = findBuiltinMapConfig(map);
    if (config != null) {
      existingByKey.putIfAbsent(config.key, () => []).add(map);
    }
  }

  final mapsToMigrate = <GameMap>[];
  final configsToAdd = <BuiltinMapConfig>[];
  for (final config in builtinMapsConfig) {
    final matched = existingByKey[config.key];
    if (matched != null && matched.isNotEmpty) {
      for (final existing in matched) {
        final migratedBg =
            normalizeLegacyBuiltinAssetPath(existing.backgroundPath);
        if (migratedBg != existing.backgroundPath) {
          existing.backgroundPath = migratedBg;
          mapsToMigrate.add(existing);
        }
      }
      continue;
    }
    configsToAdd.add(config);
  }

  if (mapsToMigrate.isEmpty && configsToAdd.isEmpty) {
    return 0;
  }

  var addedCount = 0;
  await isar.writeTxn(() async {
    if (mapsToMigrate.isNotEmpty) {
      await isar.gameMaps.putAll(mapsToMigrate);
    }
    for (final config in configsToAdd) {
      final map = GameMap(
        name: config.name,
        backgroundPath: config.backgroundPath,
        iconPath: config.iconPath,
      );
      await isar.gameMaps.put(map);

      for (int i = 0; i < config.floors.length; i++) {
        final layer = MapLayer(
          name: config.floorNames[i],
          assetPath: 'assets/maps/${config.floors[i]}',
          sortOrder: i,
        );
        await isar.mapLayers.put(layer);
        map.layers.add(layer);
      }
      await map.layers.save();
      addedCount++;
    }
  });

  return addedCount;
}
