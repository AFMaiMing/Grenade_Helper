import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../models.dart';
import '../../models/grenade_tag.dart';
import '../lan_sync/lan_sync_local_store.dart';
import 'data_package_models.dart';
import 'data_sync_and_media_models.dart';
import 'lan_sync_package_builder.dart';
import 'media_cleanup_delegate.dart';
import 'package_archive_codec.dart';
import 'package_import_entity_upserter.dart';
import 'package_preview_parser.dart';
import 'package_sync_helpers.dart';
import 'package_tombstone_and_map_importer.dart';

class PackageImportApplier {
  final Isar isar;
  final MediaCleanupDelegate mediaCleanupDelegate;
  final LanSyncPackageBuilder lanSyncBuilder;
  final PackagePreviewParser previewParser;
  final PackageImportEntityUpserter entityUpserter;
  final PackageTombstoneAndMapImporter tombstoneAndMapImporter;

  PackageImportApplier(
    this.isar, {
    required this.mediaCleanupDelegate,
    required this.lanSyncBuilder,
    required this.previewParser,
    required this.entityUpserter,
    required this.tombstoneAndMapImporter,
  });

  Future<String> importData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要导入的 .cs2pkg 文件',
    );
    if (result == null) return '取消导入';

    final filePath = result.files.single.path!;
    return importFromPath(filePath);
  }

  Future<String> importFromPath(String filePath) async {
    if (!filePath.toLowerCase().endsWith('.cs2pkg')) {
      return '请选择 .cs2pkg 格式的文件';
    }

    final preview = await previewParser.previewPackage(filePath);
    if (preview == null) return '文件格式错误或无数据';

    final selected = <String>{};
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final item in mapGrenades) {
        if (item.status != ImportStatus.skip) {
          selected.add(item.uniqueId);
        }
      }
    }

    return importFromPreview(
      preview,
      selected,
      tagResolutions: const {},
      areaResolutions: const {},
    );
  }

  Future<String> importFromPreview(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    Map<String, ImportTagConflictResolution> tagResolutions = const {},
    Map<String, ImportAreaConflictResolution> areaResolutions = const {},
    ImportPackageMode mode = ImportPackageMode.normal,
  }) async {
    final allowAppliedTombstones =
        mode == ImportPackageMode.lanSync && preview.canApplyTombstones;
    final hasGrenadeSelection = selectedUniqueIds.isNotEmpty;
    final hasMetadataChanges = preview.metadataChangeCount > 0;
    final hasTombstones = allowAppliedTombstones &&
        (preview.grenadeTombstones.isNotEmpty ||
            preview.entityTombstones.isNotEmpty);
    if (!hasGrenadeSelection && !hasMetadataChanges && !hasTombstones) {
      if (mode == ImportPackageMode.lanSync) {
        return '同步成功：数据已是最新';
      }
      return '未选择任何道具';
    }

    final importFileName = p.basename(preview.filePath);
    final dataPath = isar.directory ?? '';

    final tombstoneResult = allowAppliedTombstones
        ? await tombstoneAndMapImporter.applyGrenadeTombstones(preview)
        : (deletedCount: 0, skippedCount: 0);
    final entityTombstoneResult = allowAppliedTombstones
        ? await tombstoneAndMapImporter.applyEntityTombstones(preview)
        : const EntityTombstoneApplyResult(
            deletedCount: 0,
            skippedCount: 0,
          );
    final selectedTagUuids = collectImportTagUuids(preview, selectedUniqueIds);
    var tagIdByUuid = <String, int>{};
    var favoriteFolderIdByRef = <String, int>{};
    var impactGroupIdByRef = <String, int>{};

    int newCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    int syncedMapCount = 0;
    final importedGrenades = <Grenade>[];
    final importedMediaPathCache = <String, String>{};

    Future<String> runImportWithArchive(Archive? packageArchive) async {
      final shouldOpenPackageArchive =
          hasGrenadeSelection || preview.maps.isNotEmpty;
      if (shouldOpenPackageArchive && packageArchive == null) {
        return '文件格式错误或无数据';
      }

      syncedMapCount = await tombstoneAndMapImporter.upsertMapsForImport(
        preview,
        packageArchive: packageArchive,
        dataPath: dataPath,
        importedMediaPathCache: importedMediaPathCache,
      );

      tagIdByUuid = await entityUpserter.upsertTagsForImport(
        preview,
        selectedTagUuids,
        tagResolutions: tagResolutions,
      );
      await entityUpserter.upsertAreasForImport(
        preview,
        selectedTagUuids,
        tagIdByUuid: tagIdByUuid,
        areaResolutions: areaResolutions,
      );
      favoriteFolderIdByRef =
          await entityUpserter.upsertFavoriteFoldersForImport(preview);
      impactGroupIdByRef =
          await entityUpserter.upsertImpactGroupsForImport(preview);

      if (hasGrenadeSelection) {
        for (final mapGrenades in preview.grenadesByMap.values) {
          for (final previewItem in mapGrenades) {
            if (!selectedUniqueIds.contains(previewItem.uniqueId)) continue;

            final item = previewItem.rawData;
            final mapName = item['mapName'];
            final layerName = item['layerName'];

            final map =
                await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
            if (map == null) continue;

            final layer = await resolveTargetLayerForImport(map, layerName);
            if (layer == null) continue;

            final importedUniqueId = item['uniqueId'] as String?;
            final title = item['title'] as String;
            final xRatio = (item['x'] as num).toDouble();
            final yRatio = (item['y'] as num).toDouble();
            final tagUuids = readTagUuids(item);

            final existing = await findExistingGrenadeForImport(
              isar,
              layer,
              importedUniqueId: importedUniqueId,
              title: title,
              xRatio: xRatio,
              yRatio: yRatio,
            );

            if (existing != null) {
              if (await lanSyncBuilder.shouldImportGrenadeOverLocal(
                existing,
                item,
                preview.packageFileHashes,
              )) {
                await _updateExistingGrenade(
                  existing,
                  item,
                  preview,
                  packageArchive,
                  dataPath,
                  importedMediaPathCache,
                );
                await _replaceGrenadeTags(existing.id, tagUuids, tagIdByUuid);
                await _applyLanSyncRefsToGrenade(
                  existing,
                  item,
                  favoriteFolderIdByRef: favoriteFolderIdByRef,
                  impactGroupIdByRef: impactGroupIdByRef,
                );
                importedGrenades.add(existing);
                updatedCount++;
              } else {
                skippedCount++;
              }
            } else {
              final newGrenade = await _createNewGrenade(
                item,
                preview,
                packageArchive,
                dataPath,
                layer,
                importedUniqueId,
                importedMediaPathCache,
              );
              await _replaceGrenadeTags(newGrenade.id, tagUuids, tagIdByUuid);
              await _applyLanSyncRefsToGrenade(
                newGrenade,
                item,
                favoriteFolderIdByRef: favoriteFolderIdByRef,
                impactGroupIdByRef: impactGroupIdByRef,
              );
              importedGrenades.add(newGrenade);
              newCount++;
            }
          }
        }
      }
      if (importedGrenades.isNotEmpty) {
        final importedIds = importedGrenades
            .map((e) => e.id)
            .where((id) => id > 0)
            .toList(growable: false);
        await isar.writeTxn(() async {
          final history = ImportHistory(
            fileName: importFileName,
            importedAt: DateTime.now(),
            newCount: newCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount,
          );
          await isar.importHistorys.put(history);
          final savedGrenades = await isar.grenades.getAll(importedIds);
          history.grenades.addAll(savedGrenades.whereType<Grenade>());
          await history.grenades.save();
        });
      }
      return '';
    }

    final shouldOpenPackageArchive =
        hasGrenadeSelection || preview.maps.isNotEmpty;
    final earlyExitMessage = shouldOpenPackageArchive
        ? await withOpenedCs2PackageArchive(
            preview.filePath, runImportWithArchive)
        : await runImportWithArchive(null);
    if (earlyExitMessage.isNotEmpty) {
      return earlyExitMessage;
    }

    final messages = <String>[];
    if (newCount > 0) messages.add('新增 $newCount 个');
    if (updatedCount > 0) messages.add('更新 $updatedCount 个');
    if (skippedCount > 0) messages.add('跳过 $skippedCount 个较旧版本');
    if (tombstoneResult.deletedCount > 0) {
      messages.add('删除 ${tombstoneResult.deletedCount} 个');
    }
    if (tombstoneResult.skippedCount > 0) {
      messages.add('忽略 ${tombstoneResult.skippedCount} 条较新的本地版本');
    }
    if (entityTombstoneResult.deletedByType.isNotEmpty) {
      const orderedTypes = <String>[
        LanSyncEntityTombstoneType.tag,
        LanSyncEntityTombstoneType.area,
        LanSyncEntityTombstoneType.favoriteFolder,
        LanSyncEntityTombstoneType.impactGroup,
      ];
      for (final type in orderedTypes) {
        final count = entityTombstoneResult.deletedByType[type] ?? 0;
        if (count <= 0) continue;
        messages.add('${_entityTypeLabel(type)}删除 $count 条');
      }
    }
    if (entityTombstoneResult.skippedByType.isNotEmpty) {
      const orderedTypes = <String>[
        LanSyncEntityTombstoneType.favoriteFolder,
      ];
      for (final type in orderedTypes) {
        final count = entityTombstoneResult.skippedByType[type] ?? 0;
        if (count <= 0) continue;
        messages.add('忽略 $count 条较新的${_entityTypeLabel(type)}删除');
      }
    }
    if (syncedMapCount > 0) {
      messages.add('地图同步 $syncedMapCount 张');
    }
    if (!hasGrenadeSelection) {
      if (preview.changedTagCount > 0) {
        messages.add('标签同步 ${preview.changedTagCount} 条');
      }
      if (preview.changedAreaCount > 0) {
        messages.add('区域同步 ${preview.changedAreaCount} 条');
      }
      if (preview.changedFavoriteFolderCount > 0) {
        messages.add('收藏夹同步 ${preview.changedFavoriteFolderCount} 条');
      }
      if (preview.changedImpactGroupCount > 0) {
        messages.add('爆点分组同步 ${preview.changedImpactGroupCount} 条');
      }
    }

    if (messages.isEmpty) {
      return '没有可导入的道具';
    }
    return '成功导入：${messages.join('，')}';
  }

  String _entityTypeLabel(String type) {
    switch (type) {
      case LanSyncEntityTombstoneType.tag:
        return '标签';
      case LanSyncEntityTombstoneType.area:
        return '区域';
      case LanSyncEntityTombstoneType.favoriteFolder:
        return '收藏夹';
      case LanSyncEntityTombstoneType.impactGroup:
        return '爆点分组';
      default:
        return '对象';
    }
  }

  Future<void> _applyLanSyncRefsToGrenade(
    Grenade grenade,
    Map<String, dynamic> item, {
    required Map<String, int> favoriteFolderIdByRef,
    required Map<String, int> impactGroupIdByRef,
  }) async {
    var changed = false;

    if (item.containsKey('isFavorite') ||
        item.containsKey('favoriteFolderRef')) {
      final isFavorite = item['isFavorite'] == true;
      int? favoriteFolderId;
      if (isFavorite) {
        final ref = readFavoriteFolderRef(item);
        if (ref != null) {
          final key = favoriteFolderRefKey(
            mapName: ref.mapName,
            nameKey: ref.nameKey,
          );
          favoriteFolderId = favoriteFolderIdByRef[key];
        }
      }

      final nextIsFavorite = isFavorite && favoriteFolderId != null;
      if (grenade.isFavorite != nextIsFavorite) {
        grenade.isFavorite = nextIsFavorite;
        changed = true;
      }
      if (grenade.favoriteFolderId != favoriteFolderId) {
        grenade.favoriteFolderId = favoriteFolderId;
        changed = true;
      }
    }

    if (item.containsKey('impactGroupRef')) {
      int? nextImpactGroupId;
      final ref = readImpactGroupRef(item);
      if (ref != null) {
        final key = impactGroupSemanticKey(
          mapName: ref.mapName,
          layerName: ref.layerName,
          type: ref.type,
          name: ref.name,
          impactXRatio: ref.impactXRatio,
          impactYRatio: ref.impactYRatio,
        );
        nextImpactGroupId = impactGroupIdByRef[key];
      }
      if (grenade.impactGroupId != nextImpactGroupId) {
        grenade.impactGroupId = nextImpactGroupId;
        changed = true;
      }
    }

    if (changed) {
      await isar.writeTxn(() async {
        await isar.grenades.put(grenade);
      });
    }
  }

  Future<void> _replaceGrenadeTags(
    int grenadeId,
    List<String> tagUuids,
    Map<String, int> tagIdByUuid,
  ) async {
    final targetTagIds = <int>{};
    for (final uuid in tagUuids) {
      final tagId = tagIdByUuid[uuid];
      if (tagId != null) {
        targetTagIds.add(tagId);
      }
    }

    await isar.writeTxn(() async {
      await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).deleteAll();
      for (final tagId in targetTagIds) {
        await isar.grenadeTags
            .put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
      }
    });
  }

  Future<void> _writeGrenadeStepsAndMedias(
    Grenade targetGrenade,
    Map<String, dynamic> item,
    PackagePreviewResult preview,
    Archive? packageArchive,
    String dataPath,
    Map<String, String> importedMediaPathCache,
  ) async {
    final stepsList = item['steps'] as List;
    for (final sItem in stepsList) {
      final step = GrenadeStep(
        title: sItem['title'] ?? '',
        description: sItem['description'],
        stepIndex: sItem['index'],
      );
      final mediasList = sItem['medias'] as List;
      final mediasToCreate = <StepMedia>[];
      for (final mItem in mediasList) {
        final fileName = mItem['path'];
        final savePath =
            await tombstoneAndMapImporter.materializePackageMediaFile(
          preview: preview,
          packageArchive: packageArchive,
          packageMediaPath: fileName as String? ?? '',
          dataPath: dataPath,
          importedMediaPathCache: importedMediaPathCache,
        );
        if (savePath != null) {
          mediasToCreate
              .add(StepMedia(localPath: savePath, type: mItem['type']));
        }
      }
      await isar.writeTxn(() async {
        await isar.grenadeSteps.put(step);
        step.grenade.value = targetGrenade;
        await step.grenade.save();
        targetGrenade.steps.add(step);
        for (final media in mediasToCreate) {
          await isar.stepMedias.put(media);
          media.step.value = step;
          await media.step.save();
          step.medias.add(media);
        }
        await step.medias.save();
      });
    }
    await isar.writeTxn(() async {
      await targetGrenade.steps.save();
    });
  }

  Future<void> _updateExistingGrenade(
    Grenade existing,
    Map<String, dynamic> item,
    PackagePreviewResult preview,
    Archive? packageArchive,
    String dataPath,
    Map<String, String> importedMediaPathCache,
  ) async {
    existing.title = item['title'];
    existing.type = item['type'];
    existing.team = item['team'];
    existing.author = item['author'] as String?;
    existing.sourceUrl = item['sourceUrl'] as String?;
    existing.sourceNote = item['sourceNote'] as String?;
    existing.hasLocalEdits = false;
    existing.isImported = true;
    existing.xRatio = (item['x'] as num).toDouble();
    existing.yRatio = (item['y'] as num).toDouble();
    existing.impactXRatio = (item['impactX'] as num?)?.toDouble();
    existing.impactYRatio = (item['impactY'] as num?)?.toDouble();
    existing.impactAreaStrokes = item['impactAreaStrokes'] as String?;
    existing.updatedAt = DateTime.fromMillisecondsSinceEpoch(item['updatedAt']);
    existing.isNewImport = true;
    await isar.writeTxn(() async {
      await isar.grenades.put(existing);
    });

    await existing.steps.load();
    final oldMediaPaths = <String>{};
    await isar.writeTxn(() async {
      for (final step in existing.steps) {
        await step.medias.load();
        for (final media in step.medias) {
          final path = media.localPath.trim();
          if (path.isNotEmpty) {
            oldMediaPaths.add(path);
          }
          await isar.stepMedias.delete(media.id);
        }
        await isar.grenadeSteps.delete(step.id);
      }
    });
    existing.steps.clear();
    await isar.writeTxn(() async {
      await existing.steps.save();
    });
    await mediaCleanupDelegate.deleteMediaFilesIfUnused(oldMediaPaths);

    await _writeGrenadeStepsAndMedias(
      existing,
      item,
      preview,
      packageArchive,
      dataPath,
      importedMediaPathCache,
    );
  }

  Future<Grenade> _createNewGrenade(
    Map<String, dynamic> item,
    PackagePreviewResult preview,
    Archive? packageArchive,
    String dataPath,
    MapLayer layer,
    String? uniqueId,
    Map<String, String> importedMediaPathCache,
  ) async {
    final g = Grenade(
      title: item['title'],
      type: item['type'],
      team: item['team'],
      xRatio: (item['x'] as num).toDouble(),
      yRatio: (item['y'] as num).toDouble(),
      isNewImport: true,
      hasLocalEdits: false,
      isImported: true,
      uniqueId: uniqueId ?? const Uuid().v4(),
      created: item['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['createdAt'])
          : DateTime.now(),
      updated: item['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
          : DateTime.now(),
    );
    g.author = item['author'] as String?;
    g.sourceUrl = item['sourceUrl'] as String?;
    g.sourceNote = item['sourceNote'] as String?;
    g.impactXRatio = (item['impactX'] as num?)?.toDouble();
    g.impactYRatio = (item['impactY'] as num?)?.toDouble();
    g.impactAreaStrokes = item['impactAreaStrokes'] as String?;
    await isar.writeTxn(() async {
      await isar.grenades.put(g);
    });

    g.layer.value = layer;
    await isar.writeTxn(() async {
      await g.layer.save();
    });

    await _writeGrenadeStepsAndMedias(
      g,
      item,
      preview,
      packageArchive,
      dataPath,
      importedMediaPathCache,
    );

    return g;
  }
}
