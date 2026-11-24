// ignore_for_file: unnecessary_getters_setters

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'hotkey_service.dart';
import 'settings_service.dart';

// 管理系统主窗口、系统托盘与悬浮窗显隐生命周期
class WindowService with TrayListener, WindowListener {
  final SettingsService _settings;
  HotkeyService? _hotkeyService;

  bool _isOverlayVisible = false;
  bool _isMainWindowVisible = true;

  void Function()? onShowMainWindow;
  void Function()? onShowOverlay;
  void Function()? onHideOverlay;
  Future<void> Function()? onExitApp;
  Future<void> Function()? onCloseDatabase;

  WindowService(this._settings);

  void setHotkeyService(HotkeyService service) {
    _hotkeyService = service;
  }

  bool get isOverlayVisible => _isOverlayVisible;
  set isOverlayVisible(bool value) => _isOverlayVisible = value;
  bool get isMainWindowVisible => _isMainWindowVisible;

  Future<void> init() async {
    if (!SettingsService.isDesktop) return;

    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // 拦截窗口关闭以支持最小化到托盘
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await _initTray();
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    try {
      await trayManager.setIcon('assets/icons/app_icon.ico');
      await trayManager.setToolTip('Grenade Helper');
      await _updateTrayMenu();
    } catch (e) {
      debugPrint('Failed to initialize tray: $e');
    }
  }

  Future<void> _updateTrayMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show_main', label: '显示主窗口'),
        MenuItem(
          key: 'show_overlay',
          label: _isOverlayVisible ? '隐藏悬浮窗' : '显示悬浮窗',
        ),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出程序'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_main':
        showMainWindow();
      case 'show_overlay':
        if (_isOverlayVisible) {
          hideOverlay();
        } else {
          showOverlay();
        }
      case 'exit':
        forceExitApp();
    }
  }

  @override
  void onTrayIconMouseDown() {
    showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onWindowClose() async {
    if (_settings.getCloseToTray()) {
      await windowManager.hide();
      _isMainWindowVisible = false;
    } else {
      await forceExitApp();
    }
  }

  Future<void> showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
    _isMainWindowVisible = true;
    onShowMainWindow?.call();
  }

  Future<void> hideMainWindow() async {
    await windowManager.hide();
    _isMainWindowVisible = false;
  }

  Future<void> showOverlay() async {
    _isOverlayVisible = true;
    await _updateTrayMenu();
    await _hotkeyService?.registerOverlayHotkeys();
    onShowOverlay?.call();
  }

  Future<void> hideOverlay() async {
    _isOverlayVisible = false;
    await _updateTrayMenu();
    await _hotkeyService?.unregisterOverlayHotkeys();
    onHideOverlay?.call();
  }

  Future<void> toggleOverlay() async {
    if (_isOverlayVisible) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }

  Future<void> forceExitApp() async {
    await onExitApp?.call();
    _removeListeners();
    await trayManager.destroy();
    try {
      await onCloseDatabase?.call();
      debugPrint('[WindowService] Database closed successfully.');
    } catch (e) {
      debugPrint('[WindowService] Error closing database: $e');
    }
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> dispose() async {
    _removeListeners();
  }

  void _removeListeners() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
