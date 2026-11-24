import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/bootstrap/app_globals.dart' as globals;
import 'package:grenade_helper/bootstrap/main_app_host.dart' as host;
import 'package:grenade_helper/bootstrap/main_window_bootstrap.dart';
import 'package:grenade_helper/bootstrap/overlay_process_bootstrap.dart'
    as overlay_boot;
import 'package:grenade_helper/data/builtin_maps.dart';
import 'package:grenade_helper/main.dart' as app_main;
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/providers.dart';
import 'package:grenade_helper/screens/app_shell.dart';
import 'package:grenade_helper/screens/home/global_search_delegate.dart'
    as home_search;
import 'package:grenade_helper/screens/home_screen.dart';
import 'package:grenade_helper/services/overlay_state_service.dart';
import 'package:grenade_helper/services/settings_service.dart';
import 'package:grenade_helper/theme/app_design_system.dart';
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

void _seedSampleHomeDataSync(Isar isar) {
  isar.writeTxnSync(() {
    final mirage = GameMap(
      name: 'Mirage',
      backgroundPath: 'assets/backgrounds/mirage_bg.webp',
      iconPath: 'assets/icons/mirage_icon.svg',
    );
    isar.gameMaps.putSync(mirage);
    final mirageLayer = MapLayer(
      name: 'Default',
      assetPath: 'assets/maps/mirage.png',
      sortOrder: 0,
    );
    isar.mapLayers.putSync(mirageLayer);
    mirage.layers.add(mirageLayer);
    mirage.layers.saveSync();

    final grenade = Grenade(
      title: 'Mirage A点拱门烟',
      type: GrenadeType.smoke,
      team: TeamType.t,
      xRatio: 0.4,
      yRatio: 0.5,
      created: DateTime(2026, 1, 1),
      updated: DateTime(2026, 1, 1),
    );
    isar.grenades.putSync(grenade);
    mirageLayer.grenades.add(grenade);
    mirageLayer.grenades.saveSync();

    final overpass = GameMap(
      name: 'Overpass',
      backgroundPath: 'assets/backgrounds/overpass_bg.webp',
      iconPath: 'assets/icons/overpass_icon.svg',
    );
    isar.gameMaps.putSync(overpass);
    final overpassLayer = MapLayer(
      name: 'Default',
      assetPath: 'assets/maps/overpass.png',
      sortOrder: 0,
    );
    isar.mapLayers.putSync(overpassLayer);
    overpass.layers.add(overpassLayer);
    overpass.layers.saveSync();

    final customMap = GameMap(
      name: 'Cache Custom',
      backgroundPath: '',
      iconPath: '',
    );
    isar.gameMaps.putSync(customMap);
    final customLayer = MapLayer(
      name: 'Default',
      assetPath: '',
      sortOrder: 0,
    );
    isar.mapLayers.putSync(customLayer);
    customMap.layers.add(customLayer);
    customMap.layers.saveSync();
  });
}

void main() {
  setUpAll(() async {
    await _initIsarCoreForTest();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    app_main.globalSettingsService = null;
    app_main.globalHotkeyService = null;
    app_main.globalWindowService = null;
    app_main.globalOverlayServer = null;
    app_main.globalIsar = null;
  });

  group('main.dart 与 home_screen.dart 导出门面契约', () {
    test('导出全局变量、顶层转发函数与宿主类型保持一致', () {
      expect(identical(app_main.MainApp, host.MainApp), isTrue);
      expect(
        identical(app_main.OverlayWindowApp, overlay_boot.OverlayWindowApp),
        isTrue,
      );
      expect(
        identical(
          app_main.OverlayWindowAppState,
          overlay_boot.OverlayWindowAppState,
        ),
        isTrue,
      );
      expect(
        identical(GlobalSearchDelegate, home_search.GlobalSearchDelegate),
        isTrue,
      );

      expect(app_main.globalSettingsService, isNull);
      expect(app_main.globalHotkeyService, isNull);
      expect(app_main.globalWindowService, isNull);
      expect(app_main.globalOverlayServer, isNull);
      expect(app_main.globalIsar, isNull);
      expect(globals.globalIsar, isNull);

      final dummyMap =
          GameMap(name: 'Mirage', backgroundPath: '', iconPath: '');
      final dummyLayer = MapLayer(name: 'Default', assetPath: '', sortOrder: 0);
      expect(() => app_main.sendOverlayCommand('reload_data'), returnsNormally);
      expect(
        () => app_main.setOverlayActiveMap(dummyMap, dummyLayer),
        returnsNormally,
      );
      expect(() => app_main.clearOverlayActiveMap(), returnsNormally);
    });

    testWidgets('OverlayWindowApp 公开状态契约保留 overlayWindowKey', (tester) async {
      final appKey = GlobalKey<app_main.OverlayWindowAppState>();
      final overlayState = OverlayStateService();
      final visibleNotifier = ValueNotifier<bool>(false);
      addTearDown(overlayState.dispose);
      addTearDown(visibleNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: app_main.OverlayWindowApp(
            key: appKey,
            initialHotkeys: const <HotkeyAction, HotkeyConfig>{},
            overlayState: overlayState,
            isVisibleListenable: visibleNotifier,
            onClose: () async {},
            onMinimize: () async {},
          ),
        ),
      );

      expect(appKey.currentState, isNotNull);
      expect(appKey.currentState!.overlayWindowKey.currentState, isNotNull);
    });
  });

  group('主窗口引导预填充与旧路径迁移', () {
    test('ensureBuiltinMaps 首次写入全部官方地图并支持旧背景路径迁移', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('bootstrap_maps_test_');
      final isar = await _openTestIsar(tempDir, 'bootstrap_maps');
      try {
        final added = await ensureBuiltinMaps(isar);
        expect(added, builtinMapsConfig.length);

        final allMaps = await isar.gameMaps.where().findAll();
        expect(allMaps.length, builtinMapsConfig.length);

        final nuke = allMaps.firstWhere((m) => m.name == 'Nuke');
        await nuke.layers.load();
        expect(nuke.layers.length, 2);

        final mirage = allMaps.firstWhere((m) => m.name == 'Mirage');
        await isar.writeTxn(() async {
          mirage.backgroundPath = 'assets/backgrounds/mirage_bg.png';
          await isar.gameMaps.put(mirage);
        });

        final secondAdded = await ensureBuiltinMaps(isar);
        expect(secondAdded, 0);

        final migratedMirage = await isar.gameMaps.get(mirage.id);
        expect(
          migratedMirage?.backgroundPath,
          'assets/backgrounds/mirage_bg.webp',
        );
      } finally {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('HomeScreen、GlobalSearchDelegate 与 AppShell 渲染与交互', () {
    testWidgets(
      'HomeScreen 渲染现役地图、后备图池切换及全局搜索结果',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        late Directory tempDir;
        late Isar isar;
        await tester.runAsync(() async {
          tempDir = await Directory.systemTemp.createTemp('home_screen_test_');
          isar = await _openTestIsar(tempDir, 'home_screen');
          _seedSampleHomeDataSync(isar);
        });

        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [isarProvider.overrideWithValue(isar)],
              child: MaterialApp(
                theme: AppTheme.light(),
                home: const HomeScreen(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('地图库'), findsOneWidget);
          expect(find.text('3 张地图'), findsOneWidget);
          expect(find.text('Mirage'), findsOneWidget);
          expect(find.text('非现役地图池'), findsOneWidget);
          expect(find.text('含人质图'), findsOneWidget);
          expect(find.text('Cache Custom'), findsOneWidget);
          expect(find.text('添加自定义地图'), findsOneWidget);

          await tester.tap(find.text('非现役地图池'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();

          expect(find.text('非现役地图池'), findsOneWidget);
          expect(find.text('1 张地图 · 含人质图'), findsOneWidget);
          expect(find.text('Overpass'), findsOneWidget);

          await tester.tap(find.byTooltip('返回地图库'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
          expect(find.text('地图库'), findsOneWidget);

          await tester.tap(find.byType(TextField).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(find.byType(TextField).last, '拱门');
          await tester.pump();

          expect(find.text('Mirage A点拱门烟'), findsOneWidget);
          expect(find.text('Mirage'), findsWidgets);

          await tester.tap(find.byIcon(Icons.clear));
          await tester.pump();
          expect(find.text('Mirage A点拱门烟'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await isar.close(deleteFromDisk: true);
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          });
        }
      },
    );

    testWidgets(
      'AppShell 桌面侧边导航栏渲染并支持页面切换',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        late Directory tempDir;
        late Isar isar;
        await tester.runAsync(() async {
          tempDir = await Directory.systemTemp.createTemp('app_shell_test_');
          isar = await _openTestIsar(tempDir, 'app_shell');
          _seedSampleHomeDataSync(isar);
        });

        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [isarProvider.overrideWithValue(isar)],
              child: MaterialApp(
                theme: AppTheme.dark(),
                home: const AppShell(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('Grenade Helper'), findsOneWidget);
          expect(find.text('数据传输'), findsOneWidget);
          expect(find.text('设置'), findsOneWidget);
          expect(find.byTooltip('关于'), findsOneWidget);

          await tester.tap(find.text('数据传输'));
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('导入道具包'), findsOneWidget);
          expect(find.text('导出与分享'), findsOneWidget);
          expect(find.text('局域网同步'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await isar.close(deleteFromDisk: true);
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          });
        }
      },
    );

    testWidgets(
      'AppShell 移动端液态玻璃底栏渲染并支持切换',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        late Directory tempDir;
        late Isar isar;
        await tester.runAsync(() async {
          tempDir = await Directory.systemTemp.createTemp('app_shell_mobile_');
          isar = await _openTestIsar(tempDir, 'app_shell_mobile');
          _seedSampleHomeDataSync(isar);
        });

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [isarProvider.overrideWithValue(isar)],
              child: MaterialApp(
                theme: AppTheme.light(),
                home: const AppShell(),
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('传输'), findsOneWidget);
          expect(find.text('设置'), findsOneWidget);

          await tester.tap(find.text('传输'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          expect(find.text('导入道具包'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await isar.close(deleteFromDisk: true);
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          });
        }
      },
    );
  });
}
