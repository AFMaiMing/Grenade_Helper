import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:isar_community/isar.dart';
import 'models.dart';

/// 全局 Isar 实例，须在根 ProviderScope 中覆盖注入
final isarProvider = Provider<Isar>((ref) => throw UnimplementedError());

final themeModeProvider = StateProvider<int>((ref) => 2);

/// 将持久化主题编号转换为 Flutter ThemeMode
ThemeMode intToThemeMode(int value) => switch (value) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };

final teamFilterProvider =
    StateProvider.autoDispose<int>((ref) => TeamType.all);
final onlyFavoritesProvider = StateProvider.autoDispose<bool>((ref) => false);
final typeFilterProvider = StateProvider.autoDispose<Set<int>>((ref) => <int>{
      GrenadeType.smoke,
      GrenadeType.flash,
      GrenadeType.molotov,
      GrenadeType.he,
      GrenadeType.wallbang,
    });

final showSpawnPointsProvider = StateProvider.autoDispose<bool>((ref) => false);
final showCasualSpawnPointsProvider =
    StateProvider.autoDispose<bool>((ref) => false);
final showHostagePointsProvider =
    StateProvider.autoDispose<bool>((ref) => false);

final mapLineColorProvider = StateProvider<int>((ref) => 0xFFE040FB);
final mapLineOpacityProvider = StateProvider<double>((ref) => 0.6);
final impactAreaOpacityProvider = StateProvider<double>((ref) => 0.4);

/// 监听指定楼层的原始道具列表数据流
final _rawLayerGrenadesProvider =
    StreamProvider.autoDispose.family<List<Grenade>, int>((ref, layerId) {
  final isar = ref.watch(isarProvider);
  return isar.grenades
      .filter()
      .layer((q) => q.idEqualTo(layerId))
      .watch(fireImmediately: true);
});

bool _matchesGrenadeFilter(
  Grenade grenade, {
  required int teamFilter,
  required bool onlyFavorites,
  required Set<int> selectedTypes,
}) {
  if (!selectedTypes.contains(grenade.type)) return false;
  if (onlyFavorites && !grenade.isFavorite) return false;
  return switch (teamFilter) {
    TeamType.onlyAll => grenade.team == TeamType.all,
    TeamType.ct => grenade.team == TeamType.ct,
    TeamType.t => grenade.team == TeamType.t,
    _ => true,
  };
}

/// 根据当前筛选状态对指定楼层道具列表执行响应式内存过滤
final filteredGrenadesProvider =
    Provider.autoDispose.family<AsyncValue<List<Grenade>>, int>((ref, layerId) {
  final rawAsync = ref.watch(_rawLayerGrenadesProvider(layerId));
  final teamFilter = ref.watch(teamFilterProvider);
  final onlyFavorites = ref.watch(onlyFavoritesProvider);
  final selectedTypes = ref.watch(typeFilterProvider);

  return rawAsync.whenData(
    (allGrenades) => allGrenades
        .where(
          (g) => _matchesGrenadeFilter(
            g,
            teamFilter: teamFilter,
            onlyFavorites: onlyFavorites,
            selectedTypes: selectedTypes,
          ),
        )
        .toList(),
  );
});
