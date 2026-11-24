import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../models/grenade_tag.dart';
import '../../models/tag.dart';
import '../../providers.dart';
import '../../theme/app_design_system.dart';
import '../../widgets/app_svg_icon.dart';
import '../../widgets/grenade_type_icon.dart';
import '../../widgets/map_icon.dart';
import 'map_markers_and_lines.dart';
import 'map_providers.dart';

class MapCapsuleSurface extends StatelessWidget {
  final double radius;
  final bool useBlur;
  final Widget child;

  const MapCapsuleSurface({
    super.key,
    required this.radius,
    required this.useBlur,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!useBlur) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: child,
      ),
    );
  }
}

class MapAppBarTitle extends StatelessWidget {
  final GameMap gameMap;
  final bool isMobile;
  final List<Grenade> allMapGrenades;
  final Isar isar;
  final ValueChanged<Grenade> onSearchResultSelected;

  const MapAppBarTitle({
    super.key,
    required this.gameMap,
    required this.isMobile,
    required this.allMapGrenades,
    required this.isar,
    required this.onSearchResultSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Hero(
          tag: 'map-icon-${gameMap.id}',
          child: MapIcon(path: gameMap.iconPath, size: 26),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 380,
              ),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      gameMap.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 1,
                      height: 14,
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.28),
                    ),
                    Icon(Icons.search_rounded,
                        color: Theme.of(context).hintColor, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Autocomplete<Grenade>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Grenade>.empty();
                          }
                          final query = textEditingValue.text.toLowerCase();
                          return allMapGrenades.where((g) {
                            if (g.title.toLowerCase().contains(query)) {
                              return true;
                            }
                            final grenadeTags = isar.grenadeTags
                                .filter()
                                .grenadeIdEqualTo(g.id)
                                .findAllSync();
                            for (final gt in grenadeTags) {
                              final tag = isar.tags.getSync(gt.tagId);
                              if (tag != null &&
                                  tag.name.toLowerCase().contains(query)) {
                                return true;
                              }
                            }
                            return false;
                          });
                        },
                        displayStringForOption: (g) => g.title,
                        onSelected: onSearchResultSelected,
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8.0,
                              color: const Color(0xFF2A2D33),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.6,
                                constraints:
                                    const BoxConstraints(maxHeight: 250),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    option.layer.loadSync();
                                    return ListTile(
                                      title: Text(option.title,
                                          style: const TextStyle(
                                              color: Colors.white)),
                                      subtitle: Text(
                                          "${option.layer.value?.name ?? ''} • ${mapTypeName(option.type)}",
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12)),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        fieldViewBuilder: (context, controller, focusNode,
                                onFieldSubmitted) =>
                            TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color),
                          decoration: const InputDecoration(
                            filled: false,
                            hintText: "搜索道具...",
                            hintStyle:
                                TextStyle(color: Colors.grey, fontSize: 13),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MapTopFilterBar extends ConsumerWidget {
  final bool isMobile;
  final bool useLegacyMarkers;
  final bool hasHostageSpawns;
  final VoidCallback onBeforeToggleSpawns;

  const MapTopFilterBar({
    super.key,
    required this.isMobile,
    required this.useLegacyMarkers,
    required this.hasHostageSpawns,
    required this.onBeforeToggleSpawns,
  });

  Widget _buildTypeFilterBtn(
    WidgetRef ref,
    Set<int> selectedTypes,
    int type,
    String label,
    Color activeColor,
  ) {
    final isSelected = selectedTypes.contains(type);
    const unselectedColor = Colors.white38;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final newSet = Set<int>.from(selectedTypes);
        if (isSelected) {
          newSet.remove(type);
        } else {
          newSet.add(type);
        }
        ref.read(typeFilterProvider.notifier).state = newSet;
      },
      child: AnimatedContainer(
        duration: AppMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GrenadeTypeIcon(
              type: type,
              size: useLegacyMarkers ? 15 : 18,
              color: isSelected ? activeColor : unselectedColor,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : unselectedColor,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    WidgetRef ref,
    String label,
    int value,
    int groupValue,
    Color color,
  ) {
    final isSelected = value == groupValue;
    final activeTextColor = value == TeamType.all ? Colors.white : color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(teamFilterProvider.notifier).state = value,
      child: AnimatedContainer(
        duration: AppMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeTextColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? activeTextColor : Colors.white60,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamFilter = ref.watch(teamFilterProvider);
    final onlyFav = ref.watch(onlyFavoritesProvider);
    final selectedTypes = ref.watch(typeFilterProvider);
    final showSpawnPoints = ref.watch(showSpawnPointsProvider);
    final showHostagePoints = ref.watch(showHostagePointsProvider);

    return MapCapsuleSurface(
      radius: 15,
      useBlur: isMobile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: isMobile
              ? Colors.black.withValues(alpha: 0.56)
              : const Color(0xD612151B),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFilterChip(
                            ref, '全部', TeamType.all, teamFilter, Colors.grey),
                        const SizedBox(width: 2),
                        _buildFilterChip(ref, '通用', TeamType.onlyAll,
                            teamFilter, Colors.white),
                        const SizedBox(width: 2),
                        _buildFilterChip(ref, 'CT', TeamType.ct, teamFilter,
                            Colors.blueAccent),
                        const SizedBox(width: 2),
                        _buildFilterChip(
                            ref, 'T', TeamType.t, teamFilter, Colors.amber),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 1,
                          height: 15,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        IconButton(
                          tooltip: '仅显示收藏',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(5),
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => ref
                              .read(onlyFavoritesProvider.notifier)
                              .state = !onlyFav,
                          icon: Icon(
                            onlyFav
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: onlyFav ? Colors.amber : Colors.white60,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: showSpawnPoints ? '隐藏出生点' : '显示出生点',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(5),
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            onBeforeToggleSpawns();
                            ref.read(showSpawnPointsProvider.notifier).state =
                                !showSpawnPoints;
                          },
                          icon: Icon(
                            Icons.my_location_rounded,
                            color: showSpawnPoints
                                ? const Color(0xFFFF1744)
                                : Colors.white60,
                            size: 17,
                          ),
                        ),
                        if (hasHostageSpawns)
                          IconButton(
                            tooltip: showHostagePoints ? '隐藏人质点' : '显示人质点',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(5),
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: () {
                              ref
                                  .read(showHostagePointsProvider.notifier)
                                  .state = !showHostagePoints;
                            },
                            icon: AppSvgIcon(
                              asset: 'assets/icons/ui_hostage.svg',
                              size: 17,
                              color: showHostagePoints
                                  ? const Color(0xFF34D399)
                                  : Colors.white60,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildTypeFilterBtn(ref, selectedTypes, GrenadeType.smoke,
                        '烟', context.appTheme.smoke),
                    const SizedBox(width: 3),
                    _buildTypeFilterBtn(ref, selectedTypes, GrenadeType.flash,
                        '闪', context.appTheme.flash),
                    const SizedBox(width: 3),
                    _buildTypeFilterBtn(ref, selectedTypes, GrenadeType.molotov,
                        '火', context.appTheme.molotov),
                    const SizedBox(width: 3),
                    _buildTypeFilterBtn(ref, selectedTypes, GrenadeType.he, '雷',
                        context.appTheme.he),
                    const SizedBox(width: 3),
                    _buildTypeFilterBtn(ref, selectedTypes,
                        GrenadeType.wallbang, '穿', context.appTheme.wallbang),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MapCornerToolCapsules extends ConsumerWidget {
  final bool isMobile;
  final int layerCount;
  final int layerIndex;
  final bool isImpactMode;
  final bool hasSelectedTags;
  final VoidCallback onToggleImpactMode;
  final VoidCallback onOpenTagFilter;

  const MapCornerToolCapsules({
    super.key,
    required this.isMobile,
    required this.layerCount,
    required this.layerIndex,
    required this.isImpactMode,
    required this.hasSelectedTags,
    required this.onToggleImpactMode,
    required this.onOpenTagFilter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (layerCount > 1) ...[
          MapCapsuleSurface(
            radius: 14,
            useBlur: isMobile,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isMobile
                    ? Colors.black.withValues(alpha: 0.56)
                    : const Color(0xD612151B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '上一层',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: layerIndex < layerCount - 1
                        ? () => ref
                            .read(selectedLayerIndexProvider.notifier)
                            .state++
                        : null,
                    icon: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: layerIndex < layerCount - 1
                          ? Colors.white
                          : Colors.white24,
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'F${layerIndex + 1}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下一层',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: layerIndex > 0
                        ? () => ref
                            .read(selectedLayerIndexProvider.notifier)
                            .state--
                        : null,
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: layerIndex > 0 ? Colors.white : Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        MapCapsuleSurface(
          radius: 14,
          useBlur: isMobile,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: isMobile
                  ? Colors.black.withValues(alpha: 0.56)
                  : const Color(0xD612151B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: isImpactMode ? '切换回投掷点模式' : '开启爆点浏览模式',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  style: IconButton.styleFrom(
                    backgroundColor: isImpactMode
                        ? Colors.redAccent.withValues(alpha: 0.22)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onToggleImpactMode,
                  icon: FaIcon(
                    isImpactMode
                        ? FontAwesomeIcons.crosshairs
                        : FontAwesomeIcons.locationDot,
                    color: isImpactMode ? Colors.redAccent : Colors.white70,
                    size: 16,
                  ),
                ),
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                IconButton(
                  tooltip: '标签筛选',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  style: IconButton.styleFrom(
                    backgroundColor: hasSelectedTags
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.22)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onOpenTagFilter,
                  icon: Icon(
                    Icons.label_outline_rounded,
                    color: hasSelectedTags
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white70,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
