import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_package.dart';

/// 云端道具包下载与索引服务
class CloudPackageService {
  static const int _maxRemotePackageSizeBytes = 1024 * 1024 * 1024;
  static const String kGitHubIndexUrl =
      'https://raw.githubusercontent.com/Invis1ble-2/grenades_repo/main/';
  static const String kCDNIndexUrl =
      'https://ghproxy.grenade-helper.top/https://raw.githubusercontent.com/Invis1ble-2/grenades_repo/main/';
  static const String _lastImportedKey = 'cloud_package_last_imported';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  static String kIndexBaseUrl = kGitHubIndexUrl;
  static bool _useCDN = false;
  static final Map<String, http.Client> _activeClients = {};

  static bool get isUsingCDN => _useCDN;

  static Future<CloudPackageIndex?> fetchIndex() async {
    try {
      final response = await http
          .get(Uri.parse('${kIndexBaseUrl}index.json'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return CloudPackageIndex.fromJson(json);
      }
    } catch (e) {
      debugPrint('获取索引失败: $e');
    }
    return null;
  }

  static void switchSource(bool useCDN) {
    _useCDN = useCDN;
    kIndexBaseUrl = useCDN ? kCDNIndexUrl : kGitHubIndexUrl;
  }

  static void cancelDownload(String url) {
    _activeClients.remove(url)?.close();
  }

  static Future<String?> downloadPackage(
    String url, {
    void Function(int received, int total)? onProgress,
  }) {
    return _downloadFromUrl(url, onProgress: onProgress);
  }

  static Future<String?> downloadFromUrl(String url) => _downloadFromUrl(url);

  static Future<String?> _downloadFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    http.Client? client;
    try {
      debugPrint('正在下载: $url');
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = _userAgent;

      client = http.Client();
      _activeClients[url] = client;

      final response =
          await client.send(request).timeout(const Duration(seconds: 10));
      debugPrint('响应状态码: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('下载失败，状态码: ${response.statusCode}');
        return null;
      }

      final contentLength = response.contentLength ?? 0;
      if (contentLength > _maxRemotePackageSizeBytes) {
        debugPrint('下载失败，文件超过上限');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final tailName = url.split('/').last;
      final fileName = tailName.isNotEmpty ? tailName : 'package.cs2pkg';
      final file = File('${tempDir.path}/$fileName');
      final sink = file.openWrite();
      var received = 0;

      await for (final chunk in response.stream) {
        if (received + chunk.length > _maxRemotePackageSizeBytes) {
          await sink.close();
          try {
            await file.delete();
          } catch (_) {}
          debugPrint('下载失败，文件超过上限');
          return null;
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, contentLength);
      }

      await sink.close();
      return file.path;
    } catch (e) {
      debugPrint('下载失败 ($url): $e');
      return null;
    } finally {
      _activeClients.remove(url);
      client?.close();
    }
  }

  static Future<bool> isPackageUpToDate(
    String packageId,
    String version,
  ) async {
    final lastImportedVersion = await getLastImportedVersion(packageId);
    if (lastImportedVersion == null) return false;
    return compareVersion(lastImportedVersion, version) >= 0;
  }

  static int compareVersion(String v1, String v2) {
    final parts1 =
        v1.split('.').map((e) => int.tryParse(e) ?? 0).toList(growable: false);
    final parts2 =
        v2.split('.').map((e) => int.tryParse(e) ?? 0).toList(growable: false);
    final maxLen =
        parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1 > p2 ? 1 : -1;
    }
    return 0;
  }

  static Future<void> markPackageImported(
    String packageId,
    String version,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_lastImportedKey:$packageId', version);
  }

  static Future<String?> getLastImportedVersion(String packageId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_lastImportedKey:$packageId');
  }

  static List<CloudPackage> filterByMap(
    List<CloudPackage> packages,
    String? mapFilter,
  ) {
    if (mapFilter == null || mapFilter == 'all') return packages;
    return packages.where((p) => p.map == null || p.map == mapFilter).toList();
  }

  static List<String> getAvailableMaps(List<CloudPackage> packages) {
    final maps = <String>{
      for (final p in packages)
        if (p.map != null && p.map!.isNotEmpty) p.map!,
    };
    return maps.toList()..sort();
  }
}
