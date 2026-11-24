import '../../models/tag.dart';
import '../lan_sync/lan_sync_local_store.dart';
import 'data_package_models.dart';

class LanSyncManifestItem {
  final String key;
  final String mapName;
  final String digest;
  final int updatedAtMs;
  final Map<String, dynamic> rawData;
  final Set<String> filesToZip;

  const LanSyncManifestItem({
    required this.key,
    required this.mapName,
    required this.digest,
    required this.updatedAtMs,
    this.rawData = const {},
    this.filesToZip = const <String>{},
  });

  Map<String, dynamic> toManifestJson() => {
        'digest': digest,
        'updatedAtMs': updatedAtMs,
        'mapName': mapName,
      };
}

class LanSyncManifestBundle {
  final Map<String, LanSyncManifestItem> grenades;
  final Map<String, LanSyncManifestItem> tags;
  final Map<String, LanSyncManifestItem> areas;
  final Map<String, LanSyncManifestItem> maps;
  final Map<String, LanSyncManifestItem> favoriteFolders;
  final Map<String, LanSyncManifestItem> impactGroups;

  const LanSyncManifestBundle({
    this.grenades = const {},
    this.tags = const {},
    this.areas = const {},
    this.maps = const {},
    this.favoriteFolders = const {},
    this.impactGroups = const {},
  });

  Map<String, dynamic> toManifestJson() {
    final grenadesByMap = <String, Map<String, dynamic>>{};
    for (final entry in grenades.entries) {
      grenadesByMap.putIfAbsent(entry.value.mapName, () => <String, dynamic>{});
      grenadesByMap[entry.value.mapName]![entry.key] =
          entry.value.toManifestJson();
    }
    return {
      'manifestSchemaVersion': 1,
      'generatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'grenadesByMap': grenadesByMap,
      'entitiesByType': {
        LanSyncEntityTombstoneType.tag: {
          for (final entry in tags.entries)
            entry.key: entry.value.toManifestJson(),
        },
        LanSyncEntityTombstoneType.area: {
          for (final entry in areas.entries)
            entry.key: entry.value.toManifestJson(),
        },
        'map': {
          for (final entry in maps.entries)
            entry.key: entry.value.toManifestJson(),
        },
        LanSyncEntityTombstoneType.favoriteFolder: {
          for (final entry in favoriteFolders.entries)
            entry.key: entry.value.toManifestJson(),
        },
        LanSyncEntityTombstoneType.impactGroup: {
          for (final entry in impactGroups.entries)
            entry.key: entry.value.toManifestJson(),
        },
      },
    };
  }
}

enum TagConflictType { uuidMismatch, semanticMatch }

enum ImportTagConflictResolution { local, shared }

enum ImportAreaConflictResolution { keepLocal, overwriteShared }

class TagConflictItem {
  final TagConflictType type;
  final PackageTagData sharedTag;
  final Tag localTag;

  const TagConflictItem({
    required this.type,
    required this.sharedTag,
    required this.localTag,
  });
}

class AreaConflictGroup {
  final String tagUuid;
  final String tagName;
  final String mapName;
  final List<String> layers;

  const AreaConflictGroup({
    required this.tagUuid,
    required this.tagName,
    required this.mapName,
    required this.layers,
  });
}

class ImportConflictBundle {
  final List<TagConflictItem> tagConflicts;
  final Map<String, Tag> localTagByUuid;

  const ImportConflictBundle({
    required this.tagConflicts,
    required this.localTagByUuid,
  });
}

class ImportConflictNotice {
  final List<GrenadePreviewItem> newerLocalGrenades;
  final List<GrenadePreviewItem> newerLocalDeleteConflicts;
  final List<String> newerLocalFavoriteFolderDeletes;

  const ImportConflictNotice({
    this.newerLocalGrenades = const [],
    this.newerLocalDeleteConflicts = const [],
    this.newerLocalFavoriteFolderDeletes = const [],
  });

  bool get hasConflicts =>
      newerLocalGrenades.isNotEmpty ||
      newerLocalDeleteConflicts.isNotEmpty ||
      newerLocalFavoriteFolderDeletes.isNotEmpty;
}

class EntityTombstoneApplyResult {
  final int deletedCount;
  final int skippedCount;
  final Map<String, int> deletedByType;
  final Map<String, int> skippedByType;

  const EntityTombstoneApplyResult({
    required this.deletedCount,
    required this.skippedCount,
    this.deletedByType = const {},
    this.skippedByType = const {},
  });
}

class OrphanMediaFileEntry {
  final String path;
  final int sizeBytes;

  const OrphanMediaFileEntry({
    required this.path,
    required this.sizeBytes,
  });
}

class OrphanMediaScanResult {
  final List<OrphanMediaFileEntry> orphanFiles;
  final List<int> orphanStepIds;
  final List<int> orphanMediaIds;

  const OrphanMediaScanResult({
    required this.orphanFiles,
    this.orphanStepIds = const [],
    this.orphanMediaIds = const [],
  });

  int get totalSizeBytes =>
      orphanFiles.fold(0, (sum, item) => sum + item.sizeBytes);

  int get orphanRecordCount => orphanStepIds.length + orphanMediaIds.length;

  bool get hasAnythingToClean =>
      orphanFiles.isNotEmpty || orphanRecordCount > 0;
}

class OrphanMediaCleanupResult {
  final List<OrphanMediaFileEntry> deletedFiles;
  final List<OrphanMediaFileEntry> failedFiles;
  final int deletedStepRecords;
  final int deletedMediaRecords;

  const OrphanMediaCleanupResult({
    required this.deletedFiles,
    required this.failedFiles,
    this.deletedStepRecords = 0,
    this.deletedMediaRecords = 0,
  });

  int get deletedBytes =>
      deletedFiles.fold(0, (sum, item) => sum + item.sizeBytes);

  int get deletedRecordCount => deletedStepRecords + deletedMediaRecords;
}

// 内部媒体引用快照，仅在媒体清理代理中使用
class MediaReferenceSnapshot {
  final Set<String> liveReferencedPaths;
  final Set<int> liveStepIds;
  final Set<int> liveMediaIds;
  final List<int> orphanStepIds;
  final List<int> orphanMediaIds;

  const MediaReferenceSnapshot({
    required this.liveReferencedPaths,
    required this.liveStepIds,
    required this.liveMediaIds,
    required this.orphanStepIds,
    required this.orphanMediaIds,
  });
}
