import 'data/spawn_points/defusal_active_spawn_points.dart';
import 'data/spawn_points/defusal_reserve_spawn_points.dart';
import 'data/spawn_points/hostage_spawn_points.dart';
import 'data/spawn_points/spawn_point_models.dart';

export 'data/spawn_points/spawn_point_models.dart';

/// 内置地图出生点与人质点坐标总表。
const Map<String, MapSpawnConfig> spawnPointData = {
  ...defusalActiveSpawnPoints,
  ...defusalReserveSpawnPoints,
  ...hostageSpawnPoints,
};
