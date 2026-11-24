import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../widgets/grenade_type_icon.dart';
import 'map_clustering.dart';
import 'map_impact_dialogs.dart';
import 'map_markers_and_lines.dart';
import 'map_providers.dart';

class MapClusterListPanel extends ConsumerWidget {
  final GrenadeCluster cluster;
  final int layerId;
  final bool isEditMode;
  final bool isImpactMode;
  final bool useLegacyMarkers;
  final int? selectedImpactTypeFilter;
  final int? selectedImpactGroupId;
  final VoidCallback onClosePanel;
  final void Function(int? groupId, int? typeFilter) onSelectImpactFilter;
  final VoidCallback onStartMoveCluster;
  final VoidCallback onStartMoveImpactCluster;
  final VoidCallback onCreateGrenadeAtCluster;
  final void Function(Grenade grenade) onTapGrenade;
  final void Function(Grenade grenade) onStartMoveSingleGrenade;
  final void Function(Grenade grenade) onStartMoveSingleGrenadeImpact;
  final Future<void> Function(
    Grenade grenade,
    void Function(void Function()) setPanelState,
  ) onClearWallbangLine;
  final Future<void> Function(Grenade grenade) onOpenImpactAreaDrawing;
  final Future<void> Function(
    ImpactGroup group,
    List<Grenade> grenades,
    void Function(void Function())? setPanelState,
  ) onOpenGroupImpactAreaDrawing;
  final Future<void> Function(List<Grenade> grenades) onDeleteGrenadesInBatch;
  final VoidCallback onParentRefresh;

  const MapClusterListPanel({
    super.key,
    required this.cluster,
    required this.layerId,
    required this.isEditMode,
    required this.isImpactMode,
    required this.useLegacyMarkers,
    required this.selectedImpactTypeFilter,
    required this.selectedImpactGroupId,
    required this.onClosePanel,
    required this.onSelectImpactFilter,
    required this.onStartMoveCluster,
    required this.onStartMoveImpactCluster,
    required this.onCreateGrenadeAtCluster,
    required this.onTapGrenade,
    required this.onStartMoveSingleGrenade,
    required this.onStartMoveSingleGrenadeImpact,
    required this.onClearWallbangLine,
    required this.onOpenImpactAreaDrawing,
    required this.onOpenGroupImpactAreaDrawing,
    required this.onDeleteGrenadesInBatch,
    required this.onParentRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grenadesAsync = ref.watch(mapFilteredGrenadesProvider(layerId));
    return grenadesAsync.when(
      data: (filteredList) {
        final filteredIds = filteredList.map((g) => g.id).toSet();
        final grenades =
            cluster.grenades.where((g) => filteredIds.contains(g.id)).toList();
        // 如果当前点位下所有道具都被筛选掉，自动关闭面板
        if (grenades.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              onClosePanel();
            }
          });
          return const SizedBox.shrink();
        }
        return MapClusterListPanelContent(
          grenades: grenades,
          cluster: cluster,
          layerId: layerId,
          isEditMode: isEditMode,
          isImpactMode: isImpactMode,
          useLegacyMarkers: useLegacyMarkers,
          selectedImpactTypeFilter: selectedImpactTypeFilter,
          selectedImpactGroupId: selectedImpactGroupId,
          onClosePanel: onClosePanel,
          onSelectImpactFilter: onSelectImpactFilter,
          onStartMoveCluster: onStartMoveCluster,
          onStartMoveImpactCluster: onStartMoveImpactCluster,
          onCreateGrenadeAtCluster: onCreateGrenadeAtCluster,
          onTapGrenade: onTapGrenade,
          onStartMoveSingleGrenade: onStartMoveSingleGrenade,
          onStartMoveSingleGrenadeImpact: onStartMoveSingleGrenadeImpact,
          onClearWallbangLine: onClearWallbangLine,
          onOpenImpactAreaDrawing: onOpenImpactAreaDrawing,
          onOpenGroupImpactAreaDrawing: onOpenGroupImpactAreaDrawing,
          onDeleteGrenadesInBatch: onDeleteGrenadesInBatch,
          onParentRefresh: onParentRefresh,
        );
      },
      error: (_, __) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }
}

class MapClusterListPanelContent extends ConsumerWidget {
  final List<Grenade> grenades;
  final GrenadeCluster cluster;
  final int layerId;
  final bool isEditMode;
  final bool isImpactMode;
  final bool useLegacyMarkers;
  final int? selectedImpactTypeFilter;
  final int? selectedImpactGroupId;
  final VoidCallback onClosePanel;
  final void Function(int? groupId, int? typeFilter) onSelectImpactFilter;
  final VoidCallback onStartMoveCluster;
  final VoidCallback onStartMoveImpactCluster;
  final VoidCallback onCreateGrenadeAtCluster;
  final void Function(Grenade grenade) onTapGrenade;
  final void Function(Grenade grenade) onStartMoveSingleGrenade;
  final void Function(Grenade grenade) onStartMoveSingleGrenadeImpact;
  final Future<void> Function(
    Grenade grenade,
    void Function(void Function()) setPanelState,
  ) onClearWallbangLine;
  final Future<void> Function(Grenade grenade) onOpenImpactAreaDrawing;
  final Future<void> Function(
    ImpactGroup group,
    List<Grenade> grenades,
    void Function(void Function())? setPanelState,
  ) onOpenGroupImpactAreaDrawing;
  final Future<void> Function(List<Grenade> grenades) onDeleteGrenadesInBatch;
  final VoidCallback onParentRefresh;

  const MapClusterListPanelContent({
    super.key,
    required this.grenades,
    required this.cluster,
    required this.layerId,
    required this.isEditMode,
    required this.isImpactMode,
    required this.useLegacyMarkers,
    required this.selectedImpactTypeFilter,
    required this.selectedImpactGroupId,
    required this.onClosePanel,
    required this.onSelectImpactFilter,
    required this.onStartMoveCluster,
    required this.onStartMoveImpactCluster,
    required this.onCreateGrenadeAtCluster,
    required this.onTapGrenade,
    required this.onStartMoveSingleGrenade,
    required this.onStartMoveSingleGrenadeImpact,
    required this.onClearWallbangLine,
    required this.onOpenImpactAreaDrawing,
    required this.onOpenGroupImpactAreaDrawing,
    required this.onDeleteGrenadesInBatch,
    required this.onParentRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isar = ref.read(isarProvider);
    bool isMultiSelectMode = false;
    Set<int> selectedIds = {};

    Map<int, List<Grenade>> getTypeGroups() {
      final groups = <int, List<Grenade>>{};
      for (final g in grenades) {
        groups.putIfAbsent(g.type, () => []).add(g);
      }
      return groups;
    }

    return Container(
      height: 220,
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
      child: FutureBuilder<List<ImpactGroup>>(
        future: loadImpactGroups(isar, cluster, layerId),
        builder: (context, snapshot) {
          final customGroups = snapshot.data ?? [];
          return StatefulBuilder(
            builder: (context, setPanelState) {
              List<Grenade> displayGrenades;
              if (selectedImpactGroupId != null) {
                if (selectedImpactGroupId == -1) {
                  displayGrenades =
                      grenades.where((g) => g.impactGroupId == null).toList();
                } else {
                  displayGrenades = grenades
                      .where((g) => g.impactGroupId == selectedImpactGroupId)
                      .toList();
                }
              } else if (selectedImpactTypeFilter != null) {
                displayGrenades = grenades
                    .where((g) => g.type == selectedImpactTypeFilter)
                    .toList();
              } else {
                displayGrenades = grenades;
              }
              final unassignedGrenades =
                  grenades.where((g) => g.impactGroupId == null).toList();
              // 浏览模式下只有一个分组且无未分类道具时自动选中该分组
              if (!isEditMode &&
                  customGroups.length == 1 &&
                  unassignedGrenades.isEmpty &&
                  selectedImpactGroupId == null &&
                  selectedImpactTypeFilter == null &&
                  isImpactMode) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted && selectedImpactGroupId == null) {
                    onSelectImpactFilter(
                        customGroups.first.id, customGroups.first.type);
                  }
                });
              }
              final showTypeSelector = isImpactMode &&
                  grenades.length > 1 &&
                  selectedImpactTypeFilter == null &&
                  selectedImpactGroupId == null;
              return Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        if ((selectedImpactTypeFilter != null ||
                                selectedImpactGroupId != null) &&
                            isImpactMode)
                          IconButton(
                            onPressed: () {
                              onSelectImpactFilter(null, null);
                              setPanelState(() {
                                isMultiSelectMode = false;
                                selectedIds.clear();
                              });
                            },
                            icon: const Icon(Icons.arrow_back),
                            color: Colors.grey,
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        Text(
                          showTypeSelector
                              ? "该爆点共 ${grenades.length} 个道具"
                              : isMultiSelectMode
                                  ? "已选择 ${selectedIds.length} 个"
                                  : selectedImpactGroupId != null
                                      ? "${selectedImpactGroupId == -1 ? "未分类" : (customGroups.any((g) => g.id == selectedImpactGroupId) ? customGroups.firstWhere((g) => g.id == selectedImpactGroupId).name : "未知分组")} (${displayGrenades.length})"
                                      : selectedImpactTypeFilter != null
                                          ? "${mapTypeName(selectedImpactTypeFilter!)} (${displayGrenades.length})"
                                          : grenades.length == 1
                                              ? (grenades.first.description ??
                                                  "未命名爆点")
                                              : "该点位共 ${grenades.length} 个道具",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        if (isEditMode &&
                            !showTypeSelector &&
                            !isMultiSelectMode &&
                            ((selectedImpactGroupId != null &&
                                    selectedImpactGroupId != -1) ||
                                (selectedImpactGroupId == null &&
                                    selectedImpactTypeFilter == null &&
                                    grenades.length == 1)))
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16),
                            padding: const EdgeInsets.only(left: 4),
                            constraints: const BoxConstraints(),
                            tooltip: "重命名",
                            color: Colors.grey,
                            onPressed: () {
                              ImpactGroup? group;
                              if (selectedImpactGroupId != null) {
                                try {
                                  group = customGroups.firstWhere(
                                      (g) => g.id == selectedImpactGroupId);
                                } catch (_) {}
                              }
                              showRenameImpactPointDialog(
                                context: context,
                                isar: isar,
                                group: group,
                                grenade: grenades.length == 1 && group == null
                                    ? grenades.first
                                    : null,
                                onSuccess: () {
                                  onParentRefresh();
                                  setPanelState(() {});
                                },
                              );
                            },
                          ),
                        const Spacer(),
                        if (isEditMode && !showTypeSelector)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isMultiSelectMode)
                                TextButton.icon(
                                  onPressed: selectedIds.isEmpty
                                      ? null
                                      : () async {
                                          final confirm =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: Theme.of(ctx)
                                                  .colorScheme
                                                  .surface,
                                              title: Text("批量删除",
                                                  style: TextStyle(
                                                      color: Theme.of(ctx)
                                                          .textTheme
                                                          .bodyLarge
                                                          ?.color)),
                                              content: Text(
                                                  "确定要删除选中的 ${selectedIds.length} 个道具吗？",
                                                  style: TextStyle(
                                                      color: Theme.of(ctx)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.color)),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, false),
                                                    child: const Text("取消")),
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, true),
                                                    child: const Text("删除",
                                                        style: TextStyle(
                                                            color:
                                                                Colors.red))),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            final toDelete = <Grenade>[];
                                            for (final id in selectedIds) {
                                              final g = grenades.firstWhere(
                                                  (g) => g.id == id,
                                                  orElse: () => grenades.first);
                                              if (!toDelete
                                                  .any((x) => x.id == g.id)) {
                                                toDelete.add(g);
                                              }
                                            }
                                            await onDeleteGrenadesInBatch(
                                                toDelete);
                                            if (grenades.isEmpty ||
                                                toDelete.length ==
                                                    grenades.length) {
                                              onClosePanel();
                                            } else {
                                              setPanelState(() {
                                                isMultiSelectMode = false;
                                                selectedIds.clear();
                                              });
                                            }
                                          }
                                        },
                                  icon: const Icon(Icons.delete, size: 16),
                                  label: Text("删除(${selectedIds.length})"),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                )
                              else
                                IconButton(
                                  onPressed: () {
                                    setPanelState(() {
                                      isMultiSelectMode = true;
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                  color: Colors.red,
                                  tooltip: "批量删除",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              if (isMultiSelectMode)
                                IconButton(
                                  onPressed: () {
                                    setPanelState(() {
                                      isMultiSelectMode = false;
                                      selectedIds.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                  color: Colors.grey,
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              if (!isMultiSelectMode && !isImpactMode)
                                IconButton(
                                  onPressed: () {
                                    onClosePanel();
                                    onStartMoveCluster();
                                  },
                                  icon: const Icon(Icons.open_with),
                                  color: Colors.cyan,
                                  tooltip: "移动整体",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              if (!isMultiSelectMode && isImpactMode)
                                IconButton(
                                  onPressed: () {
                                    onClosePanel();
                                    onStartMoveImpactCluster();
                                  },
                                  icon: const Icon(Icons.gps_fixed),
                                  color: Colors.purpleAccent,
                                  tooltip: "移动爆点",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              if (!isMultiSelectMode)
                                IconButton(
                                  onPressed: () {
                                    onClosePanel();
                                    onCreateGrenadeAtCluster();
                                  },
                                  icon: const Icon(Icons.add_circle),
                                  color: Colors.orange,
                                  tooltip: "添加道具",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                            ],
                          ),
                        if (showTypeSelector && isEditMode)
                          IconButton(
                            onPressed: () => showAddImpactGroupDialog(
                              context: context,
                              isar: isar,
                              cluster: cluster,
                              layerId: layerId,
                              setPanelState: setPanelState,
                              onCreated: onParentRefresh,
                            ),
                            icon: const Icon(Icons.add_circle),
                            color: Colors.purpleAccent,
                            tooltip: "添加爆点分组",
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        IconButton(
                          onPressed: onClosePanel,
                          icon: const Icon(Icons.close),
                          color: Colors.grey,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: Theme.of(context).dividerColor, height: 1),
                  Expanded(
                    child: showTypeSelector
                        ? MapImpactTypeSelector(
                            typeGroups: getTypeGroups(),
                            cluster: cluster,
                            layerId: layerId,
                            isEditMode: isEditMode,
                            useLegacyMarkers: useLegacyMarkers,
                            setPanelState: setPanelState,
                            onSelectImpactFilter: onSelectImpactFilter,
                            onOpenGroupImpactAreaDrawing:
                                onOpenGroupImpactAreaDrawing,
                            onParentRefresh: onParentRefresh,
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: displayGrenades.length,
                            itemBuilder: (_, index) {
                              final g = displayGrenades[index];
                              final typeColor = mapGroupTypeColor(g.type);
                              final isSelected = selectedIds.contains(g.id);
                              final hasWallbangLine = g.impactXRatio != null &&
                                  g.impactYRatio != null;

                              Widget listItem = ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isMultiSelectMode)
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (val) {
                                          setPanelState(() {
                                            if (val == true) {
                                              selectedIds.add(g.id);
                                            } else {
                                              selectedIds.remove(g.id);
                                            }
                                          });
                                        },
                                        activeColor: Colors.red,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    Container(
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: typeColor, width: 2),
                                      ),
                                      child: GrenadeTypeIcon(
                                        type: g.type,
                                        size: useLegacyMarkers ? 15 : 16.5,
                                        color: typeColor,
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  g.title,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  "${mapTypeName(g.type)} • ${mapTeamName(g.team)}",
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                    fontSize: 10,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (g.isFavorite)
                                      const Icon(Icons.star,
                                          color: Colors.amber, size: 12),
                                    if (g.isNewImport)
                                      Container(
                                        margin: const EdgeInsets.only(left: 2),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 2, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          "NEW",
                                          style: TextStyle(
                                              fontSize: 6, color: Colors.white),
                                        ),
                                      ),
                                    if (isEditMode && !isMultiSelectMode)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (g.type ==
                                              GrenadeType.wallbang) ...[
                                            IconButton(
                                              onPressed: () {
                                                onClosePanel();
                                                onStartMoveSingleGrenadeImpact(
                                                    g);
                                              },
                                              icon: const Icon(
                                                  Icons.north_east_rounded),
                                              color: Colors.cyanAccent,
                                              tooltip: hasWallbangLine
                                                  ? '修改穿线'
                                                  : '设置穿线',
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 32, minHeight: 32),
                                            ),
                                            if (hasWallbangLine)
                                              IconButton(
                                                onPressed: () =>
                                                    onClearWallbangLine(
                                                  g,
                                                  (fn) {
                                                    if (context.mounted) {
                                                      setPanelState(fn);
                                                    }
                                                  },
                                                ),
                                                icon: const Icon(
                                                    Icons.link_off_rounded),
                                                color: Colors.redAccent,
                                                tooltip: '清除穿线',
                                                iconSize: 18,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 32,
                                                        minHeight: 32),
                                              ),
                                          ] else
                                            IconButton(
                                              onPressed: () {
                                                onClosePanel();
                                                onStartMoveSingleGrenadeImpact(
                                                    g);
                                              },
                                              icon: const Icon(Icons.gps_fixed),
                                              color: Colors.purpleAccent,
                                              tooltip: "设置/移动爆点",
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 32, minHeight: 32),
                                            ),
                                          if (isImpactMode &&
                                              (g.type == GrenadeType.smoke ||
                                                  g.type ==
                                                      GrenadeType.molotov))
                                            IconButton(
                                              onPressed: () {
                                                onClosePanel();
                                                onOpenImpactAreaDrawing(g);
                                              },
                                              icon: const Icon(Icons.brush),
                                              color: Colors.amber,
                                              tooltip: "绘制爆点区域",
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 32, minHeight: 32),
                                            ),
                                          if (!isImpactMode)
                                            IconButton(
                                              onPressed: () {
                                                onClosePanel();
                                                onStartMoveSingleGrenade(g);
                                              },
                                              icon: const Icon(Icons.open_with),
                                              color: Colors.cyan,
                                              tooltip: "移动投掷点",
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 32, minHeight: 32),
                                            ),
                                        ],
                                      ),
                                    if (!isMultiSelectMode)
                                      const Icon(Icons.chevron_right,
                                          color: Colors.grey, size: 16),
                                  ],
                                ),
                                onTap: isMultiSelectMode
                                    ? () {
                                        setPanelState(() {
                                          if (isSelected) {
                                            selectedIds.remove(g.id);
                                          } else {
                                            selectedIds.add(g.id);
                                          }
                                        });
                                      }
                                    : () {
                                        onClosePanel();
                                        onTapGrenade(g);
                                      },
                              );

                              if (isEditMode && !isMultiSelectMode) {
                                return Dismissible(
                                  key: Key('grenade_${g.id}'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    color: Colors.red,
                                    child: const Icon(Icons.delete,
                                        color: Colors.white),
                                  ),
                                  confirmDismiss: (_) async {
                                    return await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor:
                                            Theme.of(ctx).colorScheme.surface,
                                        title: Text("删除道具",
                                            style: TextStyle(
                                                color: Theme.of(ctx)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color)),
                                        content: Text("确定要删除 \"${g.title}\" 吗？",
                                            style: TextStyle(
                                                color: Theme.of(ctx)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color)),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text("取消")),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text("删除",
                                                  style: TextStyle(
                                                      color: Colors.red))),
                                        ],
                                      ),
                                    );
                                  },
                                  onDismissed: (_) async {
                                    await onDeleteGrenadesInBatch([g]);
                                    if (grenades.length <= 1) {
                                      onClosePanel();
                                    }
                                  },
                                  child: listItem,
                                );
                              }

                              return listItem;
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
