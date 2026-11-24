import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopSettingsStorage {
  static const String _customPathFileName = 'custom_data_path.txt';
  static const String _settingsFileName = 'settings.json';
  static const Set<String> _ignoredMigrationEntries = {
    'flutter_assets',
    'icudtl.dat',
    'default.isar-lck',
  };

  static const JsonEncoder _prettyJsonEncoder = JsonEncoder.withIndent('  ');

  static Future<Map<String, dynamic>> loadSettingsFile(File file) async {
    try {
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          debugPrint('[Settings] Loaded ${decoded.length} settings from file');
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('[Settings] Error loading settings from file: $e');
    }
    return {};
  }

  /// 读文件最新内容并合并写入，避免并发保存相互覆盖。
  static Future<Map<String, dynamic>?> saveSettingsEntries(
    File file,
    Map<String, dynamic> updates,
  ) async {
    try {
      Map<String, dynamic> fileData = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          try {
            fileData = jsonDecode(content) as Map<String, dynamic>;
          } catch (_) {}
        }
      }

      for (final entry in updates.entries) {
        fileData[entry.key] = entry.value;
      }

      await file.writeAsString(
        _prettyJsonEncoder.convert(fileData),
        flush: true,
      );
      return fileData;
    } catch (e) {
      debugPrint('[Settings] Error saving values to file: $e');
      return null;
    }
  }

  static Future<void> migrateFromSharedPreferences({
    required Map<String, dynamic> cache,
    required File? settingsFile,
    required Map<String, dynamic Function(SharedPreferences)> readers,
  }) async {
    if (cache.isNotEmpty || settingsFile == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      var migrated = false;
      for (final entry in readers.entries) {
        if (prefs.containsKey(entry.key)) {
          cache[entry.key] = entry.value(prefs);
          migrated = true;
        }
      }

      if (migrated) {
        await saveSettingsEntries(settingsFile, cache);
        debugPrint(
            '[Settings] Migrated settings from SharedPreferences to file');
      }
    } catch (e) {
      debugPrint('[Settings] Error migrating from SharedPreferences: $e');
    }
  }

  static Future<String> getDefaultDataPath() async {
    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, 'data');
  }

  static Future<String?> readCustomDataPathFromConfigFile() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final configFile = File(path.join(appSupport.path, _customPathFileName));
      if (!await configFile.exists()) return null;
      final customPath = (await configFile.readAsString()).trim();
      return customPath.isEmpty ? null : customPath;
    } catch (e) {
      debugPrint('[Settings] Error reading custom_data_path.txt: $e');
      return null;
    }
  }

  static Future<void> writeCustomDataPathToConfigFile(
      String? customPath) async {
    // 桌面端启动前通过该独立文件定位数据目录。
    try {
      final appSupport = await getApplicationSupportDirectory();
      final configFile = File(path.join(appSupport.path, _customPathFileName));
      if (customPath == null) {
        if (await configFile.exists()) {
          await configFile.delete();
        }
      } else {
        await configFile.writeAsString(customPath, flush: true);
      }
    } catch (e) {
      debugPrint('[Settings] Error updating legacy config file: $e');
    }
  }

  static Future<String> getDataPathBeforeInit() async {
    final customPath = await readCustomDataPathFromConfigFile();
    debugPrint('[Settings] getDataPathBeforeInit - customPath: $customPath');
    if (customPath != null && customPath.isNotEmpty) {
      return customPath;
    }

    final targetDir = await getDefaultDataPath();
    // 仅在新目录尚无数据时迁移旧版 exe 同级 data 目录。
    try {
      final newDir = Directory(targetDir);
      if (!newDir.existsSync() ||
          (newDir.listSync().isEmpty &&
              !File(path.join(targetDir, 'lock')).existsSync())) {
        final appRoot = Directory(Platform.resolvedExecutable).parent.path;
        final oldPath = path.join(appRoot, 'data');
        final legacyDbFile = File(path.join(oldPath, 'default.isar'));
        if (legacyDbFile.existsSync()) {
          debugPrint(
              '[Settings] Detecting legacy data at: $oldPath, migrating...');
          await moveData(oldPath, targetDir);
          debugPrint('[Settings] Legacy data migration completed.');
        }
      }
    } catch (e) {
      debugPrint('[Settings] Error checking legacy migration: $e');
    }
    return targetDir;
  }

  static Future<void> migrateLegacySettingsFileToDataDir(
    File? settingsFile,
  ) async {
    if (settingsFile == null) return;
    try {
      if (await settingsFile.exists()) return;
      final appSupport = await getApplicationSupportDirectory();
      final legacyFile = File(path.join(appSupport.path, _settingsFileName));
      if (!await legacyFile.exists()) return;
      if (path.equals(legacyFile.path, settingsFile.path)) return;
      await legacyFile.copy(settingsFile.path);
      debugPrint('[Settings] Migrated legacy settings.json to data directory');
    } catch (e) {
      debugPrint('[Settings] Error migrating legacy settings.json: $e');
    }
  }

  static Future<void> copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (!destination.existsSync()) {
      await destination.create(recursive: true);
    }

    await for (final entity in source.list(recursive: false)) {
      final baseName = path.basename(entity.path);
      if (_ignoredMigrationEntries.contains(baseName.toLowerCase())) {
        continue;
      }
      final targetPath = path.join(destination.absolute.path, baseName);
      if (entity is Directory) {
        await copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  static Future<void> moveData(String fromPath, String toPath) async {
    if (fromPath == toPath) return;

    final sourceDir = Directory(fromPath);
    if (!sourceDir.existsSync()) return;

    final targetDir = Directory(toPath);
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }

    debugPrint('[Settings] Copying data from $fromPath to $toPath');
    await copyDirectory(sourceDir, targetDir);
  }
}
