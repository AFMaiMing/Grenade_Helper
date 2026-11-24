import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'lan_sync_store_codec.dart';
import 'lan_sync_store_models.dart';

/// 局域网同步墓碑与地图基线存储委托
class LanSyncTombstoneBaselineStore {
  static const _ackedMapBaselinesKey = 'lan_sync_acked_map_baselines_v1';
  static const _mapBaselineSnapshotsKey = 'lan_sync_map_baseline_snapshots_v1';
  static const _grenadeTombstonesKey = 'lan_sync_grenade_tombstones_v1';
  static const _entityTombstonesKey = 'lan_sync_entity_tombstones_v1';
  static const _maxGrenadeTombstones = 4000;
  static const _maxEntityTombstones = 4000;

  const LanSyncTombstoneBaselineStore();

  Future<void> cleanupLegacySyncState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ackedMapBaselinesKey);
    await prefs.remove(_mapBaselineSnapshotsKey);
  }

  Future<Map<String, String>> loadAckedMapBaselineIds({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) async {
    final entries = await loadAckedMapBaselineEntries(
      peerNodeId: peerNodeId,
      mapKeys: mapKeys,
    );
    return {
      for (final entry in entries.entries) entry.key: entry.value.baselineId,
    };
  }

  Future<Map<String, LanSyncAckedMapBaselineEntry>>
      loadAckedMapBaselineEntries({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) async {
    final peerKey = peerNodeId.trim();
    final keys = LanSyncStoreCodec.normalizeNonEmptySet(mapKeys);
    if (peerKey.isEmpty || keys.isEmpty) return const {};

    final prefs = await SharedPreferences.getInstance();
    final all = LanSyncStoreCodec.decodeStoredMap(
      prefs.getString(_ackedMapBaselinesKey),
    );
    final peerMap = LanSyncStoreCodec.toStringKeyMap(all[peerKey]);
    if (peerMap.isEmpty) return const {};

    final result = <String, LanSyncAckedMapBaselineEntry>{};
    for (final mapKey in keys) {
      final entry = peerMap[mapKey];
      if (entry is! Map) continue;
      final baselineId = (entry['baselineId'] as String? ?? '').trim();
      final updatedAtMs = entry['updatedAtMs'] as int? ?? 0;
      if (baselineId.isNotEmpty) {
        result[mapKey] = LanSyncAckedMapBaselineEntry(
          baselineId: baselineId,
          updatedAtMs: updatedAtMs,
        );
      }
    }
    return result;
  }

  Future<bool> hasAckedMapBaselines({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) async {
    final keys = LanSyncStoreCodec.normalizeNonEmptySet(mapKeys);
    if (keys.isEmpty) return false;
    final map = await loadAckedMapBaselineIds(
      peerNodeId: peerNodeId,
      mapKeys: keys,
    );
    return map.length == keys.length;
  }

  Future<void> upsertAckedMapBaselines({
    required String peerNodeId,
    required Iterable<String> mapKeys,
    String? baselineId,
  }) async {
    final peerKey = peerNodeId.trim();
    final keys = LanSyncStoreCodec.normalizeNonEmptySet(mapKeys);
    if (peerKey.isEmpty || keys.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final nextBaselineId =
        (baselineId ?? 'bl_${DateTime.now().microsecondsSinceEpoch}').trim();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await LanSyncStoreCodec.updatePeerScopedMap(
      prefs,
      storageKey: _ackedMapBaselinesKey,
      peerKey: peerKey,
      update: (peerMap) {
        for (final mapKey in keys) {
          peerMap[mapKey] = {
            'baselineId': nextBaselineId,
            'updatedAtMs': nowMs,
          };
        }
      },
    );
  }

  Future<Map<String, Map<String, String>>> loadMapBaselineSnapshots({
    required String peerNodeId,
    required Iterable<String> mapKeys,
    Map<String, String>? expectedBaselineIds,
  }) async {
    final peerKey = peerNodeId.trim();
    final keys = LanSyncStoreCodec.normalizeNonEmptySet(mapKeys);
    if (peerKey.isEmpty || keys.isEmpty) return const {};

    final prefs = await SharedPreferences.getInstance();
    final all = LanSyncStoreCodec.decodeStoredMap(
      prefs.getString(_mapBaselineSnapshotsKey),
    );
    final peerMap = LanSyncStoreCodec.toStringKeyMap(all[peerKey]);
    if (peerMap.isEmpty) return const {};

    final result = <String, Map<String, String>>{};
    for (final mapKey in keys) {
      final entry = LanSyncStoreCodec.toStringKeyMap(peerMap[mapKey]);
      if (entry.isEmpty) continue;

      final expectedBaselineId = (expectedBaselineIds?[mapKey] ?? '').trim();
      if (expectedBaselineId.isNotEmpty) {
        final currentBaselineId = (entry['baselineId'] as String? ?? '').trim();
        if (currentBaselineId != expectedBaselineId) continue;
      }

      final digestsRaw = entry['grenadeDigests'];
      if (digestsRaw is! Map) continue;
      final digests = <String, String>{};
      for (final e in Map<String, dynamic>.from(digestsRaw).entries) {
        final key = e.key.trim();
        final value = (e.value as String? ?? '').trim();
        if (key.isEmpty || value.isEmpty) continue;
        digests[key] = value;
      }
      result[mapKey] = digests;
    }
    return result;
  }

  Future<void> upsertMapBaselineSnapshots({
    required String peerNodeId,
    required Map<String, Map<String, String>> mapDigests,
    required String baselineId,
  }) async {
    final peerKey = peerNodeId.trim();
    final nextBaselineId = baselineId.trim();
    if (peerKey.isEmpty || nextBaselineId.isEmpty || mapDigests.isEmpty) {
      return;
    }

    final normalized = <String, Map<String, String>>{};
    for (final entry in mapDigests.entries) {
      final mapKey = entry.key.trim();
      if (mapKey.isEmpty) continue;
      final digests = <String, String>{};
      for (final digestEntry in entry.value.entries) {
        final uid = digestEntry.key.trim();
        final digest = digestEntry.value.trim();
        if (uid.isEmpty || digest.isEmpty) continue;
        digests[uid] = digest;
      }
      normalized[mapKey] = digests;
    }
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await LanSyncStoreCodec.updatePeerScopedMap(
      prefs,
      storageKey: _mapBaselineSnapshotsKey,
      peerKey: peerKey,
      update: (peerMap) {
        for (final entry in normalized.entries) {
          peerMap[entry.key] = {
            'baselineId': nextBaselineId,
            'updatedAtMs': nowMs,
            'grenadeDigests': entry.value,
          };
        }
      },
    );
  }

  Future<void> upsertGrenadeTombstones(
    Iterable<LanSyncGrenadeTombstoneEntry> tombstones,
  ) async {
    final normalized = <String, LanSyncGrenadeTombstoneEntry>{};
    for (final entry in tombstones) {
      final uniqueId = entry.uniqueId.trim();
      final mapName = entry.mapName.trim();
      if (uniqueId.isEmpty || mapName.isEmpty) continue;
      normalized[uniqueId] = LanSyncGrenadeTombstoneEntry(
        uniqueId: uniqueId,
        mapName: mapName,
        deletedAt: entry.deletedAt,
      );
    }
    if (normalized.isEmpty) return;

    await _upsertTombstoneMap(
      storageKey: _grenadeTombstonesKey,
      entries: {
        for (final entry in normalized.entries) entry.key: entry.value.toJson(),
      },
      maxEntries: _maxGrenadeTombstones,
    );
  }

  Future<Map<String, LanSyncGrenadeTombstoneEntry>> loadGrenadeTombstones({
    Iterable<String>? uniqueIds,
    Iterable<String>? mapKeys,
  }) async {
    final targetIds = uniqueIds == null
        ? null
        : LanSyncStoreCodec.normalizeNonEmptySet(uniqueIds);
    final targetMaps = mapKeys == null
        ? null
        : LanSyncStoreCodec.normalizeNonEmptySet(mapKeys);

    final pruned = await _loadAndPruneTombstoneMap(
      storageKey: _grenadeTombstonesKey,
      maxEntries: _maxGrenadeTombstones,
    );
    if (pruned.isEmpty) return const {};

    try {
      final result = <String, LanSyncGrenadeTombstoneEntry>{};
      for (final rawEntry in pruned.entries) {
        if (rawEntry.value is! Map) continue;
        final entry = LanSyncGrenadeTombstoneEntry.fromJson(
          Map<String, dynamic>.from(rawEntry.value as Map),
        );
        if (entry.uniqueId.isEmpty || entry.mapName.isEmpty) continue;
        if (targetIds != null && !targetIds.contains(entry.uniqueId)) continue;
        if (targetMaps != null && !targetMaps.contains(entry.mapName)) continue;
        result[entry.uniqueId] = entry;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> upsertEntityTombstones(
    Iterable<LanSyncEntityTombstoneEntry> tombstones,
  ) async {
    final normalized = <String, LanSyncEntityTombstoneEntry>{};
    for (final entry in tombstones) {
      final entityType = entry.entityType.trim();
      final entityKey = entry.entityKey.trim();
      final mapName = entry.mapName.trim();
      if (!LanSyncEntityTombstoneType.values.contains(entityType) ||
          entityKey.isEmpty ||
          mapName.isEmpty) {
        continue;
      }
      final key =
          LanSyncStoreCodec.entityTombstoneCompositeKey(entityType, entityKey);
      normalized[key] = LanSyncEntityTombstoneEntry(
        entityType: entityType,
        entityKey: entityKey,
        mapName: mapName,
        deletedAt: entry.deletedAt,
        payload: Map<String, dynamic>.from(entry.payload),
      );
    }
    if (normalized.isEmpty) return;

    await _upsertTombstoneMap(
      storageKey: _entityTombstonesKey,
      entries: {
        for (final entry in normalized.entries) entry.key: entry.value.toJson(),
      },
      maxEntries: _maxEntityTombstones,
    );
  }

  Future<Map<String, LanSyncEntityTombstoneEntry>> loadEntityTombstones({
    Iterable<String>? entityTypes,
    Iterable<String>? entityKeys,
    Iterable<String>? mapKeys,
  }) async {
    final targetTypes = entityTypes
        ?.map((e) => e.trim())
        .where((e) => LanSyncEntityTombstoneType.values.contains(e))
        .toSet();
    final targetKeys = entityKeys == null
        ? null
        : LanSyncStoreCodec.normalizeNonEmptySet(entityKeys);
    final targetMaps = mapKeys == null
        ? null
        : LanSyncStoreCodec.normalizeNonEmptySet(mapKeys);

    final pruned = await _loadAndPruneTombstoneMap(
      storageKey: _entityTombstonesKey,
      maxEntries: _maxEntityTombstones,
    );
    if (pruned.isEmpty) return const {};

    final result = <String, LanSyncEntityTombstoneEntry>{};
    for (final rawEntry in pruned.entries) {
      if (rawEntry.value is! Map) continue;
      final entry = LanSyncEntityTombstoneEntry.fromJson(
        Map<String, dynamic>.from(rawEntry.value as Map),
      );
      if (!LanSyncEntityTombstoneType.values.contains(entry.entityType) ||
          entry.entityKey.isEmpty ||
          entry.mapName.isEmpty) {
        continue;
      }
      if (targetTypes != null && !targetTypes.contains(entry.entityType)) {
        continue;
      }
      if (targetKeys != null && !targetKeys.contains(entry.entityKey)) {
        continue;
      }
      if (targetMaps != null && !targetMaps.contains(entry.mapName)) {
        continue;
      }
      result[rawEntry.key] = entry;
    }
    return result;
  }

  Future<void> cleanupSyncTombstones() async {
    final prefs = await SharedPreferences.getInstance();
    final prunedGrenade = LanSyncStoreCodec.pruneRawTombstoneMap(
      LanSyncStoreCodec.decodeStoredMap(prefs.getString(_grenadeTombstonesKey)),
      maxEntries: _maxGrenadeTombstones,
    );
    final prunedEntity = LanSyncStoreCodec.pruneRawTombstoneMap(
      LanSyncStoreCodec.decodeStoredMap(prefs.getString(_entityTombstonesKey)),
      maxEntries: _maxEntityTombstones,
    );
    await prefs.setString(_grenadeTombstonesKey, jsonEncode(prunedGrenade));
    await prefs.setString(_entityTombstonesKey, jsonEncode(prunedEntity));
  }

  Future<LanSyncTombstoneStats> loadTombstoneStats() async {
    final prefs = await SharedPreferences.getInstance();
    final grenade = LanSyncStoreCodec.pruneRawTombstoneMap(
      LanSyncStoreCodec.decodeStoredMap(prefs.getString(_grenadeTombstonesKey)),
      maxEntries: _maxGrenadeTombstones,
    );
    final entity = LanSyncStoreCodec.pruneRawTombstoneMap(
      LanSyncStoreCodec.decodeStoredMap(prefs.getString(_entityTombstonesKey)),
      maxEntries: _maxEntityTombstones,
    );
    return LanSyncTombstoneStats(
      grenadeCount: grenade.length,
      entityCount: entity.length,
    );
  }

  Future<List<LanSyncBaselineDebugPeerInfo>> loadBaselineDebugPeers() async {
    final prefs = await SharedPreferences.getInstance();
    final ackAll = LanSyncStoreCodec.decodeStoredMap(
      prefs.getString(_ackedMapBaselinesKey),
    );
    final snapshotAll = LanSyncStoreCodec.decodeStoredMap(
      prefs.getString(_mapBaselineSnapshotsKey),
    );

    final peerIds = <String>{
      ...LanSyncStoreCodec.normalizeNonEmptySet(ackAll.keys),
      ...LanSyncStoreCodec.normalizeNonEmptySet(snapshotAll.keys),
    }.toList()
      ..sort();

    final peers = <LanSyncBaselineDebugPeerInfo>[];
    for (final peerId in peerIds) {
      final ackPeer = LanSyncStoreCodec.toStringKeyMap(ackAll[peerId]);
      final snapshotPeer =
          LanSyncStoreCodec.toStringKeyMap(snapshotAll[peerId]);
      final mapKeys = <String>{
        ...LanSyncStoreCodec.normalizeNonEmptySet(ackPeer.keys),
        ...LanSyncStoreCodec.normalizeNonEmptySet(snapshotPeer.keys),
      }.toList()
        ..sort();

      final maps = <LanSyncBaselineDebugMapEntry>[];
      for (final mapKey in mapKeys) {
        final ackEntry = LanSyncStoreCodec.toStringKeyMap(ackPeer[mapKey]);
        final snapshotEntry =
            LanSyncStoreCodec.toStringKeyMap(snapshotPeer[mapKey]);
        final baselineId = (ackEntry['baselineId'] as String? ??
                snapshotEntry['baselineId'] as String? ??
                '')
            .trim();
        final updatedAtMs = math.max(
          ackEntry['updatedAtMs'] as int? ?? 0,
          snapshotEntry['updatedAtMs'] as int? ?? 0,
        );
        final digestsRaw = snapshotEntry['grenadeDigests'];
        maps.add(LanSyncBaselineDebugMapEntry(
          mapKey: mapKey,
          baselineId: baselineId,
          updatedAtMs: updatedAtMs,
          snapshotCount: digestsRaw is Map ? digestsRaw.length : 0,
        ));
      }
      if (maps.isNotEmpty) {
        peers.add(LanSyncBaselineDebugPeerInfo(peerNodeId: peerId, maps: maps));
      }
    }
    return peers;
  }

  Future<void> _upsertTombstoneMap({
    required String storageKey,
    required Map<String, Map<String, dynamic>> entries,
    required int maxEntries,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = LanSyncStoreCodec.decodeStoredMap(prefs.getString(storageKey));
    for (final entry in entries.entries) {
      all[entry.key] = entry.value;
    }
    final pruned = LanSyncStoreCodec.pruneRawTombstoneMap(
      all,
      maxEntries: maxEntries,
    );
    await prefs.setString(storageKey, jsonEncode(pruned));
  }

  Future<Map<String, dynamic>> _loadAndPruneTombstoneMap({
    required String storageKey,
    required int maxEntries,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = LanSyncStoreCodec.decodeStoredMap(prefs.getString(storageKey));
    if (all.isEmpty) return const {};

    final pruned = LanSyncStoreCodec.pruneRawTombstoneMap(
      all,
      maxEntries: maxEntries,
    );
    // 若读取时发现过期或超出容量限制则就地写回压缩后的映射
    if (pruned.length != all.length) {
      await prefs.setString(storageKey, jsonEncode(pruned));
    }
    return pruned;
  }
}
