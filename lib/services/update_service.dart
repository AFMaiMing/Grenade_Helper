import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 应用版本更新信息
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String content;
  final String downloadUrl;
  final bool forceUpdate;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.content,
    required this.downloadUrl,
    this.forceUpdate = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionCode: json['versionCode'] ?? 0,
      versionName: json['versionName'] ?? '',
      content: json['content'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      forceUpdate: json['forceUpdate'] ?? false,
    );
  }
}

/// 安装包官方与网盘下载地址配置
class DownloadLinks {
  static const Map<String, String> panLinks = {
    '百度网盘': 'https://pan.baidu.com/s/5QyKQdw4AIqxcrHgbiN6gTw',
    '夸克网盘': 'https://pan.quark.cn/s/2907fabc3738',
    '蓝奏云网盘（密码4j0g）': 'https://wwanb.lanzoum.com/b016kfxakh',
  };

  static String getOfficialUrl(String platform) =>
      'https://cdn.grenade-helper.top:8443/download/$platform';
}

/// 应用版本检查更新服务
class UpdateService {
  static const String _baseUrl = 'https://cdn.grenade-helper.top:8443';

  String get currentPlatform {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final platform = currentPlatform;
      if (platform == 'unknown') return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final response = await http
          .get(Uri.parse('$_baseUrl/update/$platform'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final latestInfo = UpdateInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      return _isNewerVersion(latestInfo.versionName, packageInfo.version)
          ? latestInfo
          : null;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  List<int> _parseVersionParts(String version) {
    final parts = version.split('.').map(int.parse).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = _parseVersionParts(latest);
      final currentParts = _parseVersionParts(current);
      for (var i = 0; i < 3; i++) {
        if (latestParts[i] != currentParts[i]) {
          return latestParts[i] > currentParts[i];
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
