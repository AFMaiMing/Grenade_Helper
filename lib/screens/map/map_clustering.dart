import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../spawn_point_data.dart';

typedef MapImageBounds = ({
  double width,
  double height,
  double offsetX,
  double offsetY,
});

typedef MapVisibleRatioRect = ({
  double left,
  double top,
  double right,
  double bottom,
});

typedef ImpactEntry = ({GrenadeCluster cluster, MapLayer layer, String name});

typedef SpawnGrenadePartition = ({
  Set<String> occupiedKeys,
  List<Grenade> regularGrenades,
  List<({String key, GrenadeCluster cluster})> spawnEntries,
});

class GrenadeCluster {
  final double xRatio;
  final double yRatio;
  final List<Grenade> grenades;

  GrenadeCluster({
    required this.xRatio,
    required this.yRatio,
    required this.grenades,
  });

  int get primaryType => grenades.first.type;

  int get primaryTeam {
    final hasct = grenades.any((g) => g.team == TeamType.ct);
    final hast = grenades.any((g) => g.team == TeamType.t);
    if (hasct && hast) return TeamType.all;
    if (hasct) return TeamType.ct;
    if (hast) return TeamType.t;
    return TeamType.all;
  }

  bool get hasNewImport => grenades.any((g) => g.isNewImport);
  bool get hasFavorite => grenades.any((g) => g.isFavorite);

  bool get hasMultipleTypes {
    if (grenades.length <= 1) return false;
    final firstType = grenades.first.type;
    return grenades.any((g) => g.type != firstType);
  }
}

List<GrenadeCluster> _clusterGrenadesByPoint(
  List<Grenade> grenades, {
  required double threshold,
  required ({double x, double y})? Function(Grenade grenade) pointOf,
}) {
  if (grenades.isEmpty) return [];

  final points = <({Grenade grenade, double x, double y})>[];
  for (final grenade in grenades) {
    final point = pointOf(grenade);
    if (point == null) continue;
    points.add((grenade: grenade, x: point.x, y: point.y));
  }
  if (points.isEmpty) return [];

  // 阈值为 0 时禁用合并。
  if (threshold <= 0) {
    return points
        .map((p) => GrenadeCluster(
              xRatio: p.x,
              yRatio: p.y,
              grenades: [p.grenade],
            ))
        .toList(growable: false);
  }

  final thresholdSq = threshold * threshold;
  final cellSize = threshold;
  final buckets = <(int, int), List<int>>{};
  final cellXs = List<int>.filled(points.length, 0);
  final cellYs = List<int>.filled(points.length, 0);

  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final cx = (p.x / cellSize).floor();
    final cy = (p.y / cellSize).floor();
    cellXs[i] = cx;
    cellYs[i] = cy;
    buckets.putIfAbsent((cx, cy), () => <int>[]).add(i);
  }

  final active = List<bool>.filled(points.length, true);
  final clusters = <GrenadeCluster>[];

  for (var i = 0; i < points.length; i++) {
    if (!active[i]) continue;

    final seed = points[i];
    active[i] = false;
    final matchedIndices = <int>[i];
    final seedCx = cellXs[i];
    final seedCy = cellYs[i];

    // 只扫描种子点周围 9 个格子中的候选点，避免全量比较。
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final bucket = buckets[(seedCx + dx, seedCy + dy)];
        if (bucket == null) continue;

        for (final j in bucket) {
          if (!active[j]) continue;
          final p = points[j];
          final deltaX = p.x - seed.x;
          final deltaY = p.y - seed.y;
          if ((deltaX * deltaX + deltaY * deltaY) < thresholdSq) {
            active[j] = false;
            matchedIndices.add(j);
          }
        }
      }
    }

    if (matchedIndices.length > 2) {
      matchedIndices.sort();
    }

    var sumX = 0.0;
    var sumY = 0.0;
    final clusterGrenades = <Grenade>[];
    for (final idx in matchedIndices) {
      final p = points[idx];
      sumX += p.x;
      sumY += p.y;
      clusterGrenades.add(p.grenade);
    }

    clusters.add(
      GrenadeCluster(
        xRatio: sumX / matchedIndices.length,
        yRatio: sumY / matchedIndices.length,
        grenades: clusterGrenades,
      ),
    );
  }

  return clusters;
}

List<GrenadeCluster> clusterGrenades(
  List<Grenade> grenades, {
  double threshold = 0.0,
}) {
  return _clusterGrenadesByPoint(
    grenades,
    threshold: threshold,
    pointOf: (g) => (x: g.xRatio, y: g.yRatio),
  );
}

List<GrenadeCluster> clusterGrenadesByImpact(
  List<Grenade> grenades, {
  double threshold = 0.0,
}) {
  return _clusterGrenadesByPoint(
    grenades,
    threshold: threshold,
    pointOf: (g) {
      if (g.type == GrenadeType.wallbang) return null;
      final x = g.impactXRatio;
      final y = g.impactYRatio;
      if (x == null || y == null) return null;
      return (x: x, y: y);
    },
  );
}

bool isSameCluster(GrenadeCluster? c1, GrenadeCluster? c2) {
  if (c1 == null || c2 == null) return false;
  if (c1 == c2) return true;
  if (c1.grenades.isEmpty || c2.grenades.isEmpty) return false;
  return c1.grenades.first.id == c2.grenades.first.id;
}

double computeAdaptiveClusterThreshold({
  required double scale,
  required int grenadeCount,
  required bool highDensityClusterMode,
}) {
  final baseThreshold = scale >= 2.0 ? 0.008 : 0.02;

  if (!highDensityClusterMode) {
    if (grenadeCount >= 3200) return baseThreshold * 3.0;
    if (grenadeCount >= 2000) return baseThreshold * 2.4;
    if (grenadeCount >= 1200) return baseThreshold * 1.9;
    if (grenadeCount >= 700) return baseThreshold * 1.5;
    if (grenadeCount >= 350) return baseThreshold * 1.25;
    if (grenadeCount >= 200) return baseThreshold * 1.12;
    if (grenadeCount >= 100) return baseThreshold * 1.05;
    return baseThreshold;
  }

  if (grenadeCount >= 3200) return baseThreshold * 3.8;
  if (grenadeCount >= 2000) return baseThreshold * 3.0;
  if (grenadeCount >= 1200) return baseThreshold * 2.3;
  if (grenadeCount >= 700) return baseThreshold * 2.0;
  if (grenadeCount >= 350) return baseThreshold * 1.8;
  if (grenadeCount >= 200) return baseThreshold * 1.5;
  if (grenadeCount >= 100) return baseThreshold * 1.3;
  return baseThreshold;
}

bool shouldUseDenseMarkerStyle({
  required int grenadeCount,
  required int clusterCount,
}) {
  return grenadeCount >= 100 || clusterCount >= 100;
}

// 计算 BoxFit.contain 模式下正方形地图在容器内的实际边界
MapImageBounds computeMapImageBounds(
  double containerWidth,
  double containerHeight,
) {
  const double imageAspectRatio = 1.0;
  final double containerAspectRatio = containerWidth / containerHeight;

  if (containerAspectRatio > imageAspectRatio) {
    final imageHeight = containerHeight;
    final imageWidth = containerHeight * imageAspectRatio;
    return (
      width: imageWidth,
      height: imageHeight,
      offsetX: (containerWidth - imageWidth) / 2,
      offsetY: 0.0,
    );
  } else {
    final imageWidth = containerWidth;
    final imageHeight = containerWidth / imageAspectRatio;
    return (
      width: imageWidth,
      height: imageHeight,
      offsetX: 0.0,
      offsetY: (containerHeight - imageHeight) / 2,
    );
  }
}

MapVisibleRatioRect computeVisibleImageRatioRect({
  required BoxConstraints constraints,
  required double scale,
  required Offset position,
  required MapImageBounds imageBounds,
}) {
  final safeScale = scale <= 0 ? 1.0 : scale;
  final viewportCenter =
      Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);

  double screenToChildX(double x) =>
      ((x - viewportCenter.dx - position.dx) / safeScale) + viewportCenter.dx;
  double screenToChildY(double y) =>
      ((y - viewportCenter.dy - position.dy) / safeScale) + viewportCenter.dy;

  final childLeft = screenToChildX(0);
  final childRight = screenToChildX(constraints.maxWidth);
  final childTop = screenToChildY(0);
  final childBottom = screenToChildY(constraints.maxHeight);

  final ratioLeftA = (childLeft - imageBounds.offsetX) / imageBounds.width;
  final ratioRightA = (childRight - imageBounds.offsetX) / imageBounds.width;
  final ratioTopA = (childTop - imageBounds.offsetY) / imageBounds.height;
  final ratioBottomA = (childBottom - imageBounds.offsetY) / imageBounds.height;

  final left = ratioLeftA < ratioRightA ? ratioLeftA : ratioRightA;
  final right = ratioLeftA > ratioRightA ? ratioLeftA : ratioRightA;
  final top = ratioTopA < ratioBottomA ? ratioTopA : ratioBottomA;
  final bottom = ratioTopA > ratioBottomA ? ratioTopA : ratioBottomA;

  return (left: left, top: top, right: right, bottom: bottom);
}

bool isRatioPointVisible(
  double x,
  double y, {
  required MapVisibleRatioRect visibleRect,
  double marginX = 0,
  double marginY = 0,
}) {
  return x >= visibleRect.left - marginX &&
      x <= visibleRect.right + marginX &&
      y >= visibleRect.top - marginY &&
      y <= visibleRect.bottom + marginY;
}

bool isRatioSegmentVisible(
  double x1,
  double y1,
  double x2,
  double y2, {
  required MapVisibleRatioRect visibleRect,
  double marginX = 0,
  double marginY = 0,
}) {
  final minX = x1 < x2 ? x1 : x2;
  final maxX = x1 > x2 ? x1 : x2;
  final minY = y1 < y2 ? y1 : y2;
  final maxY = y1 > y2 ? y1 : y2;

  return !(maxX < visibleRect.left - marginX ||
      minX > visibleRect.right + marginX ||
      maxY < visibleRect.top - marginY ||
      minY > visibleRect.bottom + marginY);
}

List<Map<String, dynamic>> parseImpactStrokes(String? json) {
  if (json == null || json.isEmpty) return [];
  try {
    final parsed = jsonDecode(json) as List;
    return parsed.map((e) => Map<String, dynamic>.from(e)).toList();
  } catch (_) {
    return [];
  }
}

// 按楼层聚合已标记爆点，阈值与地图默认缩放下一致
List<ImpactEntry> groupImpactEntries(
  Isar isar,
  List<({Grenade grenade, MapLayer layer})> entries, {
  required bool highDensityClusterMode,
}) {
  final byLayer = <int, ({MapLayer layer, List<Grenade> grenades})>{};
  for (final e in entries) {
    byLayer
        .putIfAbsent(
          e.layer.id,
          () => (layer: e.layer, grenades: <Grenade>[]),
        )
        .grenades
        .add(e.grenade);
  }
  final clustered = <({GrenadeCluster cluster, MapLayer layer})>[];
  for (final v in byLayer.values) {
    final threshold = computeAdaptiveClusterThreshold(
      scale: 1.0,
      grenadeCount: v.grenades.length,
      highDensityClusterMode: highDensityClusterMode,
    );
    for (final c in clusterGrenadesByImpact(v.grenades, threshold: threshold)) {
      clustered.add((cluster: c, layer: v.layer));
    }
  }
  final groupIds = <int>{
    for (final e in clustered)
      for (final g in e.cluster.grenades)
        if (g.impactGroupId != null) g.impactGroupId!,
  }.toList();
  final groupNames = <int, String>{
    for (final group in isar.impactGroups.getAllSync(groupIds))
      if (group != null) group.id: group.name,
  };
  return clustered.map((e) {
    final names = <String>{
      for (final g in e.cluster.grenades)
        if (groupNames[g.impactGroupId] != null) groupNames[g.impactGroupId]!,
    };
    // 无自定义分组时沿用爆点面板的命名规则
    final name = names.isNotEmpty
        ? names.join('、')
        : (e.cluster.grenades.length == 1
            ? (e.cluster.grenades.first.description ?? '未命名爆点')
            : '未命名爆点');
    return (cluster: e.cluster, layer: e.layer, name: name);
  }).toList();
}

SpawnGrenadePartition partitionSpawnGrenades(
  MapSpawnConfig config,
  List<Grenade> grenades, {
  required bool includeCasual,
}) {
  if (grenades.isEmpty) {
    return (
      occupiedKeys: const {},
      regularGrenades: grenades,
      spawnEntries: const [],
    );
  }

  final candidates = <({String key, SpawnPoint point})>[
    for (final s in config.ctSpawns) (key: 'ct-${s.id}', point: s),
    for (final s in config.tSpawns) (key: 't-${s.id}', point: s),
    if (includeCasual) ...[
      for (final s in config.casualCtSpawns) (key: 'cct-${s.id}', point: s),
      for (final s in config.casualTSpawns) (key: 'ct_c-${s.id}', point: s),
    ],
  ];
  final maxDist = math.min(
    0.0045,
    config.minSpacingRatio(includeCasual: includeCasual) * 0.35,
  );
  final maxDistSq = maxDist * maxDist;

  final byKey = <String, List<Grenade>>{};
  final regular = <Grenade>[];

  for (final g in grenades) {
    String? nearestKey;
    var bestDistSq = maxDistSq;
    for (final c in candidates) {
      final dx = g.xRatio - c.point.x;
      final dy = g.yRatio - c.point.y;
      final distSq = dx * dx + dy * dy;
      if (distSq <= bestDistSq) {
        bestDistSq = distSq;
        nearestKey = c.key;
      }
    }
    if (nearestKey != null) {
      (byKey[nearestKey] ??= <Grenade>[]).add(g);
    } else {
      regular.add(g);
    }
  }

  if (byKey.isEmpty) {
    return (
      occupiedKeys: const {},
      regularGrenades: grenades,
      spawnEntries: const [],
    );
  }

  final spawnEntries = <({String key, GrenadeCluster cluster})>[];
  for (final c in candidates) {
    final matched = byKey[c.key];
    if (matched != null) {
      spawnEntries.add((
        key: c.key,
        cluster: GrenadeCluster(
          xRatio: c.point.x,
          yRatio: c.point.y,
          grenades: matched,
        ),
      ));
    }
  }

  return (
    occupiedKeys: byKey.keys.toSet(),
    regularGrenades: regular,
    spawnEntries: spawnEntries,
  );
}
