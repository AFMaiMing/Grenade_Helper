import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'store/lan_sync_store_codec.dart';
import 'store/lan_sync_store_models.dart';
import 'store/lan_sync_tombstone_baseline_store.dart';

export 'store/lan_sync_store_models.dart'
    show
        LanSyncAckedMapBaselineEntry,
        LanSyncBaselineDebugMapEntry,
        LanSyncBaselineDebugPeerInfo,
        LanSyncEntityTombstoneEntry,
        LanSyncEntityTombstoneType,
        LanSyncGrenadeTombstoneEntry,
        LanSyncHistoryEntry,
        LanSyncPeerEntry,
        LanSyncTombstoneStats;

/// 局域网同步本地持久化存储门面
class LanSyncLocalStore {
  static const _peersKey = 'lan_sync_peers_v1';
  static const _historyKey = 'lan_sync_history_v1';
  static const _stableNodeIdKey = 'lan_sync_stable_node_id_v1';
  static const _receiveSilentImportEnabledKey =
      'lan_sync_receive_silent_import_enabled_v1';
  static const _historyLimit = 120;

  final LanSyncTombstoneBaselineStore _tombstoneBaselineStore =
      const LanSyncTombstoneBaselineStore();

  Future<String> loadOrCreateStableNodeId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(_stableNodeIdKey) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final created = 'node_${const Uuid().v4()}';
    await prefs.setString(_stableNodeIdKey, created);
    return created;
  }

  Future<void> cleanupLegacySyncState() =>
      _tombstoneBaselineStore.cleanupLegacySyncState();

  Future<Map<String, String>> loadAckedMapBaselineIds({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) =>
      _tombstoneBaselineStore.loadAckedMapBaselineIds(
        peerNodeId: peerNodeId,
        mapKeys: mapKeys,
      );

  Future<Map<String, LanSyncAckedMapBaselineEntry>>
      loadAckedMapBaselineEntries({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) =>
          _tombstoneBaselineStore.loadAckedMapBaselineEntries(
            peerNodeId: peerNodeId,
            mapKeys: mapKeys,
          );

  Future<bool> hasAckedMapBaselines({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) =>
      _tombstoneBaselineStore.hasAckedMapBaselines(
        peerNodeId: peerNodeId,
        mapKeys: mapKeys,
      );

  Future<void> upsertAckedMapBaselines({
    required String peerNodeId,
    required Iterable<String> mapKeys,
    String? baselineId,
  }) =>
      _tombstoneBaselineStore.upsertAckedMapBaselines(
        peerNodeId: peerNodeId,
        mapKeys: mapKeys,
        baselineId: baselineId,
      );

  Future<Map<String, Map<String, String>>> loadMapBaselineSnapshots({
    required String peerNodeId,
    required Iterable<String> mapKeys,
    Map<String, String>? expectedBaselineIds,
  }) =>
      _tombstoneBaselineStore.loadMapBaselineSnapshots(
        peerNodeId: peerNodeId,
        mapKeys: mapKeys,
        expectedBaselineIds: expectedBaselineIds,
      );

  Future<void> upsertMapBaselineSnapshots({
    required String peerNodeId,
    required Map<String, Map<String, String>> mapDigests,
    required String baselineId,
  }) =>
      _tombstoneBaselineStore.upsertMapBaselineSnapshots(
        peerNodeId: peerNodeId,
        mapDigests: mapDigests,
        baselineId: baselineId,
      );

  Future<void> upsertGrenadeTombstones(
    Iterable<LanSyncGrenadeTombstoneEntry> tombstones,
  ) =>
      _tombstoneBaselineStore.upsertGrenadeTombstones(tombstones);

  Future<Map<String, LanSyncGrenadeTombstoneEntry>> loadGrenadeTombstones({
    Iterable<String>? uniqueIds,
    Iterable<String>? mapKeys,
  }) =>
      _tombstoneBaselineStore.loadGrenadeTombstones(
        uniqueIds: uniqueIds,
        mapKeys: mapKeys,
      );

  Future<void> upsertEntityTombstones(
    Iterable<LanSyncEntityTombstoneEntry> tombstones,
  ) =>
      _tombstoneBaselineStore.upsertEntityTombstones(tombstones);

  Future<Map<String, LanSyncEntityTombstoneEntry>> loadEntityTombstones({
    Iterable<String>? entityTypes,
    Iterable<String>? entityKeys,
    Iterable<String>? mapKeys,
  }) =>
      _tombstoneBaselineStore.loadEntityTombstones(
        entityTypes: entityTypes,
        entityKeys: entityKeys,
        mapKeys: mapKeys,
      );

  Future<void> cleanupSyncTombstones() =>
      _tombstoneBaselineStore.cleanupSyncTombstones();

  Future<LanSyncTombstoneStats> loadTombstoneStats() =>
      _tombstoneBaselineStore.loadTombstoneStats();

  Future<List<LanSyncBaselineDebugPeerInfo>> loadBaselineDebugPeers() =>
      _tombstoneBaselineStore.loadBaselineDebugPeers();

  Future<List<LanSyncPeerEntry>> loadPeers() async {
    final prefs = await SharedPreferences.getInstance();
    final peers = LanSyncStoreCodec.decodeStoredObjectList(
      prefs.getString(_peersKey),
    )
        .map(LanSyncPeerEntry.fromJson)
        .where((e) => e.id.isNotEmpty && e.host.isNotEmpty)
        .toList();
    peers.sort((a, b) {
      final aUsed = a.lastUsedAt ?? a.updatedAt;
      final bUsed = b.lastUsedAt ?? b.updatedAt;
      return bUsed.compareTo(aUsed);
    });
    return peers;
  }

  Future<void> savePeers(List<LanSyncPeerEntry> peers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _peersKey,
      jsonEncode(peers.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<List<LanSyncHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final logs = LanSyncStoreCodec.decodeStoredObjectList(
      prefs.getString(_historyKey),
    ).map(LanSyncHistoryEntry.fromJson).where((e) => e.id.isNotEmpty).toList();
    logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return logs;
  }

  Future<List<LanSyncHistoryEntry>> appendHistory(
    LanSyncHistoryEntry entry,
  ) async {
    final current = await loadHistory();
    final next = [entry, ...current];
    if (next.length > _historyLimit) {
      next.removeRange(_historyLimit, next.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(next.map((e) => e.toJson()).toList(growable: false)),
    );
    return next;
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<bool> loadReceiveSilentImportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_receiveSilentImportEnabledKey) ?? false;
  }

  Future<void> saveReceiveSilentImportEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_receiveSilentImportEnabledKey, enabled);
  }
}
