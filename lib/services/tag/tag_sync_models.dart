import '../../models/tag.dart';

class DefaultAreaTagReimportSummary {
  final int processedMaps;
  final int mapsWithPresets;
  final int addedTags;
  final int updatedTags;
  final int mapsWithAreaData;
  final int addedAreas;
  final int updatedAreas;
  final int removedDuplicateAreas;
  final List<AreaTagSyncDetail> addedTagDetails;
  final List<AreaTagSyncDetail> updatedTagDetails;

  const DefaultAreaTagReimportSummary({
    required this.processedMaps,
    required this.mapsWithPresets,
    required this.addedTags,
    required this.updatedTags,
    required this.mapsWithAreaData,
    required this.addedAreas,
    required this.updatedAreas,
    required this.removedDuplicateAreas,
    this.addedTagDetails = const <AreaTagSyncDetail>[],
    this.updatedTagDetails = const <AreaTagSyncDetail>[],
  });
}

class AreaTagSyncDetail {
  final int mapId;
  final String mapName;
  final int? tagId;
  final String tagName;
  final String oldTagUuid;
  final String newTagUuid;
  final int oldColorValue;
  final int newColorValue;

  const AreaTagSyncDetail({
    required this.mapId,
    required this.mapName,
    required this.tagId,
    required this.tagName,
    required this.oldTagUuid,
    required this.newTagUuid,
    required this.oldColorValue,
    required this.newColorValue,
  });

  String get reasonSummary {
    final reasons = <String>[];
    if (oldTagUuid != newTagUuid) reasons.add('UUID变化');
    if (oldColorValue != newColorValue) reasons.add('颜色变化');
    return reasons.isEmpty ? '无变化' : reasons.join('、');
  }
}

class EnsureSystemTagSummary {
  final int processedMaps;
  final int addedTags;
  final int updatedTags;
  final int removedObsoleteTags;
  final int keptObsoleteTagsInUse;
  final List<ObsoleteSystemTagUsageInfo> keptObsoleteTagDetails;

  const EnsureSystemTagSummary({
    required this.processedMaps,
    required this.addedTags,
    required this.updatedTags,
    required this.removedObsoleteTags,
    required this.keptObsoleteTagsInUse,
    this.keptObsoleteTagDetails = const <ObsoleteSystemTagUsageInfo>[],
  });
}

class ObsoleteSystemTagUsageInfo {
  final int mapId;
  final String mapName;
  final int tagId;
  final String tagName;
  final String tagUuid;
  final int dimension;
  final List<String> grenadeRefs;
  final List<String> areaRefs;

  const ObsoleteSystemTagUsageInfo({
    required this.mapId,
    required this.mapName,
    required this.tagId,
    required this.tagName,
    required this.tagUuid,
    required this.dimension,
    this.grenadeRefs = const <String>[],
    this.areaRefs = const <String>[],
  });

  String get dimensionName => TagDimension.getName(dimension);
}

class TagUuidMigrationSummary {
  final int migratedCount;
  final List<TagUuidMigrationDetail> details;

  const TagUuidMigrationSummary({
    required this.migratedCount,
    this.details = const <TagUuidMigrationDetail>[],
  });
}

class TagUuidMigrationDetail {
  final int tagId;
  final int mapId;
  final String mapName;
  final String tagName;
  final int dimension;
  final bool isSystem;
  final String oldUuid;
  final String newUuid;
  final String reason;

  const TagUuidMigrationDetail({
    required this.tagId,
    required this.mapId,
    required this.mapName,
    required this.tagName,
    required this.dimension,
    required this.isSystem,
    required this.oldUuid,
    required this.newUuid,
    required this.reason,
  });

  String get dimensionName => TagDimension.getName(dimension);
}
