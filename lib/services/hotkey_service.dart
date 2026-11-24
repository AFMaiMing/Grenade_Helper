import 'package:flutter/foundation.dart';

import 'settings_service.dart';
import 'windows_navigation_polling_service.dart';

// 协调桌面端全局热键回调注册与悬浮窗热键启停
class HotkeyService {
  final SettingsService _settings;
  final Map<HotkeyAction, void Function()> _handlers = {};
  final Map<HotkeyAction, void Function()> _keyUpHandlers = {};
  WindowsHotkeyPollingService? _windowsHotkeyPollingService;
  bool _overlayHotkeysRegistered = false;

  HotkeyService(this._settings);

  Future<void> init() async {
    if (!SettingsService.isDesktop) return;

    _windowsHotkeyPollingService ??= WindowsHotkeyPollingService(
      _settings,
      onKeyDown: _dispatchKeyDown,
      onKeyUp: _dispatchKeyUp,
    );
    await _windowsHotkeyPollingService!.init();
  }

  void registerHandler(HotkeyAction action, void Function() handler) {
    _handlers[action] = handler;
  }

  void registerKeyUpHandler(HotkeyAction action, void Function() handler) {
    _keyUpHandlers[action] = handler;
  }

  void unregisterHandler(HotkeyAction action) {
    _handlers.remove(action);
    _keyUpHandlers.remove(action);
  }

  Future<void> registerOverlayHotkeys() async {
    if (_overlayHotkeysRegistered) return;
    await _windowsHotkeyPollingService?.setOverlayHotkeysEnabled(true);
    _overlayHotkeysRegistered = true;
  }

  Future<void> unregisterOverlayHotkeys() async {
    if (!_overlayHotkeysRegistered) return;
    await _windowsHotkeyPollingService?.setOverlayHotkeysEnabled(false);
    _overlayHotkeysRegistered = false;
  }

  Future<void> reloadFromSettings() async {
    await _windowsHotkeyPollingService?.reloadBindings();
    debugPrint('[HotkeyService] Hotkeys reloaded from settings');
  }

  Future<void> updateHotkey(HotkeyAction action, HotkeyConfig config) async {
    await _settings.saveHotkey(action, config);
    await _windowsHotkeyPollingService?.reloadBindings();
  }

  Future<void> dispose() async {
    await _windowsHotkeyPollingService?.dispose();
    _handlers.clear();
    _keyUpHandlers.clear();
    _overlayHotkeysRegistered = false;
  }

  void _dispatchKeyDown(HotkeyAction action) {
    _handlers[action]?.call();
  }

  void _dispatchKeyUp(HotkeyAction action) {
    _keyUpHandlers[action]?.call();
  }
}
