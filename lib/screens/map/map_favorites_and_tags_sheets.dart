import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../models/map_area.dart';
import '../../models/tag.dart';
import '../../providers.dart';
import '../../services/favorite_folder_service.dart';
import '../../services/tag_service.dart';
import '../../theme/app_design_system.dart';
import '../../widgets/grenade_type_icon.dart';
import '../area_manager_screen.dart';
import '../tag_manager_screen.dart';
import 'map_markers_and_lines.dart';
import 'map_providers.dart';
import 'map_toolbars.dart';

class MapFavoritesBar extends StatelessWidget {
  final GameMap gameMap;
  final FavoriteFolderService folderService;
  final ValueChanged<Grenade> onGrenadeTap;

  const MapFavoritesBar({
    super.key,
    required this.gameMap,
    required this.folderService,
    required this.onGrenadeTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FolderWithGrenades>>(
      stream: folderService.watchMapFavorites(gameMap.id),
      builder: (context, snapshot) {
        final allFolders = snapshot.data ?? const <FolderWithGrenades>[];
        final visibleFolders =
            allFolders.where((f) => f.grenades.isNotEmpty).toList();

        final isMobile = AppBreakpoints.isMobile(context);
        return MapCapsuleSurface(
          radius: 14,
          useBlur: isMobile,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isMobile
                  ? Colors.black.withValues(alpha: 0.56)
                  : const Color(0xD612151B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: visibleFolders.isEmpty
                ? InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showFavoriteFolderManager(
                      hostContext: context,
                      gameMap: gameMap,
                      folderService: folderService,
                      onGrenadeTap: onGrenadeTap,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 17,
                            color: Colors.orangeAccent,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '收藏夹',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '管理收藏夹',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(6),
                        constraints:
                            const BoxConstraints(minWidth: 30, minHeight: 30),
                        onPressed: () => showFavoriteFolderManager(
                          hostContext: context,
                          gameMap: gameMap,
                          folderService: folderService,
                          onGrenadeTap: onGrenadeTap,
                        ),
                        icon: const Icon(
                          Icons.folder_open_rounded,
                          size: 17,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          itemCount: visibleFolders.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, index) {
                            final folderData = visibleFolders[index];
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => showFavoriteFolderItemsSheet(
                                hostContext: context,
                                gameMap: gameMap,
                                folderService: folderService,
                                folderId: folderData.folder.id,
                                onGrenadeTap: onGrenadeTap,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.folder_rounded,
                                      size: 13,
                                      color: Colors.orangeAccent,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${folderData.folder.name} (${folderData.grenades.length})',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

Future<void> showFavoriteFolderItemsSheet({
  required BuildContext hostContext,
  required GameMap gameMap,
  required FavoriteFolderService folderService,
  required int folderId,
  required ValueChanged<Grenade> onGrenadeTap,
}) async {
  await showModalBottomSheet(
    context: hostContext,
    isScrollControlled: true,
    backgroundColor: Theme.of(hostContext).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: StreamBuilder<List<FolderWithGrenades>>(
          stream: folderService.watchMapFavorites(gameMap.id),
          builder: (ctx, snapshot) {
            final folders = snapshot.data ?? const <FolderWithGrenades>[];
            FolderWithGrenades? folderData;
            for (final item in folders) {
              if (item.folder.id == folderId) {
                folderData = item;
                break;
              }
            }
            if (folderData == null) {
              return const Center(child: Text('收藏夹不存在或已删除'));
            }

            final grenades = folderData.grenades;
            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder, color: Colors.orangeAccent),
                  title: Text(folderData.folder.name),
                  subtitle: Text('${grenades.length} 个收藏道具'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: grenades.isEmpty
                      ? const Center(child: Text('该收藏夹暂无道具'))
                      : ListView.separated(
                          itemCount: grenades.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final g = grenades[index];
                            g.layer.loadSync();
                            final layerName = g.layer.value?.name ?? '未知楼层';
                            return ListTile(
                              dense: true,
                              leading: GrenadeTypeIcon(
                                type: g.type,
                                color: mapTypeColor(g.type),
                                size: 18,
                              ),
                              title: Text(
                                g.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                '$layerName · ${mapTypeName(g.type)} · ${mapTeamName(g.team)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(ctx).textTheme.bodySmall?.color,
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'move') {
                                    await showMoveFavoriteDialog(
                                      hostContext: hostContext,
                                      gameMap: gameMap,
                                      folderService: folderService,
                                      grenade: g,
                                      currentFolderId: folderData!.folder.id,
                                    );
                                  } else if (value == 'unfavorite') {
                                    await folderService.setFavorite(g.id,
                                        favorite: false);
                                    if (hostContext.mounted) {
                                      ScaffoldMessenger.of(hostContext)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('已取消收藏'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem<String>(
                                      value: 'move', child: Text('移动到其他收藏夹')),
                                  PopupMenuItem<String>(
                                      value: 'unfavorite', child: Text('取消收藏')),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                onGrenadeTap(g);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> showMoveFavoriteDialog({
  required BuildContext hostContext,
  required GameMap gameMap,
  required FavoriteFolderService folderService,
  required Grenade grenade,
  required int currentFolderId,
}) async {
  final folders = await folderService.getFoldersByMap(gameMap.id);
  final targets = folders.where((f) => f.id != currentFolderId).toList();
  if (targets.isEmpty) {
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(const SnackBar(
        content: Text('暂无可移动的目标收藏夹'), duration: Duration(seconds: 1)));
    return;
  }
  if (!hostContext.mounted) return;

  int? selectedFolderId = targets.first.id;
  final confirmed = await showDialog<bool>(
    context: hostContext,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('移动到收藏夹'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: targets
                .map((f) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        selectedFolderId == f.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: selectedFolderId == f.id
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).disabledColor,
                      ),
                      title: Text(f.name, overflow: TextOverflow.ellipsis),
                      onTap: () =>
                          setDialogState(() => selectedFolderId = f.id),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    ),
  );

  if (confirmed != true || selectedFolderId == null) return;

  try {
    await folderService.moveFavorite(grenade.id, selectedFolderId!);
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(const SnackBar(
        content: Text('已移动收藏夹'), duration: Duration(seconds: 1)));
  } catch (e) {
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(
        SnackBar(content: Text('移动失败：$e'), duration: Duration(seconds: 1)));
  }
}

Future<void> showFavoriteFolderManager({
  required BuildContext hostContext,
  required GameMap gameMap,
  required FavoriteFolderService folderService,
  required ValueChanged<Grenade> onGrenadeTap,
}) async {
  await showModalBottomSheet(
    context: hostContext,
    isScrollControlled: true,
    backgroundColor: Theme.of(hostContext).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.6,
      child: StreamBuilder<List<FolderWithGrenades>>(
        stream: folderService.watchMapFavorites(gameMap.id),
        builder: (ctx, snapshot) {
          final folders = snapshot.data ?? const <FolderWithGrenades>[];
          return Column(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.folder_open, color: Colors.orangeAccent),
                title: const Text('收藏夹管理'),
                subtitle: Text('共 ${folders.length} 个收藏夹'),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建收藏夹',
                  onPressed: () => showCreateFavoriteFolderDialog(
                    hostContext: hostContext,
                    gameMap: gameMap,
                    folderService: folderService,
                    dialogContext: ctx,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: folders.isEmpty
                    ? const Center(child: Text('暂无收藏夹'))
                    : ListView.separated(
                        itemCount: folders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final folderData = folders[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder,
                                color: Colors.orangeAccent),
                            title: Text(
                              folderData.folder.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${folderData.grenades.length} 个道具',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(ctx).textTheme.bodySmall?.color,
                              ),
                            ),
                            onTap: () => showFavoriteFolderItemsSheet(
                              hostContext: hostContext,
                              gameMap: gameMap,
                              folderService: folderService,
                              folderId: folderData.folder.id,
                              onGrenadeTap: onGrenadeTap,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () =>
                                      showRenameFavoriteFolderDialog(
                                    hostContext: hostContext,
                                    folderService: folderService,
                                    folder: folderData.folder,
                                    dialogContext: ctx,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.redAccent),
                                  onPressed: () =>
                                      showDeleteFavoriteFolderDialog(
                                    hostContext: hostContext,
                                    folderService: folderService,
                                    folderData: folderData,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> showCreateFavoriteFolderDialog({
  required BuildContext hostContext,
  required GameMap gameMap,
  required FavoriteFolderService folderService,
  BuildContext? dialogContext,
}) async {
  final ctx = dialogContext ?? hostContext;
  final controller = TextEditingController();
  final created = await showDialog<bool>(
    context: ctx,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('新建收藏夹'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '输入收藏夹名称',
        ),
        onSubmitted: (_) => Navigator.pop(dialogCtx, true),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消')),
        ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('创建')),
      ],
    ),
  );

  if (created != true) return;

  try {
    await folderService.createFolder(gameMap.id, controller.text);
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(const SnackBar(
        content: Text('收藏夹已创建'), duration: Duration(seconds: 1)));
  } catch (e) {
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(
        SnackBar(content: Text('创建失败：$e'), duration: Duration(seconds: 1)));
  }
}

Future<void> showRenameFavoriteFolderDialog({
  required BuildContext hostContext,
  required FavoriteFolderService folderService,
  required FavoriteFolder folder,
  BuildContext? dialogContext,
}) async {
  final ctx = dialogContext ?? hostContext;
  final controller = TextEditingController(text: folder.name);
  final confirmed = await showDialog<bool>(
    context: ctx,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('重命名收藏夹'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '输入新名称',
        ),
        onSubmitted: (_) => Navigator.pop(dialogCtx, true),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消')),
        ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('保存')),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    await folderService.renameFolder(folder.id, controller.text);
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(const SnackBar(
        content: Text('收藏夹已重命名'), duration: Duration(seconds: 1)));
  } catch (e) {
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(
        SnackBar(content: Text('重命名失败：$e'), duration: Duration(seconds: 1)));
  }
}

Future<void> showDeleteFavoriteFolderDialog({
  required BuildContext hostContext,
  required FavoriteFolderService folderService,
  required FolderWithGrenades folderData,
}) async {
  final folder = folderData.folder;
  final count = folderData.grenades.length;

  if (count == 0) {
    final confirmed = await showDialog<bool>(
      context: hostContext,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text('确认删除收藏夹「${folder.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await folderService.deleteFolder(
        folder.id, FavoriteFolderDeleteStrategy.unfavorite);
    return;
  }

  final strategy = await showDialog<FavoriteFolderDeleteStrategy>(
    context: hostContext,
    builder: (ctx) => AlertDialog(
      title: const Text('删除非空收藏夹'),
      content: Text('收藏夹「${folder.name}」中有 $count 个道具。\n请选择删除后如何处理这些收藏道具：'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, FavoriteFolderDeleteStrategy.unfavorite),
          child: const Text('取消收藏'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(ctx, FavoriteFolderDeleteStrategy.moveToDefault),
          child: const Text('迁移到默认夹'),
        ),
      ],
    ),
  );

  if (strategy == null) return;

  try {
    await folderService.deleteFolder(folder.id, strategy);
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(const SnackBar(
        content: Text('收藏夹已删除'), duration: Duration(seconds: 1)));
  } catch (e) {
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(
        SnackBar(content: Text('删除失败：$e'), duration: Duration(seconds: 1)));
  }
}

Future<void> showTagFilterSheet({
  required BuildContext hostContext,
  required WidgetRef ref,
  required GameMap gameMap,
  required int layerId,
}) async {
  final isar = ref.read(isarProvider);
  final tagService = TagService(isar);
  await tagService.initializeSystemTags(gameMap.id, gameMap.name);
  final allTags = await tagService.getAllTags(gameMap.id);
  final areaTagIds =
      (await isar.mapAreas.filter().mapIdEqualTo(gameMap.id).findAll())
          .map((a) => a.tagId)
          .toSet();
  final tags = allTags
      .where((tag) =>
          tag.dimension != TagDimension.area || areaTagIds.contains(tag.id))
      .toList();
  final validTagIds = tags.map((e) => e.id).toSet();
  final selectedBefore = ref.read(selectedTagIdsProvider);
  final selectedSanitized =
      selectedBefore.where((id) => validTagIds.contains(id)).toSet();
  if (selectedBefore.length != selectedSanitized.length) {
    ref.read(selectedTagIdsProvider.notifier).state = selectedSanitized;
  }
  if (!hostContext.mounted) return;
  Set<int> selectedIds = Set<int>.from(
    ref.read(selectedTagIdsProvider),
  );

  showModalBottomSheet(
    context: hostContext,
    backgroundColor: Theme.of(hostContext).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
      final grouped = <int, List<Tag>>{};
      for (final tag in tags) {
        grouped.putIfAbsent(tag.dimension, () => []).add(tag);
      }
      return Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(hostContext).size.height * 0.6),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.label, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text('标签筛选',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).textTheme.titleLarge?.color)),
              const Spacer(),
              if (selectedIds.isNotEmpty)
                TextButton(
                    onPressed: () {
                      selectedIds = {};
                      ref.read(selectedTagIdsProvider.notifier).state =
                          selectedIds;
                      setSheetState(() {});
                    },
                    child: const Text('清除')),
              IconButton(
                icon: const Icon(Icons.map_outlined, color: Colors.grey),
                tooltip: '管理区域',
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      hostContext,
                      MaterialPageRoute(
                          builder: (_) => AreaManagerScreen(gameMap: gameMap)));
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.grey),
                tooltip: '管理标签',
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      hostContext,
                      MaterialPageRoute(
                          builder: (_) => TagManagerScreen(
                              mapId: gameMap.id, mapName: gameMap.name)));
                },
              ),
            ]),
            if (selectedIds.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('已选 ${selectedIds.length} 个标签',
                      style: TextStyle(
                          color: Theme.of(ctx).textTheme.bodySmall?.color,
                          fontSize: 12))),
            const SizedBox(height: 8),
            Flexible(
              child: tags.isEmpty
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('暂无标签，点击右上角管理',
                              style: TextStyle(
                                  color: Theme.of(ctx)
                                      .textTheme
                                      .bodySmall
                                      ?.color))))
                  : ListView(
                      shrinkWrap: true,
                      children: grouped.entries
                          .where((e) => e.key != TagDimension.role)
                          .map((e) => _TagDimensionGroup(
                                dimension: e.key,
                                tags: e.value,
                                selectedIds: selectedIds,
                                onToggleTag: (tagId) {
                                  if (selectedIds.contains(tagId)) {
                                    selectedIds.remove(tagId);
                                  } else {
                                    selectedIds.add(tagId);
                                  }
                                  ref
                                      .read(selectedTagIdsProvider.notifier)
                                      .state = Set<int>.from(selectedIds);
                                },
                                setSheetState: setSheetState,
                              ))
                          .toList()),
            ),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('确定'))),
          ],
        ),
      );
    }),
  );
}

class _TagDimensionGroup extends StatelessWidget {
  final int dimension;
  final List<Tag> tags;
  final Set<int> selectedIds;
  final void Function(int tagId) onToggleTag;
  final void Function(void Function()) setSheetState;

  const _TagDimensionGroup({
    required this.dimension,
    required this.tags,
    required this.selectedIds,
    required this.onToggleTag,
    required this.setSheetState,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(TagDimension.getName(dimension),
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500))),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            final isSelected = selectedIds.contains(tag.id);
            final color = Color(tag.colorValue);
            return GestureDetector(
              onTap: () {
                onToggleTag(tag.id);
                setSheetState(() {});
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: isSelected ? color : color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color:
                            isSelected ? color : color.withValues(alpha: 0.4))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isSelected)
                    const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child:
                            Icon(Icons.check, size: 14, color: Colors.white)),
                  Text(tag.name,
                      style: TextStyle(
                          fontSize: 13,
                          color: isSelected ? Colors.white : color)),
                ]),
              ),
            );
          }).toList()),
      const SizedBox(height: 12),
    ]);
  }
}
