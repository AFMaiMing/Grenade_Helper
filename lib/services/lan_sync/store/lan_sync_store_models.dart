DateTime _parseStoredDate(Object? raw, {DateTime? fallback}) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
  }
  return fallback ?? DateTime.now();
}

/// 局域网同步已配对或常用节点记录
class LanSyncPeerEntry {
  final String id;
  final String name;
  final String host;
  final int port;
  final String peerId;
  final String sharedSecret;
  final bool isPaired;
  final String remoteDeviceName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final String note;

  const LanSyncPeerEntry({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.peerId = '',
    this.sharedSecret = '',
    this.isPaired = false,
    this.remoteDeviceName = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.note = '',
  });

  LanSyncPeerEntry copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? peerId,
    String? sharedSecret,
    bool? isPaired,
    String? remoteDeviceName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    bool clearLastUsedAt = false,
    String? note,
  }) {
    return LanSyncPeerEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      peerId: peerId ?? this.peerId,
      sharedSecret: sharedSecret ?? this.sharedSecret,
      isPaired: isPaired ?? this.isPaired,
      remoteDeviceName: remoteDeviceName ?? this.remoteDeviceName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: clearLastUsedAt ? null : (lastUsedAt ?? this.lastUsedAt),
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'peerId': peerId,
        'sharedSecret': sharedSecret,
        'isPaired': isPaired,
        'remoteDeviceName': remoteDeviceName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'note': note,
      };

  factory LanSyncPeerEntry.fromJson(Map<String, dynamic> json) {
    final lastUsedRaw = json['lastUsedAt'] as String?;
    return LanSyncPeerEntry(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      host: (json['host'] as String? ?? '').trim(),
      port: json['port'] as int? ?? 39527,
      peerId: (json['peerId'] as String? ?? '').trim(),
      sharedSecret: (json['sharedSecret'] as String? ?? '').trim(),
      isPaired: json['isPaired'] as bool? ?? false,
      remoteDeviceName: (json['remoteDeviceName'] as String? ?? '').trim(),
      createdAt: _parseStoredDate(json['createdAt']),
      updatedAt: _parseStoredDate(json['updatedAt']),
      lastUsedAt: lastUsedRaw != null ? DateTime.tryParse(lastUsedRaw) : null,
      note: (json['note'] as String? ?? '').trim(),
    );
  }
}

/// 局域网同步操作历史日志条目
class LanSyncHistoryEntry {
  final String id;
  final String category;
  final String title;
  final String detail;
  final bool success;
  final DateTime createdAt;

  const LanSyncHistoryEntry({
    required this.id,
    required this.category,
    required this.title,
    required this.detail,
    required this.success,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'detail': detail,
        'success': success,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LanSyncHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LanSyncHistoryEntry(
      id: (json['id'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? 'system').trim(),
      title: (json['title'] as String? ?? '').trim(),
      detail: (json['detail'] as String? ?? '').trim(),
      success: json['success'] as bool? ?? true,
      createdAt: _parseStoredDate(json['createdAt']),
    );
  }
}

/// 道具删除墓碑条目
class LanSyncGrenadeTombstoneEntry {
  final String uniqueId;
  final String mapName;
  final int deletedAt;

  const LanSyncGrenadeTombstoneEntry({
    required this.uniqueId,
    required this.mapName,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'uniqueId': uniqueId,
        'mapName': mapName,
        'deletedAt': deletedAt,
      };

  factory LanSyncGrenadeTombstoneEntry.fromJson(Map<String, dynamic> json) {
    return LanSyncGrenadeTombstoneEntry(
      uniqueId: (json['uniqueId'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      deletedAt:
          json['deletedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 实体墓碑支持的实体类型常量集合
class LanSyncEntityTombstoneType {
  static const String tag = 'tag';
  static const String area = 'area';
  static const String favoriteFolder = 'favoriteFolder';
  static const String impactGroup = 'impactGroup';

  static const Set<String> values = {
    tag,
    area,
    favoriteFolder,
    impactGroup,
  };
}

/// 非道具实体的删除墓碑条目
class LanSyncEntityTombstoneEntry {
  final String entityType;
  final String entityKey;
  final String mapName;
  final int deletedAt;
  final Map<String, dynamic> payload;

  const LanSyncEntityTombstoneEntry({
    required this.entityType,
    required this.entityKey,
    required this.mapName,
    required this.deletedAt,
    this.payload = const {},
  });

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'entityKey': entityKey,
        'mapName': mapName,
        'deletedAt': deletedAt,
        'payload': payload,
      };

  factory LanSyncEntityTombstoneEntry.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return LanSyncEntityTombstoneEntry(
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
}

/// 已确认的地图同步基线条目
class LanSyncAckedMapBaselineEntry {
  final String baselineId;
  final int updatedAtMs;

  const LanSyncAckedMapBaselineEntry({
    required this.baselineId,
    required this.updatedAtMs,
  });
}

/// 基线调试面板展示的地图基线快照摘要
class LanSyncBaselineDebugMapEntry {
  final String mapKey;
  final String baselineId;
  final int updatedAtMs;
  final int snapshotCount;

  const LanSyncBaselineDebugMapEntry({
    required this.mapKey,
    required this.baselineId,
    required this.updatedAtMs,
    required this.snapshotCount,
  });
}

/// 基线调试面板按对端节点聚合的地图信息
class LanSyncBaselineDebugPeerInfo {
  final String peerNodeId;
  final List<LanSyncBaselineDebugMapEntry> maps;

  const LanSyncBaselineDebugPeerInfo({
    required this.peerNodeId,
    required this.maps,
  });
}

/// 墓碑数量统计摘要
class LanSyncTombstoneStats {
  final int grenadeCount;
  final int entityCount;

  const LanSyncTombstoneStats({
    required this.grenadeCount,
    required this.entityCount,
  });
}
