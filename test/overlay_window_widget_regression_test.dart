import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/overlay_snapshot.dart';
import 'package:grenade_helper/screens/grenade_preview_screen.dart';
import 'package:grenade_helper/screens/overlay_window.dart';
import 'package:grenade_helper/services/data_service.dart';
import 'package:grenade_helper/services/overlay_state_service.dart';
import 'package:grenade_helper/services/settings_service.dart';
import 'package:grenade_helper/widgets/grenade_type_icon.dart';

Map<HotkeyAction, HotkeyConfig> _createTestHotkeys({
  LogicalKeyboardKey decreaseSpeedKey = LogicalKeyboardKey.minus,
  LogicalKeyboardKey increaseSpeedKey = LogicalKeyboardKey.equal,
  LogicalKeyboardKey fullscreenKey = LogicalKeyboardKey.enter,
}) {
  return {
    HotkeyAction.toggleOverlay: HotkeyConfig(
      key: LogicalKeyboardKey.keyG,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.navigateUp:
        const HotkeyConfig(key: LogicalKeyboardKey.arrowUp),
    HotkeyAction.navigateDown:
        const HotkeyConfig(key: LogicalKeyboardKey.arrowDown),
    HotkeyAction.navigateLeft:
        const HotkeyConfig(key: LogicalKeyboardKey.arrowLeft),
    HotkeyAction.navigateRight:
        const HotkeyConfig(key: LogicalKeyboardKey.arrowRight),
    HotkeyAction.prevGrenade:
        const HotkeyConfig(key: LogicalKeyboardKey.pageUp),
    HotkeyAction.nextGrenade:
        const HotkeyConfig(key: LogicalKeyboardKey.pageDown),
    HotkeyAction.prevStep:
        const HotkeyConfig(key: LogicalKeyboardKey.bracketLeft),
    HotkeyAction.nextStep:
        const HotkeyConfig(key: LogicalKeyboardKey.bracketRight),
    HotkeyAction.toggleSmoke:
        const HotkeyConfig(key: LogicalKeyboardKey.digit7),
    HotkeyAction.toggleFlash:
        const HotkeyConfig(key: LogicalKeyboardKey.digit8),
    HotkeyAction.toggleMolotov:
        const HotkeyConfig(key: LogicalKeyboardKey.digit9),
    HotkeyAction.toggleHE: const HotkeyConfig(key: LogicalKeyboardKey.digit0),
    HotkeyAction.toggleWallbang: HotkeyConfig(
      key: LogicalKeyboardKey.digit0,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.hideOverlay:
        const HotkeyConfig(key: LogicalKeyboardKey.escape),
    HotkeyAction.togglePlayPause: HotkeyConfig(
      key: LogicalKeyboardKey.keyP,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.toggleMediaFullscreenPreview: HotkeyConfig(
      key: fullscreenKey,
      modifiers: fullscreenKey == LogicalKeyboardKey.enter
          ? {LogicalKeyboardKey.alt}
          : const {},
    ),
    HotkeyAction.increaseNavSpeed: HotkeyConfig(key: increaseSpeedKey),
    HotkeyAction.decreaseNavSpeed: HotkeyConfig(key: decreaseSpeedKey),
    HotkeyAction.scrollUp: HotkeyConfig(
      key: LogicalKeyboardKey.pageUp,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.scrollDown: HotkeyConfig(
      key: LogicalKeyboardKey.pageDown,
      modifiers: {LogicalKeyboardKey.alt},
    ),
  };
}

Widget _wrapOverlayApp({
  Key? overlayKey,
  required OverlayStateService overlayState,
  required Map<HotkeyAction, HotkeyConfig> hotkeys,
  bool isVisible = true,
}) {
  return MaterialApp(
    home: SizedBox(
      width: 900,
      height: 800,
      child: OverlayWindow(
        key: overlayKey,
        initialHotkeys: hotkeys,
        overlayState: overlayState,
        isVisible: isVisible,
        onClose: () async {},
        onMinimize: () async {},
        onStartDrag: () {},
      ),
    ),
  );
}

void main() {
  setUp(() {
    GrenadeTypeIcon.useLegacy = true;
  });

  tearDown(() {
    GrenadeTypeIcon.useLegacy = false;
  });

  testWidgets('OverlayWindow 在不可见态下返回禁用的 TickerMode 并停止渲染内部界面', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = OverlayStateService();
    addTearDown(state.dispose);
    final hotkeys = _createTestHotkeys();

    await tester.pumpWidget(
      _wrapOverlayApp(
        overlayState: state,
        hotkeys: hotkeys,
        isVisible: false,
      ),
    );
    await tester.pump();

    final tickerFinder = find.descendant(
      of: find.byType(OverlayWindow),
      matching: find.byType(TickerMode),
    );
    expect(tickerFinder, findsOneWidget);
    final tickerMode = tester.widget<TickerMode>(tickerFinder);
    expect(tickerMode.enabled, isFalse);
    expect(
      find.descendant(
        of: tickerFinder,
        matching: find.byType(SizedBox),
      ),
      findsOneWidget,
    );
    expect(find.text('请先进入地图'), findsNothing);
    expect(find.text('未选择地图'), findsNothing);

    await tester.pumpWidget(
      _wrapOverlayApp(
        overlayState: state,
        hotkeys: hotkeys,
        isVisible: true,
      ),
    );
    await tester.pump();

    expect(find.text('未选择地图'), findsOneWidget);
    expect(find.text('请先进入地图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OverlayWindow 正确渲染无地图与无道具空状态', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = OverlayStateService();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _wrapOverlayApp(
        overlayState: state,
        hotkeys: _createTestHotkeys(),
      ),
    );
    await tester.pump();

    expect(find.text('未选择地图'), findsOneWidget);
    expect(find.text('请先进入地图'), findsOneWidget);
    expect(find.text('在主界面选择一张地图后\n悬浮窗将显示该地图的道具'), findsOneWidget);

    state.applyMapSnapshot(
      const OverlayMapSnapshot(
        mapId: 1,
        mapName: 'Mirage',
        layerId: 10,
        layerAssetPath: '',
        grenades: [],
      ),
    );
    await tester.pump();

    expect(find.text('Mirage'), findsOneWidget);
    expect(find.text('该地图暂无道具'), findsOneWidget);
    expect(find.text('请先在地图上添加道具点位'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OverlayWindow 点击类型筛选图标可切换过滤并同步空状态切换', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = OverlayStateService();
    addTearDown(state.dispose);

    state.applyMapSnapshot(
      const OverlayMapSnapshot(
        mapId: 2,
        mapName: 'Inferno',
        layerId: 20,
        layerAssetPath: '',
        grenades: [
          OverlayGrenadeItem(
            id: 101,
            title: '香蕉道瞬爆闪',
            type: GrenadeType.flash,
            xRatio: 0.35,
            yRatio: 0.45,
            steps: [
              OverlayStepItem(
                stepIndex: 0,
                title: '准备站位',
                description: '贴紧木桶左键投掷',
                medias: [],
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrapOverlayApp(
        overlayState: state,
        hotkeys: _createTestHotkeys(),
      ),
    );
    await tester.pump();

    expect(find.byType(GrenadeTypeIcon), findsNWidgets(5));
    expect(find.text('Inferno'), findsOneWidget);
    expect(find.text('香蕉道瞬爆闪'), findsOneWidget);
    expect(find.text('贴紧木桶左键投掷'), findsOneWidget);
    expect(find.text('道具 1/1'), findsOneWidget);
    expect(find.text('准备站位 1/1'), findsOneWidget);

    final smokeFilterFinder = find.byWidgetPredicate(
      (widget) => widget is GrenadeTypeIcon && widget.type == GrenadeType.smoke,
    );
    final flashFilterFinder = find.byWidgetPredicate(
      (widget) => widget is GrenadeTypeIcon && widget.type == GrenadeType.flash,
    );
    expect(smokeFilterFinder, findsOneWidget);
    expect(flashFilterFinder, findsOneWidget);

    await tester.tap(smokeFilterFinder);
    await tester.pump();
    expect(state.activeFilters.contains(GrenadeType.smoke), isFalse);
    expect(find.text('贴紧木桶左键投掷'), findsOneWidget);

    await tester.tap(smokeFilterFinder);
    await tester.pump();
    expect(state.activeFilters.contains(GrenadeType.smoke), isTrue);

    await tester.tap(flashFilterFinder);
    await tester.pump();

    expect(state.activeFilters.contains(GrenadeType.flash), isFalse);
    expect(find.text('该地图暂无道具'), findsOneWidget);
    expect(find.text('贴紧木桶左键投掷'), findsNothing);

    await tester.tap(flashFilterFinder);
    await tester.pump();

    expect(state.activeFilters.contains(GrenadeType.flash), isTrue);
    expect(find.text('该地图暂无道具'), findsNothing);
    expect(find.text('道具 1/1'), findsOneWidget);
    expect(find.text('使用方向键移动准星'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OverlayWindowState 暴露完整公开契约且 reloadHotkeys 立即更新显示',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final overlayKey = GlobalKey<OverlayWindowState>();
    final state = OverlayStateService();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _wrapOverlayApp(
        overlayKey: overlayKey,
        overlayState: state,
        hotkeys: _createTestHotkeys(),
      ),
    );
    await tester.pump();

    final overlayWindowState = overlayKey.currentState!;
    expect(overlayWindowState.persistedWindowPosition, isNull);
    expect(overlayWindowState.blocksDirectionalNavigation, isFalse);
    expect(find.text('速度:3/5 (-/=)'), findsOneWidget);
    expect(find.textContaining('Alt + Enter 全屏'), findsOneWidget);

    overlayWindowState.reloadHotkeys(
      _createTestHotkeys(
        decreaseSpeedKey: LogicalKeyboardKey.f9,
        increaseSpeedKey: LogicalKeyboardKey.f10,
        fullscreenKey: LogicalKeyboardKey.f11,
      ),
    );
    await tester.pump();

    expect(find.text('速度:3/5 (F9/F10)'), findsOneWidget);
    expect(find.textContaining('F11 全屏'), findsOneWidget);

    overlayWindowState.scrollContent(100);
    await overlayWindowState.pauseActiveVideoPlayback();
    await overlayWindowState.exitFullscreenPreviewIfNeeded();
    await overlayWindowState.toggleMediaFullscreenPreview();
    expect(overlayWindowState.blocksDirectionalNavigation, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GrenadePreviewScreen 渲染标题、状态标签与媒体占位保持一致', (tester) async {
    final previewItem = GrenadePreviewItem(
      uniqueId: 'g-1',
      title: 'A1过点烟',
      type: GrenadeType.smoke,
      mapName: 'Mirage',
      layerName: '默认图层',
      author: '测试作者',
      status: ImportStatus.newItem,
      updatedAt: DateTime(2026, 11, 24),
      rawData: const {
        'steps': [
          {
            'title': '站位说明',
            'description': '瞄准天线顶端',
            'medias': [
              {'path': 'demo.mp4', 'type': MediaType.video},
            ],
          },
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GrenadePreviewScreen(
          grenade: previewItem,
          memoryImages: const {
            'demo.mp4': [1, 2, 3],
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('A1过点烟'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('烟雾弹'), findsOneWidget);
    expect(find.text('Mirage - 默认图层'), findsOneWidget);
    expect(find.text('站位说明'), findsOneWidget);
    expect(find.text('瞄准天线顶端'), findsOneWidget);
    expect(find.text('视频预览（导入后可播放）'), findsOneWidget);
    expect(find.text('作者: 测试作者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
