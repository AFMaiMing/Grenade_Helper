import 'package:flutter/foundation.dart';

/// 云端道具包模型
@immutable
class CloudPackage {
  final String id;
  final String name;
  final String description;
  final String author;

  /// 适用地图标识，null 表示全图通用
  final String? map;
  final String version;
  final String updated;
  final String url;

  /// 可选的 CDN 加速下载地址
  final String? cdnUrl;

  const CloudPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    this.map,
    required this.version,
    required this.updated,
    required this.url,
    this.cdnUrl,
  });

  factory CloudPackage.fromJson(Map<String, dynamic> json) {
    return CloudPackage(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '未知',
      map: json['map'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      updated: json['updated'] as String? ?? '',
      url: json['url'] as String,
      cdnUrl: json['cdnUrl'] as String?,
    );
  }

  /// 启用加速且存在有效 CDN 链接时优先返回加速地址
  String getDownloadUrl(bool useCDN) {
    final candidate = cdnUrl;
    if (useCDN && candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
    return url;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'author': author,
        'map': map,
        'version': version,
        'updated': updated,
        'url': url,
        if (cdnUrl != null) 'cdnUrl': cdnUrl,
      };
}

/// 云端仓库索引模型
@immutable
class CloudPackageIndex {
  final int version;
  final String? updated;

  /// 贡献者索引 JSON 文件路径列表
  final List<String> sources;
  final List<CloudPackage> packages;

  const CloudPackageIndex({
    required this.version,
    this.updated,
    this.sources = const [],
    required this.packages,
  });

  factory CloudPackageIndex.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] as List<dynamic>?;
    final rawPackages = json['packages'] as List<dynamic>?;
    return CloudPackageIndex(
      version: json['version'] as int? ?? 1,
      updated: json['updated'] as String?,
      sources: rawSources == null
          ? const <String>[]
          : List<String>.unmodifiable(rawSources.map((e) => e as String)),
      packages: rawPackages == null
          ? const <CloudPackage>[]
          : List<CloudPackage>.unmodifiable(
              rawPackages.map(
                (e) =>
                    CloudPackage.fromJson(Map<String, dynamic>.from(e as Map)),
              ),
            ),
    );
  }
}
