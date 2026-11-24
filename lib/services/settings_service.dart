import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import 'settings/desktop_settings_storage.dart';
import 'settings/hotkey_models.dart';

export 'settings/hotkey_models.dart'
    show HotkeyConfig, HotkeyAction, HotkeyConflictException;

class SettingsService {
  static const String _keyHotkeys = 'desktop_hotkeys';
  static const String _keyOverlayOpacity = 'overlay_opacity';
  static const String _keyOverlaySize = 'overlay_size';
  static const String _keyCloseToTray = 'close_to_tray';
  static const String _keyOverlayX = 'overlay_x';
  static const String _keyOverlayY = 'overlay_y';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyMarkerMoveMode = 'marker_move_mode';
  static const String _keyGrenadeCreateMode = 'grenade_create_mode';
  static const String _keyShowMapGrenadeList = 'show_map_grenade_list';
  static const String _keyHighDensityClusterMode = 'high_density_cluster_mode';
  static const String _keyMapMarkerUseEmoji = 'map_marker_use_emoji';
  static const String _keyJoystickOpacity = 'joystick_opacity';
  static const String _keyJoystickSpeed = 'joystick_speed';
  static const String _keyOverlayNavSpeed = 'overlay_nav_speed';
  static const String _keyDataPath = 'custom_data_path';
  static const String _keyLaunchCount = 'app_launch_count';
  static const String _keyDonationDialogShown = 'donation_dialog_shown';
  static const String _keyMapLineColor = 'map_line_color';
  static const String _keyMapLineOpacity = 'map_line_opacity';
  static const String _keyImpactAreaOpacity = 'impact_area_opacity';

  SharedPreferences? _prefs;
  Map<String, dynamic> _cache = {};
  File? _settingsFile;

  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> init() async {
    if (isDesktop) {
      final dataPath = await getDataPathBeforeInit();
      final dataDir = Directory(dataPath);
      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }
      _settingsFile = File(path.join(dataPath, 'settings.json'));
      await DesktopSettingsStorage.migrateLegacySettingsFileToDataDir(
        _settingsFile,
      );
      _cache = await DesktopSettingsStorage.loadSettingsFile(_settingsFile!);
      _cache[_keyDataPath] =
          await DesktopSettingsStorage.readCustomDataPathFromConfigFile();
      await DesktopSettingsStorage.migrateFromSharedPreferences(
        cache: _cache,
        settingsFile: _settingsFile,
        readers: {
          _keyHotkeys: (p) => p.getString(_keyHotkeys),
          _keyOverlayOpacity: (p) => p.getDouble(_keyOverlayOpacity),
          _keyOverlaySize: (p) => p.getInt(_keyOverlaySize),
          _keyCloseToTray: (p) => p.getBool(_keyCloseToTray),
          _keyOverlayX: (p) => p.getDouble(_keyOverlayX),
          _keyOverlayY: (p) => p.getDouble(_keyOverlayY),
          _keyThemeMode: (p) => p.getInt(_keyThemeMode),
          _keyOverlayNavSpeed: (p) => p.getInt(_keyOverlayNavSpeed),
          _keyLaunchCount: (p) => p.getInt(_keyLaunchCount),
          _keyDonationDialogShown: (p) => p.getBool(_keyDonationDialogShown),
          _keyMapLineColor: (p) => p.getInt(_keyMapLineColor),
          _keyMapLineOpacity: (p) => p.getDouble(_keyMapLineOpacity),
          _keyImpactAreaOpacity: (p) => p.getDouble(_keyImpactAreaOpacity),
          _keyHighDensityClusterMode: (p) =>
              p.getBool(_keyHighDensityClusterMode),
        },
      );
    } else {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  Future<void> _saveEntries(Map<String, dynamic> updates) async {
    final file = _settingsFile;
    if (file == null) return;
    final saved =
        await DesktopSettingsStorage.saveSettingsEntries(file, updates);
    if (saved != null) {
      _cache = saved;
    }
  }

  Future<void> _saveValue(String key, dynamic value) =>
      _saveEntries({key: value});

  int _getInt(String key, int defaultValue) {
    if (isDesktop) {
      return (_cache[key] as num?)?.toInt() ?? defaultValue;
    }
    return _prefs?.getInt(key) ?? defaultValue;
  }

  Future<void> _setInt(String key, int value) async {
    if (isDesktop) {
      _cache[key] = value;
      await _saveValue(key, value);
    } else {
      await _prefs?.setInt(key, value);
    }
  }

  double _getDouble(String key, double defaultValue) {
    if (isDesktop) {
      return (_cache[key] as num?)?.toDouble() ?? defaultValue;
    }
    return _prefs?.getDouble(key) ?? defaultValue;
  }

  double? _getNullableDouble(String key) {
    if (isDesktop) {
      return (_cache[key] as num?)?.toDouble();
    }
    return _prefs?.getDouble(key);
  }

  Future<void> _setDouble(String key, double value) async {
    if (isDesktop) {
      _cache[key] = value;
      await _saveValue(key, value);
    } else {
      await _prefs?.setDouble(key, value);
    }
  }

  bool _getBool(String key, bool defaultValue) {
    if (isDesktop) {
      return _cache[key] as bool? ?? defaultValue;
    }
    return _prefs?.getBool(key) ?? defaultValue;
  }

  Future<void> _setBool(String key, bool value) async {
    if (isDesktop) {
      _cache[key] = value;
      await _saveValue(key, value);
    } else {
      await _prefs?.setBool(key, value);
    }
  }

  Future<void> reload() async {
    if (isDesktop) {
      if (_settingsFile != null) {
        _cache = await DesktopSettingsStorage.loadSettingsFile(_settingsFile!);
      }
    } else {
      await _prefs?.reload();
    }
  }

  Map<HotkeyAction, HotkeyConfig> getHotkeys() {
    final defaults = defaultHotkeyBindings();
    final stored = isDesktop
        ? _cache[_keyHotkeys] as String?
        : _prefs?.getString(_keyHotkeys);
    if (stored == null) return defaults;

    try {
      final Map<String, dynamic> json = jsonDecode(stored);
      final result = <HotkeyAction, HotkeyConfig>{};
      for (final action in HotkeyAction.values) {
        final actionKey = action.name;
        result[action] = json.containsKey(actionKey)
            ? HotkeyConfig.fromJson(json[actionKey])
            : defaults[action]!;
      }
      return result;
    } catch (_) {
      return defaults;
    }
  }

  Future<void> saveHotkey(HotkeyAction action, HotkeyConfig config) async {
    final hotkeys = getHotkeys();
    for (final entry in hotkeys.entries) {
      if (entry.key == action) continue;
      if (entry.value.conflictsWith(config)) {
        throw HotkeyConflictException(
          action: action,
          conflictingAction: entry.key,
          config: config,
        );
      }
    }

    hotkeys[action] = config;
    final json = <String, dynamic>{
      for (final entry in hotkeys.entries) entry.key.name: entry.value.toJson(),
    };
    final encoded = jsonEncode(json);

    if (isDesktop) {
      _cache[_keyHotkeys] = encoded;
      await _saveValue(_keyHotkeys, encoded);
    } else {
      await _prefs?.setString(_keyHotkeys, encoded);
    }
  }

  Future<void> resetHotkeys() async {
    if (isDesktop) {
      await _saveValue(_keyHotkeys, null);
      _cache.remove(_keyHotkeys);
    } else {
      await _prefs?.remove(_keyHotkeys);
    }
  }

  double getOverlayOpacity() => _getDouble(_keyOverlayOpacity, 0.9);
  Future<void> setOverlayOpacity(double value) =>
      _setDouble(_keyOverlayOpacity, value);

  int getOverlaySize() => _getInt(_keyOverlaySize, 1);
  Future<void> setOverlaySize(int value) => _setInt(_keyOverlaySize, value);

  bool getCloseToTray() => _getBool(_keyCloseToTray, true);
  Future<void> setCloseToTray(bool value) => _setBool(_keyCloseToTray, value);

  double? getOverlayX() => _getNullableDouble(_keyOverlayX);
  double? getOverlayY() => _getNullableDouble(_keyOverlayY);

  Future<void> setOverlayPosition(double x, double y) async {
    if (isDesktop) {
      _cache[_keyOverlayX] = x;
      _cache[_keyOverlayY] = y;
      await _saveEntries({_keyOverlayX: x, _keyOverlayY: y});
    } else {
      await _prefs?.setDouble(_keyOverlayX, x);
      await _prefs?.setDouble(_keyOverlayY, y);
    }
  }

  (double width, double height) getOverlaySizePixels() =>
      calculateSizePixels(getOverlaySize());

  static (double width, double height) calculateSizePixels(int sizeIndex) {
    return switch (sizeIndex) {
      0 => (500.0, 800.0),
      2 => (600.0, 950.0),
      _ => (550.0, 850.0),
    };
  }

  int getOverlayNavSpeed() => _getInt(_keyOverlayNavSpeed, 3);
  Future<void> setOverlayNavSpeed(int value) =>
      _setInt(_keyOverlayNavSpeed, value);

  int getThemeMode() => _getInt(_keyThemeMode, 2);
  Future<void> setThemeMode(int value) => _setInt(_keyThemeMode, value);

  int getMarkerMoveMode() => _getInt(_keyMarkerMoveMode, 0);
  Future<void> setMarkerMoveMode(int value) =>
      _setInt(_keyMarkerMoveMode, value);

  int getGrenadeCreateMode() => _getInt(_keyGrenadeCreateMode, 0);
  Future<void> setGrenadeCreateMode(int value) =>
      _setInt(_keyGrenadeCreateMode, value);

  bool getShowMapGrenadeList() => _getBool(_keyShowMapGrenadeList, false);
  Future<void> setShowMapGrenadeList(bool value) =>
      _setBool(_keyShowMapGrenadeList, value);

  bool getHighDensityClusterMode() =>
      _getBool(_keyHighDensityClusterMode, true);
  Future<void> setHighDensityClusterMode(bool value) =>
      _setBool(_keyHighDensityClusterMode, value);

  bool getMapMarkerUseEmoji() => _getBool(_keyMapMarkerUseEmoji, false);
  Future<void> setMapMarkerUseEmoji(bool value) =>
      _setBool(_keyMapMarkerUseEmoji, value);

  double getJoystickOpacity() => _getDouble(_keyJoystickOpacity, 0.8);
  Future<void> setJoystickOpacity(double value) =>
      _setDouble(_keyJoystickOpacity, value);

  int getJoystickSpeed() => _getInt(_keyJoystickSpeed, 3);
  Future<void> setJoystickSpeed(int value) => _setInt(_keyJoystickSpeed, value);

  int getLaunchCount() => _getInt(_keyLaunchCount, 0);

  Future<int> incrementLaunchCount() async {
    final count = getLaunchCount() + 1;
    await _setInt(_keyLaunchCount, count);
    return count;
  }

  bool isDonationDialogShown() => _getBool(_keyDonationDialogShown, false);
  Future<void> setDonationDialogShown() =>
      _setBool(_keyDonationDialogShown, true);

  int getMapLineColor() => _getInt(_keyMapLineColor, 0xFFE040FB);
  Future<void> setMapLineColor(int value) => _setInt(_keyMapLineColor, value);

  double getMapLineOpacity() => _getDouble(_keyMapLineOpacity, 0.6);
  Future<void> setMapLineOpacity(double value) =>
      _setDouble(_keyMapLineOpacity, value);

  double getImpactAreaOpacity() => _getDouble(_keyImpactAreaOpacity, 0.4);
  Future<void> setImpactAreaOpacity(double value) =>
      _setDouble(_keyImpactAreaOpacity, value);

  String? getCustomDataPath() {
    if (isDesktop) {
      return _cache[_keyDataPath] as String?;
    }
    return _prefs?.getString(_keyDataPath);
  }

  Future<void> setCustomDataPath(String? customPath) async {
    debugPrint('[Settings] setCustomDataPath called with: $customPath');
    if (isDesktop) {
      if (customPath == null) {
        _cache.remove(_keyDataPath);
      } else {
        _cache[_keyDataPath] = customPath;
      }
      await DesktopSettingsStorage.writeCustomDataPathToConfigFile(customPath);
    } else {
      if (customPath == null) {
        await _prefs?.remove(_keyDataPath);
      } else {
        await _prefs?.setString(_keyDataPath, customPath);
      }
    }
  }

  static Future<String> getDefaultDataPath() =>
      DesktopSettingsStorage.getDefaultDataPath();

  Future<String> getEffectiveDataPath() async {
    if (isDesktop) {
      final customPath = _cache[_keyDataPath] as String?;
      if (customPath != null && customPath.isNotEmpty) {
        return customPath;
      }
      final configPath =
          await DesktopSettingsStorage.readCustomDataPathFromConfigFile();
      if (configPath != null && configPath.isNotEmpty) {
        _cache[_keyDataPath] = configPath;
        return configPath;
      }
    }
    return getDefaultDataPath();
  }

  static Future<String> getDataPathBeforeInit() =>
      DesktopSettingsStorage.getDataPathBeforeInit();

  static Future<void> copyDirectory(
    Directory source,
    Directory destination,
  ) =>
      DesktopSettingsStorage.copyDirectory(source, destination);

  static Future<void> moveData(String fromPath, String toPath) =>
      DesktopSettingsStorage.moveData(fromPath, toPath);
}
