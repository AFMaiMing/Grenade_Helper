import 'package:isar_community/isar.dart';

import '../models.dart';
import '../services/hotkey_service.dart';
import '../services/overlay_ipc_server.dart';
import '../services/settings_service.dart';
import '../services/window_service.dart';

// 全局服务与数据库实例
SettingsService? globalSettingsService;
HotkeyService? globalHotkeyService;
WindowService? globalWindowService;
OverlayIpcServer? globalOverlayServer;
Isar? globalIsar;

void sendOverlayCommand(String command, [Map<String, dynamic>? args]) {
  globalOverlayServer?.sendCommand(command, args);
}

void setOverlayActiveMap(GameMap map, MapLayer layer) {
  globalOverlayServer?.setActiveMap(map, layer);
}

void clearOverlayActiveMap() {
  globalOverlayServer?.clearActiveMap();
}
