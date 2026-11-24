import '../../models.dart';
import '../../models/tag.dart';

const int maxImportPackageSizeBytes = 1024 * 1024 * 1024;
const int maxImportPackageFileCount = 1000;
const int maxImportPackageEntrySizeBytes = 300 * 1024 * 1024;
const int maxImportPackageExpandedSizeBytes = 4 * 1024 * 1024 * 1024;
const int maxExportPackageSizeBytes = 1024 * 1024 * 1024;
const int estimatedArchiveBaseOverheadBytes = 2048;
const int estimatedArchiveEntryOverheadBytes = 256;
const String packageManifestFileName = 'manifest.json';
const String packageDataFileName = 'data.json';
const String packageTypeExport = 'export';
const String packageTypeLanSync = 'lan_sync';
const int packageManifestVersion = 1;
const int exportSchemaVersion = 3;
const int lanSyncSchemaVersion = 7;
const String placeholderSha256Hex =
    '0000000000000000000000000000000000000000000000000000000000000000';

enum ImportPackageMode { normal, lanSync }

class PackageManifestFileEntry {
  final String path;
  final String kind;
  final int sizeBytes;
  final String sha256;

  const PackageManifestFileEntry({
    required this.path,
    required this.kind,
    required this.sizeBytes,
    required this.sha256,
  });

  factory PackageManifestFileEntry.fromJson(Map<String, dynamic> json) {
    return PackageManifestFileEntry(
      path: (json['path'] as String? ?? '').trim(),
      kind: (json['kind'] as String? ?? '').trim(),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      sha256: (json['sha256'] as String? ?? '').trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'kind': kind,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
      };
}

class PackageManifestData {
  final int manifestVersion;
  final int schemaVersion;
  final String packageType;
  final int createdAt;
  final List<PackageManifestFileEntry> files;
  final String contentHmac;

  const PackageManifestData({
    required this.manifestVersion,
    required this.schemaVersion,
    required this.packageType,
    required this.createdAt,
    required this.files,
    required this.contentHmac,
  });

  factory PackageManifestData.fromJson(Map<String, dynamic> json) {
    final filesRaw = json['files'];
    final files = <PackageManifestFileEntry>[];
    if (filesRaw is List) {
      for (final raw in filesRaw) {
        if (raw is! Map<String, dynamic>) continue;
        files.add(PackageManifestFileEntry.fromJson(raw));
      }
    }
    return PackageManifestData(
      manifestVersion: json['manifestVersion'] as int? ?? 0,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      packageType: (json['packageType'] as String? ?? '').trim(),
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      files: files,
      contentHmac: (json['contentHmac'] as String? ?? '').trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'manifestVersion': manifestVersion,
        'schemaVersion': schemaVersion,
        'packageType': packageType,
        'createdAt': createdAt,
        'files': files.map((entry) => entry.toJson()).toList(growable: false),
        'contentHmac': contentHmac,
      };

  bool get isValid =>
      manifestVersion == packageManifestVersion &&
      schemaVersion > 0 &&
      (packageType == packageTypeExport || packageType == packageTypeLanSync) &&
      files.isNotEmpty &&
      contentHmac.isNotEmpty;
}

class ExportPackageEstimate {
  final int grenadeCount;
  final int mediaFileCount;
  final int mediaBytes;
  final int dataJsonBytes;
  final int manifestJsonBytes;
  final int estimatedPackageBytes;
  final int limitBytes;

  const ExportPackageEstimate({
    required this.grenadeCount,
    required this.mediaFileCount,
    required this.mediaBytes,
    required this.dataJsonBytes,
    required this.manifestJsonBytes,
    required this.estimatedPackageBytes,
    this.limitBytes = maxExportPackageSizeBytes,
  });

  bool get exceedsLimit => estimatedPackageBytes > limitBytes;
}

enum ImportStatus { newItem, update, skip }

class GrenadePreviewItem {
  final Map<String, dynamic> rawData;
  final String uniqueId;
  final String title;
  final int type;
  final String mapName;
  final String layerName;
  final String? author;
  final ImportStatus status;
  final DateTime updatedAt;

  GrenadePreviewItem({
    required this.rawData,
    required this.uniqueId,
    required this.title,
    required this.type,
    required this.mapName,
    required this.layerName,
    this.author,
    required this.status,
    required this.updatedAt,
  });
}

class PackagePreviewResult {
  final Map<String, List<GrenadePreviewItem>> grenadesByMap;
  final String filePath;
  final Map<String, List<int>> memoryImages;
  final int schemaVersion;
  final String packageType;
  final bool isTrustedPackage;
  final bool isLegacyPackage;
  final Map<String, String> packageFileHashes;
  final Map<String, int> packageFileSizes;
  final Set<String> availablePackageFiles;
  final Map<String, PackageTagData> tagsByUuid;
  final List<PackageAreaData> areas;
  final List<PackageFavoriteFolderData> favoriteFolders;
  final List<PackageImpactGroupData> impactGroups;
  final List<PackageMapData> maps;
  final List<PackageGrenadeTombstoneData> grenadeTombstones;
  final List<PackageEntityTombstoneData> entityTombstones;
  final int changedTagCount;
  final int changedAreaCount;
  final int changedFavoriteFolderCount;
  final int changedImpactGroupCount;
  final int changedMapCount;

  PackagePreviewResult({
    required this.grenadesByMap,
    required this.filePath,
    required this.memoryImages,
    this.schemaVersion = 1,
    this.packageType = packageTypeExport,
    this.isTrustedPackage = false,
    this.isLegacyPackage = true,
    this.packageFileHashes = const {},
    this.packageFileSizes = const {},
    this.availablePackageFiles = const <String>{},
    this.tagsByUuid = const {},
    this.areas = const [],
    this.favoriteFolders = const [],
    this.impactGroups = const [],
    this.maps = const [],
    this.grenadeTombstones = const [],
    this.entityTombstones = const [],
    this.changedTagCount = 0,
    this.changedAreaCount = 0,
    this.changedFavoriteFolderCount = 0,
    this.changedImpactGroupCount = 0,
    this.changedMapCount = 0,
  });

  bool get isMultiMap => mapNames.length > 1;
  bool get canApplyTombstones =>
      isTrustedPackage && packageType == packageTypeLanSync;

  int get totalCount =>
      grenadesByMap.values.fold(0, (sum, list) => sum + list.length);

  int get metadataChangeCount =>
      changedTagCount +
      changedAreaCount +
      changedFavoriteFolderCount +
      changedImpactGroupCount +
      changedMapCount;

  List<String> get mapNames {
    final ordered = <String>[];
    final seen = <String>{};
    void collectNames(Iterable<String> names) {
      for (final raw in names) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty || !seen.add(trimmed)) continue;
        ordered.add(trimmed);
      }
    }

    collectNames(grenadesByMap.keys);
    collectNames(grenadeTombstones.map((e) => e.mapName));
    collectNames(entityTombstones.map((e) => e.mapName));
    collectNames(tagsByUuid.values.map((e) => e.mapName));
    collectNames(areas.map((e) => e.mapName));
    collectNames(favoriteFolders.map((e) => e.mapName));
    collectNames(impactGroups.map((e) => e.mapName));
    collectNames(maps.map((e) => e.mapName));
    return ordered;
  }
}

class PackageGrenadeTombstoneData {
  final String uniqueId;
  final String mapName;
  final int deletedAt;

  const PackageGrenadeTombstoneData({
    required this.uniqueId,
    required this.mapName,
    required this.deletedAt,
  });

  factory PackageGrenadeTombstoneData.fromJson(Map<String, dynamic> json) {
    return PackageGrenadeTombstoneData(
      uniqueId: (json['uniqueId'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      deletedAt:
          json['deletedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'uniqueId': uniqueId,
        'mapName': mapName,
        'deletedAt': deletedAt,
      };
}

class PackageEntityTombstoneData {
  final String entityType;
  final String entityKey;
  final String mapName;
  final int deletedAt;
  final Map<String, dynamic> payload;

  const PackageEntityTombstoneData({
    required this.entityType,
    required this.entityKey,
    required this.mapName,
    required this.deletedAt,
    this.payload = const {},
  });

  factory PackageEntityTombstoneData.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return PackageEntityTombstoneData(
      entityType: (json['entityType'] as String? ?? '').trim(),
      entityKey: (json['entityKey'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      deletedAt:
          json['deletedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'entityKey': entityKey,
        'mapName': mapName,
        'deletedAt': deletedAt,
        'payload': payload,
      };
}

class PackageTagData {
  final String tagUuid;
  final String mapName;
  final String name;
  final int dimension;
  final int colorValue;
  final String? groupName;
  final bool isSystem;
  final int updatedAt;

  const PackageTagData({
    required this.tagUuid,
    required this.mapName,
    required this.name,
    required this.dimension,
    required this.colorValue,
    this.groupName,
    required this.isSystem,
    required this.updatedAt,
  });

  factory PackageTagData.fromJson(Map<String, dynamic> json) {
    return PackageTagData(
      tagUuid: (json['tagUuid'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      dimension: json['dimension'] as int? ?? TagDimension.custom,
      colorValue: json['colorValue'] as int? ?? 0xFF607D8B,
      groupName: json['groupName'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'tagUuid': tagUuid,
        'mapName': mapName,
        'name': name,
        'dimension': dimension,
        'colorValue': colorValue,
        'groupName': groupName,
        'isSystem': isSystem,
        'updatedAt': updatedAt,
      };
}

class PackageAreaData {
  final String tagUuid;
  final String mapName;
  final String layerName;
  final String name;
  final int colorValue;
  final String strokes;
  final int createdAt;
  final int updatedAt;

  const PackageAreaData({
    required this.tagUuid,
    required this.mapName,
    required this.layerName,
    required this.name,
    required this.colorValue,
    required this.strokes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PackageAreaData.fromJson(Map<String, dynamic> json) {
    return PackageAreaData(
      tagUuid: (json['tagUuid'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      layerName: (json['layerName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      colorValue: json['colorValue'] as int? ?? 0xFF4CAF50,
      strokes: json['strokes'] as String? ?? '[]',
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] as int? ??
          (json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toJson() => {
        'tagUuid': tagUuid,
        'mapName': mapName,
        'layerName': layerName,
        'name': name,
        'colorValue': colorValue,
        'strokes': strokes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class PackageFavoriteFolderData {
  final String mapName;
  final String name;
  final String nameKey;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  const PackageFavoriteFolderData({
    required this.mapName,
    required this.name,
    required this.nameKey,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PackageFavoriteFolderData.fromJson(Map<String, dynamic> json) {
    return PackageFavoriteFolderData(
      mapName: (json['mapName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      nameKey: (json['nameKey'] as String? ?? '').trim(),
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'mapName': mapName,
        'name': name,
        'nameKey': nameKey,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class PackageImpactGroupData {
  final String mapName;
  final String layerName;
  final String name;
  final int type;
  final double impactXRatio;
  final double impactYRatio;
  final int createdAt;
  final int updatedAt;

  const PackageImpactGroupData({
    required this.mapName,
    required this.layerName,
    required this.name,
    required this.type,
    required this.impactXRatio,
    required this.impactYRatio,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PackageImpactGroupData.fromJson(Map<String, dynamic> json) {
    return PackageImpactGroupData(
      mapName: (json['mapName'] as String? ?? '').trim(),
      layerName: (json['layerName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      type: json['type'] as int? ?? GrenadeType.smoke,
      impactXRatio: (json['impactXRatio'] as num?)?.toDouble() ?? 0.0,
      impactYRatio: (json['impactYRatio'] as num?)?.toDouble() ?? 0.0,
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] as int? ??
          (json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toJson() => {
        'mapName': mapName,
        'layerName': layerName,
        'name': name,
        'type': type,
        'impactXRatio': impactXRatio,
        'impactYRatio': impactYRatio,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class PackageMapLayerData {
  final String name;
  final String assetPath;
  final int sortOrder;

  const PackageMapLayerData({
    required this.name,
    required this.assetPath,
    required this.sortOrder,
  });

  factory PackageMapLayerData.fromJson(Map<String, dynamic> json) {
    return PackageMapLayerData(
      name: (json['name'] as String? ?? '').trim(),
      assetPath: (json['assetPath'] as String? ?? '').trim(),
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'assetPath': assetPath,
        'sortOrder': sortOrder,
      };
}

class PackageMapData {
  final String mapName;
  final String backgroundPath;
  final String iconPath;
  final List<PackageMapLayerData> layers;

  const PackageMapData({
    required this.mapName,
    required this.backgroundPath,
    required this.iconPath,
    required this.layers,
  });

  factory PackageMapData.fromJson(Map<String, dynamic> json) {
    final layersRaw = json['layers'];
    final layers = <PackageMapLayerData>[];
    if (layersRaw is List) {
      for (final raw in layersRaw) {
        if (raw is! Map) continue;
        final layer = PackageMapLayerData.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (layer.name.isEmpty) continue;
        layers.add(layer);
      }
    }
    return PackageMapData(
      mapName: (json['mapName'] as String? ?? '').trim(),
      backgroundPath: (json['backgroundPath'] as String? ?? '').trim(),
      iconPath: (json['iconPath'] as String? ?? '').trim(),
      layers: layers,
    );
  }

  Map<String, dynamic> toJson() => {
        'mapName': mapName,
        'backgroundPath': backgroundPath,
        'iconPath': iconPath,
        'layers': layers.map((item) => item.toJson()).toList(growable: false),
      };
}

// 内部打包参数传输类，仅在 data 子模块内部使用
class PackageParams {
  final String exportDirPath;
  final String zipPath;
  final String jsonData;
  final List<String> filesToCopy;
  final int schemaVersion;
  final String packageType;

  PackageParams({
    required this.exportDirPath,
    required this.zipPath,
    required this.jsonData,
    required this.filesToCopy,
    required this.schemaVersion,
    required this.packageType,
  });
}

class ExportBundle {
  final List<Map<String, dynamic>> grenades;
  final List<Map<String, dynamic>> tags;
  final List<Map<String, dynamic>> areas;
  final List<Map<String, dynamic>> maps;
  final List<Map<String, dynamic>> favoriteFolders;
  final List<Map<String, dynamic>> impactGroups;
  final Set<String> filesToZip;

  const ExportBundle({
    required this.grenades,
    required this.tags,
    required this.areas,
    required this.maps,
    required this.favoriteFolders,
    required this.impactGroups,
    required this.filesToZip,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': exportSchemaVersion,
        'grenades': grenades,
        'tags': tags,
        'areas': areas,
        'maps': maps,
        'favoriteFolders': favoriteFolders,
        'impactGroups': impactGroups,
      };
}

class PackageFavoriteFolderRef {
  final String mapName;
  final String nameKey;

  const PackageFavoriteFolderRef({
    required this.mapName,
    required this.nameKey,
  });
}

class PackageImpactGroupRef {
  final String mapName;
  final String layerName;
  final String name;
  final int type;
  final double impactXRatio;
  final double impactYRatio;

  const PackageImpactGroupRef({
    required this.mapName,
    required this.layerName,
    required this.name,
    required this.type,
    required this.impactXRatio,
    required this.impactYRatio,
  });
}

class LanSyncExportBundle {
  final List<Map<String, dynamic>> grenades;
  final List<Map<String, dynamic>> tags;
  final List<Map<String, dynamic>> areas;
  final List<Map<String, dynamic>> maps;
  final List<Map<String, dynamic>> favoriteFolders;
  final List<Map<String, dynamic>> impactGroups;
  final List<Map<String, dynamic>> grenadeTombstones;
  final List<Map<String, dynamic>> entityTombstones;
  final Set<String> filesToZip;

  const LanSyncExportBundle({
    required this.grenades,
    required this.tags,
    required this.areas,
    required this.maps,
    required this.favoriteFolders,
    required this.impactGroups,
    required this.grenadeTombstones,
    required this.entityTombstones,
    required this.filesToZip,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': lanSyncSchemaVersion,
        'grenades': grenades,
        'tags': tags,
        'areas': areas,
        'maps': maps,
        'favoriteFolders': favoriteFolders,
        'impactGroups': impactGroups,
        'grenadeTombstones': grenadeTombstones,
        'entityTombstones': entityTombstones,
      };
}

class MetadataPreviewCounts {
  final int tags;
  final int areas;
  final int favoriteFolders;
  final int impactGroups;
  final int maps;

  const MetadataPreviewCounts({
    this.tags = 0,
    this.areas = 0,
    this.favoriteFolders = 0,
    this.impactGroups = 0,
    this.maps = 0,
  });
}

class LocalTagContext {
  final Map<String, GameMap> mapByName;
  final Map<String, Tag> localByUuid;
  final Map<String, Tag> localBySemantic;

  const LocalTagContext({
    required this.mapByName,
    required this.localByUuid,
    required this.localBySemantic,
  });
}
