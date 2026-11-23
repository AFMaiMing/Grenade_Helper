import 'package:flutter/foundation.dart';

import '../models.dart';
import '../services/settings_service.dart';

List<T> _decodeJsonList<T>(
  Object? raw,
  T Function(Map<String, dynamic> json) fromJson,
) {
  final items = raw as List<dynamic>? ?? const <dynamic>[];
  return List<T>.unmodifiable(
    items.map((e) => fromJson(Map<String, dynamic>.from(e as Map))),
  );
}

@immutable
class OverlayMediaItem {
  final String localPath;
  final int type;
  final int sortOrder;

  const OverlayMediaItem({
    required this.localPath,
    required this.type,
    required this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
        'localPath': localPath,
        'type': type,
        'sortOrder': sortOrder,
      };

  factory OverlayMediaItem.fromJson(Map<String, dynamic> json) {
    return OverlayMediaItem(
      localPath: json['localPath'] as String? ?? '',
      type: (json['type'] as num?)?.toInt() ?? MediaType.image,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class OverlayStepItem {
  final int stepIndex;
  final String title;
  final String description;
  final List<OverlayMediaItem> medias;

  const OverlayStepItem({
    required this.stepIndex,
    required this.title,
    required this.description,
    required this.medias,
  });

  Map<String, dynamic> toJson() => {
        'stepIndex': stepIndex,
        'title': title,
        'description': description,
        'medias': medias.map((m) => m.toJson()).toList(),
      };

  factory OverlayStepItem.fromJson(Map<String, dynamic> json) {
    return OverlayStepItem(
      stepIndex: (json['stepIndex'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      medias: _decodeJsonList(json['medias'], OverlayMediaItem.fromJson),
    );
  }
}

@immutable
class OverlayGrenadeItem {
  final int id;
  final String title;
  final int type;
  final double xRatio;
  final double yRatio;
  final List<OverlayStepItem> steps;

  const OverlayGrenadeItem({
    required this.id,
    required this.title,
    required this.type,
    required this.xRatio,
    required this.yRatio,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'xRatio': xRatio,
        'yRatio': yRatio,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory OverlayGrenadeItem.fromJson(Map<String, dynamic> json) {
    return OverlayGrenadeItem(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '',
      type: (json['type'] as num?)?.toInt() ?? GrenadeType.smoke,
      xRatio: (json['xRatio'] as num).toDouble(),
      yRatio: (json['yRatio'] as num).toDouble(),
      steps: _decodeJsonList(json['steps'], OverlayStepItem.fromJson),
    );
  }
}

/// 供悬浮窗独立进程消费的不可变地图快照
@immutable
class OverlayMapSnapshot {
  final int mapId;
  final String mapName;
  final int layerId;
  final String layerAssetPath;
  final List<OverlayGrenadeItem> grenades;

  const OverlayMapSnapshot({
    required this.mapId,
    required this.mapName,
    required this.layerId,
    required this.layerAssetPath,
    required this.grenades,
  });

  /// 同步加载指定图层的道具、步骤与媒体生成快照
  static OverlayMapSnapshot fromIsar(GameMap map, MapLayer layer) {
    layer.grenades.loadSync();
    final grenadeItems = List<OverlayGrenadeItem>.unmodifiable(
      layer.grenades.map(_grenadeFromIsar),
    );
    return OverlayMapSnapshot(
      mapId: map.id,
      mapName: map.name,
      layerId: layer.id,
      layerAssetPath: layer.assetPath,
      grenades: grenadeItems,
    );
  }

  static OverlayGrenadeItem _grenadeFromIsar(Grenade grenade) {
    grenade.steps.loadSync();
    final sortedSteps = grenade.steps.toList()
      ..sort((a, b) => a.stepIndex.compareTo(b.stepIndex));
    return OverlayGrenadeItem(
      id: grenade.id,
      title: grenade.title,
      type: grenade.type,
      xRatio: grenade.xRatio,
      yRatio: grenade.yRatio,
      steps: List<OverlayStepItem>.unmodifiable(sortedSteps.map(_stepFromIsar)),
    );
  }

  static OverlayStepItem _stepFromIsar(GrenadeStep step) {
    step.medias.loadSync();
    final sortedMedias = step.medias.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return OverlayStepItem(
      stepIndex: step.stepIndex,
      title: step.title,
      description: step.description,
      medias: List<OverlayMediaItem>.unmodifiable(
        sortedMedias.map(
          (m) => OverlayMediaItem(
            localPath: m.localPath,
            type: m.type,
            sortOrder: m.sortOrder,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'mapId': mapId,
        'mapName': mapName,
        'layerId': layerId,
        'layerAssetPath': layerAssetPath,
        'grenades': grenades.map((g) => g.toJson()).toList(),
      };

  factory OverlayMapSnapshot.fromJson(Map<String, dynamic> json) {
    return OverlayMapSnapshot(
      mapId: (json['mapId'] as num).toInt(),
      mapName: json['mapName'] as String? ?? '',
      layerId: (json['layerId'] as num).toInt(),
      layerAssetPath: json['layerAssetPath'] as String? ?? '',
      grenades: _decodeJsonList(json['grenades'], OverlayGrenadeItem.fromJson),
    );
  }
}

/// 悬浮窗启动 IPC 握手初始化配置
@immutable
class OverlayInitConfig {
  final double x;
  final double y;
  final int sizeIndex;
  final double opacity;
  final int navSpeedLevel;
  final bool useLegacyIcons;
  final Map<HotkeyAction, HotkeyConfig> hotkeys;
  final OverlayMapSnapshot? mapSnapshot;

  const OverlayInitConfig({
    required this.x,
    required this.y,
    required this.sizeIndex,
    required this.opacity,
    required this.navSpeedLevel,
    required this.useLegacyIcons,
    required this.hotkeys,
    required this.mapSnapshot,
  });

  static Map<String, dynamic> encodeHotkeys(
    Map<HotkeyAction, HotkeyConfig> hotkeys,
  ) {
    return {
      for (final entry in hotkeys.entries) entry.key.name: entry.value.toJson(),
    };
  }

  static Map<HotkeyAction, HotkeyConfig> decodeHotkeys(
    Map<dynamic, dynamic>? raw,
  ) {
    if (raw == null) return const {};
    final result = <HotkeyAction, HotkeyConfig>{};
    for (final action in HotkeyAction.values) {
      final entry = raw[action.name];
      if (entry is Map) {
        result[action] = HotkeyConfig.fromJson(
          Map<String, dynamic>.from(entry),
        );
      }
    }
    return Map<HotkeyAction, HotkeyConfig>.unmodifiable(result);
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'sizeIndex': sizeIndex,
        'opacity': opacity,
        'navSpeedLevel': navSpeedLevel,
        'useLegacyIcons': useLegacyIcons,
        'hotkeys': encodeHotkeys(hotkeys),
        'mapSnapshot': mapSnapshot?.toJson(),
      };

  factory OverlayInitConfig.fromJson(Map<String, dynamic> json) {
    final rawSnapshot = json['mapSnapshot'];
    return OverlayInitConfig(
      x: (json['x'] as num?)?.toDouble() ?? 100.0,
      y: (json['y'] as num?)?.toDouble() ?? 100.0,
      sizeIndex: (json['sizeIndex'] as num?)?.toInt() ?? 1,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.9,
      navSpeedLevel: (json['navSpeedLevel'] as num?)?.toInt() ?? 3,
      useLegacyIcons: json['useLegacyIcons'] as bool? ?? false,
      hotkeys: decodeHotkeys(json['hotkeys'] as Map?),
      mapSnapshot: rawSnapshot is Map
          ? OverlayMapSnapshot.fromJson(Map<String, dynamic>.from(rawSnapshot))
          : null,
    );
  }
}
