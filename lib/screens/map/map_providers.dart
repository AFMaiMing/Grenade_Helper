import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../models/grenade_tag.dart';
import '../../providers.dart';

final isEditModeProvider = StateProvider.autoDispose<bool>((ref) => false);
final selectedLayerIndexProvider = StateProvider.autoDispose<int>((ref) => 0);
final selectedTagIdsProvider = StateProvider.autoDispose<Set<int>>((ref) => {});

final grenadeTagRevisionProvider =
    StreamProvider.autoDispose<int>((ref) async* {
  final isar = ref.watch(isarProvider);
  int revision = 0;
  yield revision;
  await for (final _ in isar.grenadeTags.watchLazy()) {
    revision++;
    yield revision;
  }
});

// 选中标签（含区域标签）匹配到的道具 ID，未选标签时为 null
final tagMatchedGrenadeIdsProvider =
    FutureProvider.autoDispose<Set<int>?>((ref) async {
  final isar = ref.watch(isarProvider);
  final selectedTagIds = ref.watch(selectedTagIdsProvider);
  ref.watch(grenadeTagRevisionProvider);
  if (selectedTagIds.isEmpty) return null;
  final matchedGrenadeIds = <int>{};
  for (final tagId in selectedTagIds) {
    final links = await isar.grenadeTags.filter().tagIdEqualTo(tagId).findAll();
    for (final link in links) {
      matchedGrenadeIds.add(link.grenadeId);
    }
  }
  return matchedGrenadeIds;
});

bool passesGrenadeFilter(
  Grenade g,
  Set<int> selectedTypes,
  int teamFilter,
  bool onlyFav,
  Set<int>? tagMatchedIds,
) {
  if (!selectedTypes.contains(g.type)) return false;
  if (teamFilter == TeamType.onlyAll && g.team != TeamType.all) return false;
  if (teamFilter == TeamType.ct && g.team != TeamType.ct) return false;
  if (teamFilter == TeamType.t && g.team != TeamType.t) return false;
  if (onlyFav && !g.isFavorite) return false;
  if (tagMatchedIds != null && !tagMatchedIds.contains(g.id)) return false;
  return true;
}

final mapFilteredGrenadesProvider =
    StreamProvider.autoDispose.family<List<Grenade>, int>((ref, layerId) {
  final isar = ref.watch(isarProvider);
  final teamFilter = ref.watch(teamFilterProvider);
  final onlyFav = ref.watch(onlyFavoritesProvider);
  final selectedTypes = ref.watch(typeFilterProvider);
  final tagMatchedIdsFuture = ref.watch(tagMatchedGrenadeIdsProvider.future);

  return isar.grenades
      .filter()
      .layer((q) => q.idEqualTo(layerId))
      .watch(fireImmediately: true)
      .asyncMap((allGrenades) async {
    final tagMatchedIds = await tagMatchedIdsFuture;
    return allGrenades
        .where((g) => passesGrenadeFilter(
            g, selectedTypes, teamFilter, onlyFav, tagMatchedIds))
        .toList();
  });
});
