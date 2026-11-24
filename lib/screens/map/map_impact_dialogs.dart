import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../services/data_service.dart';
import '../../widgets/grenade_type_icon.dart';
import 'map_clustering.dart';
import 'map_markers_and_lines.dart';

// 加载与当前爆点坐标匹配的自定义分组（阈值与聚合阈值一致为 0.02）
Future<List<ImpactGroup>> loadImpactGroups(
  Isar isar,
  GrenadeCluster? cluster,
  int? layerId,
) async {
  if (cluster == null || layerId == null) return [];
  final allGroups =
      await isar.impactGroups.filter().layerIdEqualTo(layerId).findAll();
  const threshold = 0.02;
  return allGroups.where((g) {
    final dx = (g.impactXRatio - cluster.xRatio).abs();
    final dy = (g.impactYRatio - cluster.yRatio).abs();
    return (dx * dx + dy * dy) < threshold * threshold;
  }).toList();
}

class MapImpactTypeSelector extends ConsumerWidget {
  final Map<int, List<Grenade>> typeGroups;
  final GrenadeCluster? cluster;
  final int? layerId;
  final bool isEditMode;
  final bool useLegacyMarkers;
  final void Function(void Function())? setPanelState;
  final void Function(int? groupId, int? typeFilter) onSelectImpactFilter;
  final Future<void> Function(
    ImpactGroup group,
    List<Grenade> grenades,
    void Function(void Function())? setPanelState,
  ) onOpenGroupImpactAreaDrawing;
  final VoidCallback onParentRefresh;

  const MapImpactTypeSelector({
    super.key,
    required this.typeGroups,
    required this.cluster,
    required this.layerId,
    required this.isEditMode,
    required this.useLegacyMarkers,
    required this.setPanelState,
    required this.onSelectImpactFilter,
    required this.onOpenGroupImpactAreaDrawing,
    required this.onParentRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isar = ref.read(isarProvider);
    return FutureBuilder<List<ImpactGroup>>(
      future: loadImpactGroups(isar, cluster, layerId),
      builder: (context, snapshot) {
        final customGroups = snapshot.data ?? [];
        final allGrenades = typeGroups.values.expand((e) => e).toList();
        final unassignedGrenades =
            allGrenades.where((g) => g.impactGroupId == null).toList();

        if (customGroups.isEmpty && unassignedGrenades.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open,
                      size: 48,
                      color: Colors.purpleAccent.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text("暂无分组和道具",
                      style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 14)),
                  const SizedBox(height: 8),
                  Text("点击右上角 + 按钮创建分组或添加道具",
                      style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.6),
                          fontSize: 12)),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (unassignedGrenades.isNotEmpty || customGroups.isEmpty)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey, width: 2),
                  ),
                  child: const Icon(Icons.inbox, size: 20, color: Colors.grey),
                ),
                title: const Text("未分类",
                    style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                subtitle: Text("${unassignedGrenades.length} 个投掷点",
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12)),
                trailing: Icon(Icons.chevron_right,
                    color: Colors.grey.withValues(alpha: 0.7)),
                onTap: () {
                  onSelectImpactFilter(-1, null);
                  setPanelState?.call(() {});
                },
              ),
            if (customGroups.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                        width: 20,
                        height: 1,
                        color: Colors.purpleAccent.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Text("自定义分组",
                        style: TextStyle(
                            color: Colors.purpleAccent.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Container(
                            height: 1,
                            color: Colors.purpleAccent.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ...customGroups.map((group) {
              final typeColor = mapGroupTypeColor(group.type);
              final groupGrenades = allGrenades
                  .where((g) => g.impactGroupId == group.id)
                  .toList();

              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.purpleAccent, width: 2),
                  ),
                  child: GrenadeTypeIcon(
                    type: group.type,
                    size: useLegacyMarkers ? 21 : 26,
                    color: typeColor,
                  ),
                ),
                title: Text(group.name,
                    style: const TextStyle(
                        color: Colors.purpleAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                subtitle: Text(
                    "${mapTypeName(group.type)} · ${groupGrenades.length} 个投掷点",
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((group.type == GrenadeType.smoke ||
                            group.type == GrenadeType.molotov) &&
                        layerId != null &&
                        isEditMode)
                      IconButton(
                        onPressed: () => onOpenGroupImpactAreaDrawing(
                            group, groupGrenades, setPanelState),
                        icon: const Icon(Icons.brush),
                        color: Colors.amber,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "绘制分组爆点范围",
                      ),
                    if (isEditMode)
                      IconButton(
                        onPressed: () => showAssignGrenadesToGroupDialog(
                          context: context,
                          isar: isar,
                          group: group,
                          allGrenades: allGrenades,
                          useLegacyMarkers: useLegacyMarkers,
                          setPanelState: setPanelState,
                          onSaved: onParentRefresh,
                        ),
                        icon: const Icon(Icons.playlist_add),
                        color: Colors.amber,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "分类投掷点",
                      ),
                    if (isEditMode)
                      IconButton(
                        onPressed: () => deleteImpactGroup(
                          context: context,
                          isar: isar,
                          group: group,
                          setPanelState: setPanelState,
                          onDeleted: onParentRefresh,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.red.withValues(alpha: 0.7),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "删除分组",
                      ),
                    Icon(Icons.chevron_right,
                        color: Colors.purpleAccent.withValues(alpha: 0.7)),
                  ],
                ),
                onTap: () {
                  onSelectImpactFilter(group.id, group.type);
                  setPanelState?.call(() {});
                },
              );
            }),
          ],
        );
      },
    );
  }
}

class _MapImpactTypeChip extends StatelessWidget {
  final int type;
  final int selectedType;
  final ValueChanged<int> onTap;

  const _MapImpactTypeChip({
    required this.type,
    required this.selectedType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = type == selectedType;
    final name = mapTypeName(type);
    final typeColor = mapGroupTypeColor(type);

    return GestureDetector(
      onTap: () => onTap(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? typeColor.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? typeColor : Colors.grey.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GrenadeTypeIcon(type: type, size: 19, color: typeColor),
            const SizedBox(width: 6),
            Text(name,
                style: TextStyle(
                    color: typeColor,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

void showAddImpactGroupDialog({
  required BuildContext context,
  required Isar isar,
  required GrenadeCluster cluster,
  required int layerId,
  required void Function(void Function()) setPanelState,
  required VoidCallback onCreated,
}) {
  final nameController = TextEditingController();
  int selectedType = GrenadeType.smoke;
  String? errorText;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Row(
          children: [
            const Icon(Icons.add_circle, color: Colors.purpleAccent),
            const SizedBox(width: 8),
            Text("添加爆点分组",
                style:
                    TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("选择道具类型",
                style: TextStyle(
                    color: Theme.of(ctx).textTheme.bodySmall?.color,
                    fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _MapImpactTypeChip(
                        type: GrenadeType.smoke,
                        selectedType: selectedType,
                        onTap: (type) {
                          setDialogState(() => selectedType = type);
                        })),
                const SizedBox(width: 8),
                Expanded(
                    child: _MapImpactTypeChip(
                        type: GrenadeType.flash,
                        selectedType: selectedType,
                        onTap: (type) {
                          setDialogState(() => selectedType = type);
                        })),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _MapImpactTypeChip(
                        type: GrenadeType.molotov,
                        selectedType: selectedType,
                        onTap: (type) {
                          setDialogState(() => selectedType = type);
                        })),
                const SizedBox(width: 8),
                Expanded(
                    child: _MapImpactTypeChip(
                        type: GrenadeType.he,
                        selectedType: selectedType,
                        onTap: (type) {
                          setDialogState(() => selectedType = type);
                        })),
              ],
            ),
            const SizedBox(height: 16),
            Text("分组名称",
                style: TextStyle(
                    color: Theme.of(ctx).textTheme.bodySmall?.color,
                    fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: "例如: 烟雾1、A点闪等",
                errorText: errorText,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                setDialogState(() => errorText = "请输入分组名称");
                return;
              }
              final currentGroups =
                  await loadImpactGroups(isar, cluster, layerId);
              if (currentGroups.any((g) => g.name == name)) {
                setDialogState(() => errorText = "该爆点下分组名称已存在");
                return;
              }
              final group = ImpactGroup(
                name: name,
                type: selectedType,
                impactXRatio: cluster.xRatio,
                impactYRatio: cluster.yRatio,
                layerId: layerId,
                updated: DateTime.now(),
              );
              await isar.writeTxn(() async {
                await isar.impactGroups.put(group);
              });
              if (ctx.mounted) Navigator.pop(ctx);
              setPanelState(() {});
              onCreated();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("创建"),
          ),
        ],
      ),
    ),
  );
}

void showAssignGrenadesToGroupDialog({
  required BuildContext context,
  required Isar isar,
  required ImpactGroup group,
  required List<Grenade> allGrenades,
  required bool useLegacyMarkers,
  required void Function(void Function())? setPanelState,
  required VoidCallback onSaved,
}) {
  final eligibleGrenades =
      allGrenades.where((g) => g.type == group.type).toList();
  final assignedIds = eligibleGrenades
      .where((g) => g.impactGroupId == group.id)
      .map((g) => g.id)
      .toSet();
  Set<int> selectedIds = Set.from(assignedIds);

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Row(
          children: [
            const Icon(Icons.playlist_add, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text("分类投掷点到 \"${group.name}\"",
                  style: TextStyle(
                      color: Theme.of(ctx).textTheme.bodyLarge?.color,
                      fontSize: 16),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: eligibleGrenades.isEmpty
              ? Center(
                  child: Text("没有 ${mapTypeName(group.type)} 类型的投掷点",
                      style: TextStyle(
                          color: Theme.of(ctx).textTheme.bodySmall?.color)),
                )
              : ListView.builder(
                  itemCount: eligibleGrenades.length,
                  itemBuilder: (ctx, index) {
                    final g = eligibleGrenades[index];
                    final isSelected = selectedIds.contains(g.id);
                    final typeColor = mapGroupTypeColor(g.type);

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            selectedIds.add(g.id);
                          } else {
                            selectedIds.remove(g.id);
                          }
                        });
                      },
                      activeColor: Colors.purpleAccent,
                      title: Text(g.title,
                          style: TextStyle(
                              color: Theme.of(ctx).textTheme.bodyLarge?.color,
                              fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(mapTypeName(g.type),
                          style: TextStyle(color: typeColor, fontSize: 12)),
                      secondary: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: typeColor, width: 1.5),
                        ),
                        child: GrenadeTypeIcon(
                          type: g.type,
                          size: useLegacyMarkers ? 15 : 20,
                          color: typeColor,
                        ),
                      ),
                      dense: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              await isar.writeTxn(() async {
                for (final g in eligibleGrenades) {
                  if (selectedIds.contains(g.id)) {
                    g.impactGroupId = group.id;
                  } else if (g.impactGroupId == group.id) {
                    g.impactGroupId = null;
                  }
                  await isar.grenades.put(g);
                }
              });
              if (ctx.mounted) Navigator.pop(ctx);
              setPanelState?.call(() {});
              onSaved();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("确定"),
          ),
        ],
      ),
    ),
  );
}

Future<void> deleteImpactGroup({
  required BuildContext context,
  required Isar isar,
  required ImpactGroup group,
  required void Function(void Function())? setPanelState,
  required VoidCallback onDeleted,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      title: Text("删除分组",
          style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
      content: Text("确定要删除分组 \"${group.name}\" 吗？\n该分组下的投掷点不会被删除。",
          style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消")),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("删除", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await DataService(isar).deleteImpactGroup(group);
    setPanelState?.call(() {});
    onDeleted();
  }
}

Future<void> showRenameImpactPointDialog({
  required BuildContext context,
  required Isar isar,
  ImpactGroup? group,
  Grenade? grenade,
  required VoidCallback onSuccess,
}) async {
  final isGroup = group != null;
  final TextEditingController controller = TextEditingController(
      text: isGroup ? group.name : (grenade?.description ?? ""));

  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isGroup ? "重命名分组" : "重命名爆点"),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: "名称"),
        autofocus: true,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("取消")),
        TextButton(
          onPressed: () async {
            final newName = controller.text.trim();

            await isar.writeTxn(() async {
              if (isGroup) {
                group.name = newName;
                group.updatedAt = DateTime.now();
                await isar.impactGroups.put(group);
              } else if (grenade != null) {
                grenade.description = newName;
                await isar.grenades.put(grenade);
              }
            });
            onSuccess();
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
          },
          child: const Text("保存"),
        ),
      ],
    ),
  );
}
