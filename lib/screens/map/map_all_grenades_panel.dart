import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';

import '../../main.dart';
import '../../models.dart';
import '../../widgets/grenade_type_icon.dart';
import 'map_clustering.dart';
import 'map_markers_and_lines.dart';

class MapAllGrenadesPanel extends StatelessWidget {
  static const double collapsedHeight = 60;
  static const double defaultHeight = 260;
  static const double minExpandedHeight = 180;

  final Isar isar;
  final List<({Grenade grenade, MapLayer layer})> entries;
  final bool isEditMode;
  final int currentLayerId;
  final bool isImpactMode;
  final bool useLegacyMarkers;
  final ValueNotifier<double> panelHeightNotifier;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchQueryChanged;
  final VoidCallback onToggleCollapsed;
  final void Function(double deltaDy, double maxHeight) onResize;
  final ValueChanged<double> onSnapHeight;
  final void Function(Grenade grenade, MapLayer layer) onTapGrenade;
  final Future<void> Function(Grenade grenade) onDeleteGrenade;
  final void Function(GrenadeCluster cluster, MapLayer layer)
      onTapImpactCluster;

  const MapAllGrenadesPanel({
    super.key,
    required this.isar,
    required this.entries,
    required this.isEditMode,
    required this.currentLayerId,
    required this.isImpactMode,
    required this.useLegacyMarkers,
    required this.panelHeightNotifier,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchQueryChanged,
    required this.onToggleCollapsed,
    required this.onResize,
    required this.onSnapHeight,
    required this.onTapGrenade,
    required this.onDeleteGrenade,
    required this.onTapImpactCluster,
  });

  Widget _buildImpactEntryList(
    BuildContext context,
    List<ImpactEntry> allEntries,
    List<ImpactEntry> filteredEntries,
  ) {
    if (allEntries.isEmpty) {
      return const Center(
        child: Text('当前地图暂无已标记爆点', style: TextStyle(color: Colors.grey)),
      );
    }
    if (filteredEntries.isEmpty) {
      return const Center(
        child: Text('没有匹配的爆点', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: filteredEntries.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
      ),
      itemBuilder: (context, index) {
        final entry = filteredEntries[index];
        final cluster = entry.cluster;
        final layer = entry.layer;
        final count = cluster.grenades.length;
        final color =
            count > 1 ? Colors.purpleAccent : mapTypeColor(cluster.primaryType);
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          tileColor: layer.id == currentLayerId
              ? Colors.blueAccent.withValues(alpha: 0.08)
              : null,
          leading: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.8),
            ),
            child: GrenadeTypeIcon(
              type: cluster.primaryType,
              size: useLegacyMarkers ? 14 : 18,
              color: color,
            ),
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          subtitle: Text(
            '${layer.name} • $count 个道具',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cluster.hasFavorite)
                const Icon(Icons.star, color: Colors.amber, size: 14),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 16),
            ],
          ),
          onTap: () => onTapImpactCluster(cluster, layer),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxPanelHeight =
        ((MediaQuery.of(context).size.height * 0.65).clamp(240.0, 560.0) as num)
            .toDouble();
    final query = searchQuery.trim().toLowerCase();
    final sortedEntries = [...entries]..sort((a, b) {
        final layerCompare = a.layer.name.compareTo(b.layer.name);
        if (layerCompare != 0) return layerCompare;
        return a.grenade.title.compareTo(b.grenade.title);
      });
    final filteredEntries = query.isEmpty
        ? sortedEntries
        : sortedEntries.where((entry) {
            final g = entry.grenade;
            return g.title.toLowerCase().contains(query);
          }).toList();
    final highDensityClusterMode =
        globalSettingsService?.getHighDensityClusterMode() ?? true;
    final impactEntries = isImpactMode
        ? groupImpactEntries(
            isar,
            sortedEntries,
            highDensityClusterMode: highDensityClusterMode,
          )
        : const <ImpactEntry>[];
    final filteredImpactEntries = query.isEmpty
        ? impactEntries
        : impactEntries
            .where((e) =>
                e.name.toLowerCase().contains(query) ||
                e.cluster.grenades
                    .any((g) => g.title.toLowerCase().contains(query)))
            .toList();
    final totalCount =
        isImpactMode ? impactEntries.length : sortedEntries.length;
    final shownCount =
        isImpactMode ? filteredImpactEntries.length : filteredEntries.length;
    final listTitle = isImpactMode ? '地图爆点列表' : '地图道具列表';

    return ValueListenableBuilder<double>(
      valueListenable: panelHeightNotifier,
      builder: (context, rawPanelHeight, _) {
        final panelHeight = (rawPanelHeight as num)
            .clamp(collapsedHeight, maxPanelHeight)
            .toDouble();
        final showExpandedContent = panelHeight >= minExpandedHeight;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: panelHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) =>
                    onResize(details.delta.dy, maxPanelHeight),
                onVerticalDragEnd: (_) => onSnapHeight(maxPanelHeight),
                child: Column(
                  children: [
                    SizedBox(height: showExpandedContent ? 6 : 4),
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: showExpandedContent ? 8 : 4,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.list_alt,
                              color: Colors.blueAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              showExpandedContent
                                  ? '$listTitle（$shownCount/$totalCount）'
                                  : '$listTitle（$totalCount）',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (showExpandedContent)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                isImpactMode
                                    ? '点击定位爆点'
                                    : (isEditMode ? '点击编辑，右侧可删' : '点击查看'),
                                style: TextStyle(
                                  color: Theme.of(context).hintColor,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: showExpandedContent ? '折叠列表' : '展开列表',
                            onPressed: onToggleCollapsed,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: Icon(
                              showExpandedContent
                                  ? Icons.expand_more
                                  : Icons.expand_less,
                              color: Colors.blueAccent,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (showExpandedContent)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchQueryChanged,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isImpactMode ? '搜索分组或道具名称' : '搜索道具名称',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      suffixIcon: searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空搜索',
                              icon: const Icon(Icons.close, size: 14),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: () {
                                searchController.clear();
                                onSearchQueryChanged('');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              if (showExpandedContent)
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              if (showExpandedContent)
                Expanded(
                  child: isImpactMode
                      ? _buildImpactEntryList(
                          context, impactEntries, filteredImpactEntries)
                      : sortedEntries.isEmpty
                          ? const Center(
                              child: Text(
                                '当前地图暂无道具',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : filteredEntries.isEmpty
                              ? const Center(
                                  child: Text(
                                    '没有匹配的道具',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: filteredEntries.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: Theme.of(context)
                                        .dividerColor
                                        .withValues(alpha: 0.12),
                                  ),
                                  itemBuilder: (context, index) {
                                    final entry = filteredEntries[index];
                                    final g = entry.grenade;
                                    final layer = entry.layer;
                                    final isCurrentLayer =
                                        layer.id == currentLayerId;
                                    final typeColor = mapTypeColor(g.type);

                                    return ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      tileColor: isCurrentLayer
                                          ? Colors.blueAccent
                                              .withValues(alpha: 0.08)
                                          : null,
                                      leading: Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: typeColor, width: 1.8),
                                        ),
                                        child: GrenadeTypeIcon(
                                          type: g.type,
                                          size: useLegacyMarkers ? 14 : 18,
                                          color: typeColor,
                                        ),
                                      ),
                                      title: Text(
                                        g.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      subtitle: Text(
                                        '${layer.name} • ${mapTypeName(g.type)} • ${mapTeamName(g.team)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context).hintColor,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (g.isFavorite)
                                            const Icon(Icons.star,
                                                color: Colors.amber, size: 14),
                                          if (isEditMode)
                                            IconButton(
                                              onPressed: () =>
                                                  onDeleteGrenade(g),
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              color: Colors.redAccent,
                                              tooltip: '删除道具',
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                            )
                                          else
                                            const Icon(Icons.chevron_right,
                                                color: Colors.grey, size: 16),
                                        ],
                                      ),
                                      onTap: () => onTapGrenade(g, layer),
                                    );
                                  },
                                ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<bool> confirmDeleteGrenadeFromMapList(
  BuildContext context,
  Grenade g,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      title: Text("删除道具",
          style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
      content: Text("确定要删除 \"${g.title}\" 吗？",
          style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("取消"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("删除", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return confirmed == true;
}
