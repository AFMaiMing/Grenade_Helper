import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../models/overlay_snapshot.dart';
import '../screens/overlay_window.dart';
import '../services/media_handle_service.dart';
import '../services/overlay_ipc_client.dart';
import '../services/overlay_state_service.dart';
import '../services/settings_service.dart';
import '../widgets/grenade_type_icon.dart';

NavigationDirection? _parseDirection(String? dirStr) {
  switch (dirStr) {
    case 'up':
      return NavigationDirection.up;
    case 'down':
      return NavigationDirection.down;
    case 'left':
      return NavigationDirection.left;
    case 'right':
      return NavigationDirection.right;
    default:
      return null;
  }
}

// 运行悬浮窗独立子进程
Future<void> runOverlayProcess(List<String> args) async {
  final ipcArgs = OverlayIpcClient.parseArgs(args);
  if (ipcArgs == null) {
    exit(0);
  }

  final client = OverlayIpcClient(port: ipcArgs.port, token: ipcArgs.token);
  client.onDisconnected = () => exit(0);

  late final OverlayInitConfig initConfig;
  try {
    initConfig = await client.connectAndAwaitInit();
  } catch (_) {
    exit(0);
  }

  GrenadeTypeIcon.useLegacy = initConfig.useLegacyIcons;

  await windowManager.ensureInitialized();
  final size = SettingsService.calculateSizePixels(initConfig.sizeIndex);

  const windowOptions = WindowOptions(
    minimumSize: Size(300, 400),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setSize(Size(size.$1, size.$2));
    await windowManager.setPosition(Offset(initConfig.x, initConfig.y));
  });

  final overlayState = OverlayStateService();
  overlayState.setOpacity(initConfig.opacity);
  overlayState.setNavSpeedLevel(initConfig.navSpeedLevel);
  if (initConfig.mapSnapshot != null) {
    overlayState.applyMapSnapshot(initConfig.mapSnapshot!);
  }

  final overlayAppKey = GlobalKey<OverlayWindowAppState>();
  final isOverlayVisibleNotifier = ValueNotifier<bool>(false);
  const overlayWindowChannel = MethodChannel('grenade_helper/overlay_window');

  Future<void> showNativeOverlay() async {
    if (Platform.isWindows) {
      await overlayWindowChannel.invokeMethod<void>('showNoActivate');
    } else {
      await windowManager.show(inactive: true);
    }
  }

  Future<void> hideNativeOverlay() async {
    if (Platform.isWindows) {
      await overlayWindowChannel.invokeMethod<void>('hide');
    } else {
      await windowManager.hide();
    }
  }

  Future<void> persistOverlayBounds() async {
    final preferredPosition = overlayAppKey
        .currentState?.overlayWindowKey.currentState?.persistedWindowPosition;
    final position =
        preferredPosition ?? (await windowManager.getBounds()).topLeft;
    client.sendEvent('bounds_changed', {
      'x': position.dx,
      'y': position.dy,
    });
  }

  Future<void> pauseOverlayVideoPlayback() async {
    await overlayAppKey.currentState?.overlayWindowKey.currentState
        ?.pauseActiveVideoPlayback();
  }

  bool blocksDirectionalNavigation() {
    return overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.blocksDirectionalNavigation ==
        true;
  }

  Future<void> hideOverlay({bool notifyMain = false}) async {
    if (!isOverlayVisibleNotifier.value) return;
    await pauseOverlayVideoPlayback();
    await overlayAppKey.currentState?.overlayWindowKey.currentState
        ?.exitFullscreenPreviewIfNeeded();
    await persistOverlayBounds();
    overlayState.stopAllNavigation();
    isOverlayVisibleNotifier.value = false;
    await hideNativeOverlay();
    if (notifyMain) {
      client.sendEvent('hidden');
    }
  }

  Future<void> showOverlay() async {
    isOverlayVisibleNotifier.value = true;
    await showNativeOverlay();
  }

  client.onCommand = (command, cmdArgs) async {
    await _handleOverlayCommand(
      command: command,
      cmdArgs: cmdArgs,
      client: client,
      overlayState: overlayState,
      overlayAppKey: overlayAppKey,
      isOverlayVisibleNotifier: isOverlayVisibleNotifier,
      showOverlay: showOverlay,
      hideOverlay: hideOverlay,
      pauseOverlayVideoPlayback: pauseOverlayVideoPlayback,
      persistOverlayBounds: persistOverlayBounds,
      blocksDirectionalNavigation: blocksDirectionalNavigation,
    );
  };

  runApp(
    ExcludeSemantics(
      excluding: !kIsWeb && Platform.isWindows,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.orange,
          scaffoldBackgroundColor: Colors.transparent,
          useMaterial3: true,
        ),
        home: OverlayWindowApp(
          key: overlayAppKey,
          initialHotkeys: initConfig.hotkeys,
          overlayState: overlayState,
          isVisibleListenable: isOverlayVisibleNotifier,
          onClose: () => hideOverlay(notifyMain: true),
          onMinimize: () => hideOverlay(notifyMain: true),
        ),
      ),
    ),
  );

  client.sendEvent('ready');
}

Future<void> _handleOverlayCommand({
  required String command,
  required Map<String, dynamic>? cmdArgs,
  required OverlayIpcClient client,
  required OverlayStateService overlayState,
  required GlobalKey<OverlayWindowAppState> overlayAppKey,
  required ValueNotifier<bool> isOverlayVisibleNotifier,
  required Future<void> Function() showOverlay,
  required Future<void> Function({bool notifyMain}) hideOverlay,
  required Future<void> Function() pauseOverlayVideoPlayback,
  required Future<void> Function() persistOverlayBounds,
  required bool Function() blocksDirectionalNavigation,
}) async {
  switch (command) {
    case 'set_map_snapshot':
      if (cmdArgs != null) {
        overlayState.applyMapSnapshot(OverlayMapSnapshot.fromJson(cmdArgs));
      }
      break;
    case 'clear_map':
      overlayState.clearMap();
      break;
    case 'show_overlay':
      await showOverlay();
      break;
    case 'hide_overlay':
      await hideOverlay();
      break;
    case 'close':
      await pauseOverlayVideoPlayback();
      await overlayAppKey.currentState?.overlayWindowKey.currentState
          ?.exitFullscreenPreviewIfNeeded();
      if (isOverlayVisibleNotifier.value) {
        await persistOverlayBounds();
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await client.close();
      exit(0);
    case 'prev_grenade':
      overlayState.prevGrenade();
      break;
    case 'next_grenade':
      overlayState.nextGrenade();
      break;
    case 'prev_step':
      overlayState.prevStep();
      break;
    case 'next_step':
      overlayState.nextStep();
      break;
    case 'toggle_smoke':
      overlayState.toggleFilter(GrenadeType.smoke);
      break;
    case 'toggle_flash':
      overlayState.toggleFilter(GrenadeType.flash);
      break;
    case 'toggle_molotov':
      overlayState.toggleFilter(GrenadeType.molotov);
      break;
    case 'toggle_he':
      overlayState.toggleFilter(GrenadeType.he);
      break;
    case 'toggle_wallbang':
      overlayState.toggleFilter(GrenadeType.wallbang);
      break;
    case 'navigate_up':
      if (!blocksDirectionalNavigation()) {
        overlayState.navigateDirection(NavigationDirection.up);
      }
      break;
    case 'navigate_down':
      if (!blocksDirectionalNavigation()) {
        overlayState.navigateDirection(NavigationDirection.down);
      }
      break;
    case 'navigate_left':
      if (!blocksDirectionalNavigation()) {
        overlayState.navigateDirection(NavigationDirection.left);
      }
      break;
    case 'navigate_right':
      if (!blocksDirectionalNavigation()) {
        overlayState.navigateDirection(NavigationDirection.right);
      }
      break;
    case 'start_navigation':
      final dir = _parseDirection(cmdArgs?['direction'] as String?);
      if (blocksDirectionalNavigation()) {
        overlayState.stopAllNavigation();
      } else if (dir != null) {
        overlayState.startNavigation(dir);
      }
      break;
    case 'stop_navigation':
      final dir = _parseDirection(cmdArgs?['direction'] as String?);
      if (dir != null) overlayState.stopNavigation(dir);
      break;
    case 'stop_all_navigation':
      overlayState.stopAllNavigation();
      break;
    case 'toggle_play_pause':
      overlayState.triggerVideoTogglePlayPause();
      break;
    case 'toggle_media_fullscreen_preview':
      await overlayAppKey.currentState?.overlayWindowKey.currentState
          ?.toggleMediaFullscreenPreview();
      break;
    case 'update_opacity':
      final opacity = (cmdArgs?['opacity'] as num?)?.toDouble() ?? 0.9;
      overlayState.setOpacity(opacity);
      break;
    case 'update_nav_speed':
      final speed = (cmdArgs?['speed'] as num?)?.round() ?? 3;
      overlayState.setNavSpeedLevel(speed);
      break;
    case 'update_size':
      final sizeIndex = (cmdArgs?['sizeIndex'] as num?)?.toInt() ?? 1;
      await overlayState.setOverlaySize(sizeIndex);
      break;
    case 'increase_nav_speed':
      overlayState.increaseNavSpeed();
      client.sendEvent('nav_speed_changed', {
        'speed': overlayState.navSpeedLevel,
      });
      break;
    case 'decrease_nav_speed':
      overlayState.decreaseNavSpeed();
      client.sendEvent('nav_speed_changed', {
        'speed': overlayState.navSpeedLevel,
      });
      break;
    case 'scroll_up':
      overlayAppKey.currentState?.overlayWindowKey.currentState
          ?.scrollContent(-300);
      break;
    case 'scroll_down':
      overlayAppKey.currentState?.overlayWindowKey.currentState
          ?.scrollContent(300);
      break;
    case 'set_legacy_icons':
      GrenadeTypeIcon.useLegacy = cmdArgs?['value'] == true;
      overlayState.refresh();
      break;
    case 'reload_hotkeys':
      final rawHotkeys = cmdArgs?['hotkeys'];
      if (rawHotkeys is Map) {
        final hotkeys = OverlayInitConfig.decodeHotkeys(rawHotkeys);
        overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.reloadHotkeys(hotkeys);
      }
      break;
    case 'release_media':
      final requestId = (cmdArgs?['requestId'] as num?)?.toInt();
      final rawPaths = (cmdArgs?['paths'] as List?) ?? const [];
      final paths = rawPaths.whereType<String>().toList(growable: false);
      await MediaHandleService.releaseLocalPaths(paths);
      if (requestId != null) {
        client.sendEvent('media_released', {'requestId': requestId});
      }
      break;
  }
}

// 悬浮窗独立窗口宿主组件
class OverlayWindowApp extends StatefulWidget {
  final Map<HotkeyAction, HotkeyConfig> initialHotkeys;
  final OverlayStateService overlayState;
  final ValueListenable<bool> isVisibleListenable;
  final AsyncCallback onClose;
  final AsyncCallback onMinimize;

  const OverlayWindowApp({
    super.key,
    required this.initialHotkeys,
    required this.overlayState,
    required this.isVisibleListenable,
    required this.onClose,
    required this.onMinimize,
  });

  @override
  State<OverlayWindowApp> createState() => OverlayWindowAppState();
}

class OverlayWindowAppState extends State<OverlayWindowApp> {
  final GlobalKey<OverlayWindowState> overlayWindowKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ValueListenableBuilder<bool>(
        valueListenable: widget.isVisibleListenable,
        builder: (context, isVisible, _) {
          return OverlayWindow(
            key: overlayWindowKey,
            initialHotkeys: widget.initialHotkeys,
            overlayState: widget.overlayState,
            isVisible: isVisible,
            onClose: widget.onClose,
            onMinimize: widget.onMinimize,
            onStartDrag: () async {
              await windowManager.startDragging();
            },
          );
        },
      ),
    );
  }
}
