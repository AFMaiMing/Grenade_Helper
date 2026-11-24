import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import 'data_package_models.dart';
import 'package_archive_codec.dart';

bool isAssetPath(String path) {
  return path.trim().replaceAll('\\', '/').toLowerCase().startsWith('assets/');
}

bool isBuiltinAssetMap(GameMap map) {
  return isAssetPath(map.backgroundPath);
}

void addMapFileToZipIfNeeded(String path, Set<String> filesToZip) {
  final normalized = path.trim();
  if (normalized.isEmpty || isAssetPath(normalized)) return;
  final file = File(normalized);
  if (!file.existsSync()) return;
  filesToZip.add(file.path);
}

String normalizeFolderNameKey(String value) {
  return value.trim().toLowerCase();
}

String normalizeImpactGroupName(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

double roundRatio3(double value) => (value * 1000).round() / 1000.0;

String impactGroupSemanticKey({
  required String mapName,
  required String layerName,
  required int type,
  required String name,
  required double impactXRatio,
  required double impactYRatio,
}) {
  return '${mapName.trim().toLowerCase()}|'
      '${layerName.trim().toLowerCase()}|'
      '$type|'
      '${normalizeImpactGroupName(name)}|'
      '${roundRatio3(impactXRatio).toStringAsFixed(3)}|'
      '${roundRatio3(impactYRatio).toStringAsFixed(3)}';
}

String favoriteFolderRefKey({
  required String mapName,
  required String nameKey,
}) {
  return '${mapName.trim().toLowerCase()}|${nameKey.trim().toLowerCase()}';
}

String buildEntityTombstoneKey({
  required String entityType,
  required String entityKey,
}) {
  return '${entityType.trim()}|${entityKey.trim()}';
}

String buildAreaTombstoneKey({
  required String tagUuid,
  required String layerName,
}) {
  return '${tagUuid.trim()}|${layerName.trim().toLowerCase()}';
}

String buildFavoriteFolderTombstoneKey({
  required String mapName,
  required String nameKey,
}) {
  return favoriteFolderRefKey(mapName: mapName, nameKey: nameKey);
}

String buildImpactGroupTombstoneKey({
  required String mapName,
  required String layerName,
  required int type,
  required String name,
  required double impactXRatio,
  required double impactYRatio,
}) {
  return impactGroupSemanticKey(
    mapName: mapName,
    layerName: layerName,
    type: type,
    name: name,
    impactXRatio: impactXRatio,
    impactYRatio: impactYRatio,
  );
}

String digestJsonValue(Object? value) {
  final canonical = canonicalizePackageJsonValue(value);
  final encoded = jsonEncode(canonical);
  return sha256.convert(utf8.encode(encoded)).toString();
}

Map<String, dynamic> normalizePayloadForSyncDigest(
  Map<String, dynamic> value, {
  bool removeHasLocalEdits = false,
}) {
  final normalized =
      Map<String, dynamic>.from(canonicalizePackageJsonValue(value) as Map);
  normalized.remove('createdAt');
  normalized.remove('updatedAt');
  if (removeHasLocalEdits) {
    normalized.remove('hasLocalEdits');
  }
  return normalized;
}

Map<String, dynamic> normalizeGrenadePayloadForSync(
  Map<String, dynamic> value,
) {
  return normalizePayloadForSyncDigest(
    value,
    removeHasLocalEdits: true,
  );
}

String normalizeStructuredJsonString(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  try {
    final decoded = jsonDecode(trimmed);
    return jsonEncode(canonicalizePackageJsonValue(decoded));
  } catch (_) {
    return trimmed;
  }
}

bool isSharedAreaEquivalent(MapArea local, PackageAreaData shared) {
  return local.name == shared.name &&
      local.colorValue == shared.colorValue &&
      normalizeStructuredJsonString(local.strokes) ==
          normalizeStructuredJsonString(shared.strokes);
}

Future<bool> isLocalFileEquivalentToPackagePath({
  required String localPath,
  required String sharedRawPath,
  required Map<String, String> packageFileHashes,
}) async {
  final normalizedLocal = localPath.trim();
  final normalizedShared = sharedRawPath.trim();
  if (normalizedShared.isEmpty) return normalizedLocal.isEmpty;
  if (isAssetPath(normalizedShared)) {
    return normalizedLocal == normalizedShared;
  }
  if (normalizedLocal.isEmpty) return false;
  final fileName = extractArchiveFileNameFromPackagePath(normalizedShared);
  final expectedHash = packageFileHashes[fileName] ?? '';
  if (expectedHash.isEmpty) {
    return normalizedLocal == normalizedShared;
  }
  final localHash = await sha256FileHex(normalizedLocal);
  return localHash.isNotEmpty && localHash == expectedHash;
}

Future<bool> isSharedMapEquivalentToLocal(
  PackageMapData shared,
  GameMap local, {
  required Map<String, String> packageFileHashes,
}) async {
  if (!await isLocalFileEquivalentToPackagePath(
    localPath: local.backgroundPath,
    sharedRawPath: shared.backgroundPath,
    packageFileHashes: packageFileHashes,
  )) {
    return false;
  }
  if (!await isLocalFileEquivalentToPackagePath(
    localPath: local.iconPath,
    sharedRawPath: shared.iconPath,
    packageFileHashes: packageFileHashes,
  )) {
    return false;
  }

  await local.layers.load();
  final localLayerByName = <String, MapLayer>{
    for (final layer in local.layers)
      if (layer.name.trim().isNotEmpty) layer.name.trim(): layer,
  };
  for (final sharedLayer in shared.layers) {
    final layerName = sharedLayer.name.trim();
    if (layerName.isEmpty) continue;
    final localLayer = localLayerByName[layerName];
    if (localLayer == null) return false;
    if (localLayer.sortOrder != sharedLayer.sortOrder) return false;
    if (!await isLocalFileEquivalentToPackagePath(
      localPath: localLayer.assetPath,
      sharedRawPath: sharedLayer.assetPath,
      packageFileHashes: packageFileHashes,
    )) {
      return false;
    }
  }
  return true;
}

String semanticTagKey(int mapId, int dimension, String name) {
  return '$mapId|$dimension|${name.trim().toLowerCase()}';
}

bool isTagDifferent(Tag local, PackageTagData shared) {
  return local.name != shared.name ||
      local.colorValue != shared.colorValue ||
      local.dimension != shared.dimension ||
      (local.groupName ?? '') != (shared.groupName ?? '') ||
      local.isSystem != shared.isSystem;
}

bool requiresManualConflictResolution({
  required int sharedUpdatedAtMs,
  required int localUpdatedAtMs,
  required bool contentDifferent,
}) {
  return sharedUpdatedAtMs == localUpdatedAtMs && contentDifferent;
}

bool shouldApplyIncomingUpdate({
  required int sharedUpdatedAtMs,
  required int localUpdatedAtMs,
  required bool contentDifferent,
}) {
  if (sharedUpdatedAtMs > localUpdatedAtMs) return true;
  if (sharedUpdatedAtMs < localUpdatedAtMs) return false;
  return contentDifferent;
}

List<String> readTagUuids(Map<String, dynamic> item) {
  final raw = item['tagUuids'];
  if (raw is List) {
    return raw
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
  return const [];
}

PackageFavoriteFolderRef? readFavoriteFolderRef(Map<String, dynamic> item) {
  final raw = item['favoriteFolderRef'];
  if (raw is! Map) return null;
  final mapName = (raw['mapName'] as String? ?? '').trim();
  final nameKey = normalizeFolderNameKey(raw['nameKey'] as String? ?? '');
  if (mapName.isEmpty || nameKey.isEmpty) return null;
  return PackageFavoriteFolderRef(mapName: mapName, nameKey: nameKey);
}

PackageImpactGroupRef? readImpactGroupRef(Map<String, dynamic> item) {
  final raw = item['impactGroupRef'];
  if (raw is! Map) return null;
  final mapName = (raw['mapName'] as String? ?? '').trim();
  final layerName = (raw['layerName'] as String? ?? '').trim();
  final name = (raw['name'] as String? ?? '').trim();
  final type = raw['type'] as int?;
  final x = (raw['impactXRatio'] as num?)?.toDouble();
  final y = (raw['impactYRatio'] as num?)?.toDouble();
  if (mapName.isEmpty ||
      layerName.isEmpty ||
      name.isEmpty ||
      type == null ||
      x == null ||
      y == null) {
    return null;
  }
  return PackageImpactGroupRef(
    mapName: mapName,
    layerName: layerName,
    name: name,
    type: type,
    impactXRatio: x,
    impactYRatio: y,
  );
}

Set<String> collectSelectedTagUuids(
  PackagePreviewResult preview,
  Set<String> selectedUniqueIds,
) {
  final result = <String>{};
  for (final mapItems in preview.grenadesByMap.values) {
    for (final item in mapItems) {
      if (!selectedUniqueIds.contains(item.uniqueId)) continue;
      final raw = item.rawData['tagUuids'];
      if (raw is! List) continue;
      for (final uuid in raw) {
        if (uuid is String && uuid.trim().isNotEmpty) {
          result.add(uuid.trim());
        }
      }
    }
  }
  return result;
}

Set<String> collectImportTagUuids(
  PackagePreviewResult preview,
  Set<String> selectedUniqueIds,
) {
  final selected = collectSelectedTagUuids(preview, selectedUniqueIds);
  final uuids = <String>{
    ...selected,
    ...preview.tagsByUuid.keys.map((e) => e.trim()).where((e) => e.isNotEmpty),
    ...preview.areas.map((e) => e.tagUuid.trim()).where((e) => e.isNotEmpty),
  };
  return uuids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
}

Future<LocalTagContext> buildLocalTagContext(
  Isar isar,
  Set<String> mapNames,
) async {
  final mapByName = <String, GameMap>{};
  for (final mapName in mapNames) {
    final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
    if (map != null) {
      mapByName[mapName] = map;
    }
  }

  final localByUuid = <String, Tag>{};
  final localBySemantic = <String, Tag>{};
  for (final map in mapByName.values) {
    final tags = await isar.tags.filter().mapIdEqualTo(map.id).findAll();
    for (final tag in tags) {
      final uuid = tag.tagUuid.trim();
      if (uuid.isNotEmpty) {
        localByUuid[uuid] = tag;
      }
      localBySemantic[semanticTagKey(map.id, tag.dimension, tag.name)] = tag;
    }
  }

  return LocalTagContext(
    mapByName: mapByName,
    localByUuid: localByUuid,
    localBySemantic: localBySemantic,
  );
}

String buildSharedGrenadeDigest(
  Map<String, dynamic> item,
  Map<String, String> packageFileHashes,
) {
  final normalized = normalizeGrenadePayloadForSync(item);
  final sharedSteps = ((normalized['steps'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList(growable: false);
  for (var i = 0; i < sharedSteps.length; i++) {
    final medias =
        ((sharedSteps[i]['medias'] as List?) ?? const []).cast<dynamic>();
    final normalizedMedias = <Map<String, dynamic>>[];
    for (final media in medias) {
      final mediaMap = Map<String, dynamic>.from(media as Map);
      final fileName = (mediaMap['path'] as String? ?? '').trim();
      final mediaHash =
          fileName.isNotEmpty && packageFileHashes.containsKey(fileName)
              ? packageFileHashes[fileName]!
              : '';
      normalizedMedias.add({
        'type': mediaMap['type'],
        'contentHash': mediaHash,
      });
    }
    sharedSteps[i]['medias'] = normalizedMedias;
  }
  normalized['steps'] = sharedSteps;
  return digestJsonValue(normalized);
}

Future<MapLayer?> resolveTargetLayerForImport(
  GameMap map,
  String layerName,
) async {
  await map.layers.load();
  for (final l in map.layers) {
    if (l.name == layerName) {
      return l;
    }
  }
  return map.layers.isNotEmpty ? map.layers.first : null;
}

Future<Grenade?> findExistingGrenadeForImport(
  Isar isar,
  MapLayer layer, {
  required String? importedUniqueId,
  required String title,
  required double xRatio,
  required double yRatio,
}) async {
  if (importedUniqueId != null && importedUniqueId.isNotEmpty) {
    final allGrenades = await isar.grenades.where().findAll();
    final matched =
        allGrenades.where((g) => g.uniqueId == importedUniqueId).firstOrNull;
    if (matched != null) return matched;
  }
  if (importedUniqueId == null) {
    await layer.grenades.load();
    return layer.grenades
        .where((g) =>
            g.title == title &&
            (g.xRatio - xRatio).abs() < 0.01 &&
            (g.yRatio - yRatio).abs() < 0.01)
        .firstOrNull;
  }
  return null;
}
