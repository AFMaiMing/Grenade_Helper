import 'dart:math' as math;

/// 单个出生点或人质点的归一化地图坐标。
class SpawnPoint {
  final int id;
  final double x;
  final double y;

  const SpawnPoint(this.id, this.x, this.y);
}

final Map<(MapSpawnConfig, bool), double> _minSpawnSpacingCache = {};

/// 地图出生点与人质点配置，提供点位分组及最小间距比率计算。
class MapSpawnConfig {
  final List<SpawnPoint> ctSpawns;
  final List<SpawnPoint> tSpawns;
  final List<SpawnPoint> casualCtSpawns;
  final List<SpawnPoint> casualTSpawns;
  final List<SpawnPoint> hostageSpawns;

  const MapSpawnConfig({
    required this.ctSpawns,
    required this.tSpawns,
    this.casualCtSpawns = const [],
    this.casualTSpawns = const [],
    this.hostageSpawns = const [],
  });

  bool get hasCasualSpawns =>
      casualCtSpawns.isNotEmpty || casualTSpawns.isNotEmpty;
  bool get hasHostageSpawns => hostageSpawns.isNotEmpty;

  double minSpacingRatio({bool includeCasual = false}) {
    final key = (this, includeCasual);
    final cached = _minSpawnSpacingCache[key];
    if (cached != null) return cached;

    final points = <SpawnPoint>[
      ...ctSpawns,
      ...tSpawns,
      if (includeCasual) ...casualCtSpawns,
      if (includeCasual) ...casualTSpawns,
    ];
    var minDist = 0.05;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dx = points[i].x - points[j].x;
        final dy = points[i].y - points[j].y;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > 0.002 && d < minDist) {
          minDist = d;
        }
      }
    }
    _minSpawnSpacingCache[key] = minDist;
    return minDist;
  }
}
