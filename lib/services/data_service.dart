import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import 'data/data_package_models.dart' as package_models;
import 'data/data_package_models.dart'
    show
        ExportPackageEstimate,
        GrenadePreviewItem,
        ImportPackageMode,
        PackageEntityTombstoneData,
        PackageGrenadeTombstoneData,
        PackagePreviewResult;
import 'data/data_sync_and_media_models.dart'
    show
        AreaConflictGroup,
        ImportAreaConflictResolution,
        ImportConflictBundle,
        ImportConflictNotice,
        ImportTagConflictResolution,
        LanSyncManifestBundle,
        OrphanMediaCleanupResult,
        OrphanMediaFileEntry,
        OrphanMediaScanResult;
import 'data/lan_sync_package_builder.dart';
import 'data/media_cleanup_delegate.dart';
import 'data/package_archive_codec.dart' as archive_codec;
import 'data/package_conflict_collector.dart';
import 'data/package_export_engine.dart';
import 'data/package_import_applier.dart';
import 'data/package_import_entity_upserter.dart';
import 'data/package_preview_parser.dart';
import 'data/package_sync_helpers.dart' as sync_helpers;
import 'data/package_tombstone_and_map_importer.dart';

export 'data/data_package_models.dart'
    show
        ExportPackageEstimate,
        GrenadePreviewItem,
        ImportPackageMode,
        ImportStatus,
        PackageAreaData,
        PackageEntityTombstoneData,
        PackageFavoriteFolderData,
        PackageGrenadeTombstoneData,
        PackageImpactGroupData,
        PackageManifestData,
        PackageManifestFileEntry,
        PackageMapData,
        PackageMapLayerData,
        PackagePreviewResult,
        PackageTagData;
export 'data/data_sync_and_media_models.dart'
    show
        AreaConflictGroup,
        EntityTombstoneApplyResult,
        ImportAreaConflictResolution,
        ImportConflictBundle,
        ImportConflictNotice,
        ImportTagConflictResolution,
        LanSyncManifestBundle,
        LanSyncManifestItem,
        OrphanMediaCleanupResult,
        OrphanMediaFileEntry,
        OrphanMediaScanResult,
        TagConflictItem,
        TagConflictType;

class DataService {
  final Isar isar;
  late final MediaCleanupDelegate _mediaCleanupDelegate =
      MediaCleanupDelegate(isar);
  late final PackageExportEngine _exportEngine = PackageExportEngine(isar);
  late final LanSyncPackageBuilder _lanSyncBuilder =
      LanSyncPackageBuilder(isar, _exportEngine);
  late final PackagePreviewParser _previewParser =
      PackagePreviewParser(isar, _lanSyncBuilder);
  late final PackageConflictCollector _conflictCollector =
      PackageConflictCollector(isar, _lanSyncBuilder);
  late final PackageImportEntityUpserter _entityUpserter =
      PackageImportEntityUpserter(isar);
  late final PackageTombstoneAndMapImporter _tombstoneAndMapImporter =
      PackageTombstoneAndMapImporter(isar, _mediaCleanupDelegate);
  late final PackageImportApplier _importApplier = PackageImportApplier(
    isar,
    mediaCleanupDelegate: _mediaCleanupDelegate,
    lanSyncBuilder: _lanSyncBuilder,
    previewParser: _previewParser,
    entityUpserter: _entityUpserter,
    tombstoneAndMapImporter: _tombstoneAndMapImporter,
  );

  DataService(this.isar);

  static const Set<String> trackedImageExtensions =
      archive_codec.trackedImageExtensions;

  static const Set<String> trackedVideoExtensions =
      archive_codec.trackedVideoExtensions;

  static int get maxExportPackageSizeBytes =>
      package_models.maxExportPackageSizeBytes;

  static String formatBytes(int bytes) =>
      archive_codec.formatPackageBytes(bytes);

  static String normalizeMediaPath(String rawPath) =>
      MediaCleanupDelegate.normalizeMediaPath(rawPath);

  static Future<List<int>?> readPackageMediaBytes({
    required String packageFilePath,
    required String packageMediaPath,
    String? expectedSha256,
    int? expectedSizeBytes,
  }) =>
      archive_codec.readPackageMediaBytesFromArchive(
        packageFilePath: packageFilePath,
        packageMediaPath: packageMediaPath,
        expectedSha256: expectedSha256,
        expectedSizeBytes: expectedSizeBytes,
      );

  static Future<bool> deleteMediaFile(String localPath) =>
      MediaCleanupDelegate.deleteMediaFile(localPath);

  static Future<void> deleteMediaFiles(List<String> paths) =>
      MediaCleanupDelegate.deleteMediaFiles(paths);

  Future<ExportPackageEstimate> estimateExportPackage(
    List<Grenade> grenades,
  ) =>
      _exportEngine.estimateExportPackage(grenades);

  Future<List<String>> deleteMediaFilesIfUnused(
    Iterable<String> localPaths, {
    Set<int> excludingMediaIds = const {},
  }) =>
      _mediaCleanupDelegate.deleteMediaFilesIfUnused(
        localPaths,
        excludingMediaIds: excludingMediaIds,
      );

  Future<bool> deleteMediaFileIfUnused(
    String localPath, {
    int? excludingMediaId,
  }) =>
      _mediaCleanupDelegate.deleteMediaFileIfUnused(
        localPath,
        excludingMediaId: excludingMediaId,
      );

  Future<bool> deleteStepMedia(StepMedia media) =>
      _mediaCleanupDelegate.deleteStepMedia(media);

  Future<List<String>> deleteStep(GrenadeStep step) =>
      _mediaCleanupDelegate.deleteStep(step);

  Future<OrphanMediaScanResult> scanOrphanMediaFiles() =>
      _mediaCleanupDelegate.scanOrphanMediaFiles();

  Future<OrphanMediaCleanupResult> cleanupOrphanMediaFiles(
    Iterable<OrphanMediaFileEntry> files, {
    List<int> orphanStepIds = const [],
    List<int> orphanMediaIds = const [],
  }) =>
      _mediaCleanupDelegate.cleanupOrphanMediaFiles(
        files,
        orphanStepIds: orphanStepIds,
        orphanMediaIds: orphanMediaIds,
      );

  Future<int> deleteGrenades(
    List<Grenade> grenades, {
    bool recordSyncTombstones = true,
  }) =>
      _mediaCleanupDelegate.deleteGrenades(
        grenades,
        recordSyncTombstones: recordSyncTombstones,
      );

  Future<int> deleteAllGrenadesForMap(GameMap map) =>
      _mediaCleanupDelegate.deleteAllGrenadesForMap(map);

  Future<void> deleteImpactGroup(
    ImpactGroup group, {
    bool recordSyncTombstone = true,
  }) =>
      _mediaCleanupDelegate.deleteImpactGroup(
        group,
        recordSyncTombstone: recordSyncTombstone,
      );

  Future<PackagePreviewResult?> previewPackage(
    String filePath, {
    ImportPackageMode mode = ImportPackageMode.normal,
    bool requireTrustedPackage = false,
  }) =>
      _previewParser.previewPackage(
        filePath,
        mode: mode,
        requireTrustedPackage: requireTrustedPackage,
      );

  String entityTombstoneKey({
    required String entityType,
    required String entityKey,
  }) =>
      sync_helpers.buildEntityTombstoneKey(
        entityType: entityType,
        entityKey: entityKey,
      );

  String buildAreaEntityKey({
    required String tagUuid,
    required String layerName,
  }) =>
      sync_helpers.buildAreaTombstoneKey(
        tagUuid: tagUuid,
        layerName: layerName,
      );

  String buildFavoriteFolderEntityKey({
    required String mapName,
    required String nameKey,
  }) =>
      sync_helpers.buildFavoriteFolderTombstoneKey(
        mapName: mapName,
        nameKey: nameKey,
      );

  String buildImpactGroupEntityKey({
    required String mapName,
    required String layerName,
    required int type,
    required String name,
    required double impactXRatio,
    required double impactYRatio,
  }) =>
      sync_helpers.buildImpactGroupTombstoneKey(
        mapName: mapName,
        layerName: layerName,
        type: type,
        name: name,
        impactXRatio: impactXRatio,
        impactYRatio: impactYRatio,
      );

  Future<LanSyncManifestBundle> buildLanSyncManifest({
    required Set<String> mapKeys,
  }) =>
      _lanSyncBuilder.buildLanSyncManifest(mapKeys: mapKeys);

  Future<String> buildLanSyncPackageToTemp({
    required int scopeType,
    Grenade? singleGrenade,
    GameMap? singleMap,
    List<Grenade>? explicitGrenades,
    List<Map<String, dynamic>> explicitGrenadePayloads = const [],
    List<Map<String, dynamic>> explicitTagPayloads = const [],
    List<Map<String, dynamic>> explicitAreaPayloads = const [],
    List<Map<String, dynamic>> explicitMapPayloads = const [],
    List<Map<String, dynamic>> explicitFavoriteFolderPayloads = const [],
    List<Map<String, dynamic>> explicitImpactGroupPayloads = const [],
    Set<String> explicitFilesToZip = const <String>{},
    List<PackageGrenadeTombstoneData> grenadeTombstones = const [],
    List<PackageEntityTombstoneData> entityTombstones = const [],
  }) =>
      _lanSyncBuilder.buildLanSyncPackageToTemp(
        scopeType: scopeType,
        singleGrenade: singleGrenade,
        singleMap: singleMap,
        explicitGrenades: explicitGrenades,
        explicitGrenadePayloads: explicitGrenadePayloads,
        explicitTagPayloads: explicitTagPayloads,
        explicitAreaPayloads: explicitAreaPayloads,
        explicitMapPayloads: explicitMapPayloads,
        explicitFavoriteFolderPayloads: explicitFavoriteFolderPayloads,
        explicitImpactGroupPayloads: explicitImpactGroupPayloads,
        explicitFilesToZip: explicitFilesToZip,
        grenadeTombstones: grenadeTombstones,
        entityTombstones: entityTombstones,
      );

  Future<List<Grenade>> loadGrenadesByUniqueIds(
    Iterable<String> uniqueIds,
  ) =>
      _lanSyncBuilder.loadGrenadesByUniqueIds(uniqueIds);

  Future<Map<String, GrenadePreviewItem>>
      loadLocalGrenadePreviewItemsByUniqueIds(
    Iterable<String> uniqueIds,
  ) =>
          _lanSyncBuilder.loadLocalGrenadePreviewItemsByUniqueIds(uniqueIds);

  Future<Map<String, Map<String, String>>> buildGrenadeDigestByMap({
    required Set<String> mapKeys,
  }) =>
      _lanSyncBuilder.buildGrenadeDigestByMap(mapKeys: mapKeys);

  Future<void> exportSelectedGrenades(
    BuildContext context,
    List<Grenade> grenades,
  ) =>
      _exportEngine.exportSelectedGrenades(context, grenades);

  Future<void> exportData(
    BuildContext context, {
    required int scopeType,
    Grenade? singleGrenade,
    GameMap? singleMap,
  }) =>
      _exportEngine.exportData(
        context,
        scopeType: scopeType,
        singleGrenade: singleGrenade,
        singleMap: singleMap,
      );

  Future<ImportConflictBundle> collectTagConflicts(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds,
  ) =>
      _conflictCollector.collectTagConflicts(preview, selectedUniqueIds);

  Future<List<AreaConflictGroup>> collectAreaConflicts(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    required Map<String, ImportTagConflictResolution> tagResolutions,
  }) =>
      _conflictCollector.collectAreaConflicts(
        preview,
        selectedUniqueIds,
        tagResolutions: tagResolutions,
      );

  Future<ImportConflictNotice> collectImportConflictNotice(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    ImportPackageMode mode = ImportPackageMode.normal,
  }) =>
      _conflictCollector.collectImportConflictNotice(
        preview,
        selectedUniqueIds,
        mode: mode,
      );

  Future<String> importData() => _importApplier.importData();

  Future<String> importFromPath(String filePath) =>
      _importApplier.importFromPath(filePath);

  Future<String> importFromPreview(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    Map<String, ImportTagConflictResolution> tagResolutions = const {},
    Map<String, ImportAreaConflictResolution> areaResolutions = const {},
    ImportPackageMode mode = ImportPackageMode.normal,
  }) =>
      _importApplier.importFromPreview(
        preview,
        selectedUniqueIds,
        tagResolutions: tagResolutions,
        areaResolutions: areaResolutions,
        mode: mode,
      );
}
