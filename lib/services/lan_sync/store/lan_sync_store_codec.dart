import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地同步存储的 JSON 编解码与墓碑裁剪纯辅助工具
abstract final class LanSyncStoreCodec {
  static const int syncTombstoneRetentionDays = 90;

  static String entityTombstoneCompositeKey(
    String entityType,
    String entityKey,
  ) {
    return '${entityType.trim()}|${entityKey.trim()}';
  }

  static int tombstoneCutoffMs() {
    return DateTime.now()
        .subtract(const Duration(days: syncTombstoneRetentionDays))
        .millisecondsSinceEpoch;
  }

  static Map<String, dynamic> toStringKeyMap(Object? raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static Set<String> normalizeNonEmptySet(Iterable<String>? values) {
    if (values == null) return const {};
    return values.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Map<String, dynamic> decodeStoredMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> decodeStoredObjectList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> pruneRawTombstoneMap(
    Map<String, dynamic> source, {
    required int maxEntries,
  }) {
    final cutoffMs = tombstoneCutoffMs();
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final rawEntry in source.entries) {
      if (rawEntry.value is! Map) continue;
      final value = Map<String, dynamic>.from(rawEntry.value as Map);
      final deletedAt = value['deletedAt'] as int?;
      if (deletedAt == null || deletedAt < cutoffMs) continue;
      entries.add(MapEntry(rawEntry.key, value));
    }
    entries.sort((a, b) =>
        (b.value['deletedAt'] as int).compareTo(a.value['deletedAt'] as int));
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    return {
      for (final entry in entries) entry.key: entry.value,
    };
  }

  static Future<void> updatePeerScopedMap(
    SharedPreferences prefs, {
    required String storageKey,
    required String peerKey,
    required void Function(Map<String, dynamic> peerMap) update,
  }) async {
    final all = decodeStoredMap(prefs.getString(storageKey));
    final peerMap = toStringKeyMap(all[peerKey]);
    update(peerMap);
    all[peerKey] = peerMap;
    await prefs.setString(storageKey, jsonEncode(all));
  }
}
