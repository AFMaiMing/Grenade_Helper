import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show sendOverlayCommand;
import '../models.dart';
import '../models/tag.dart';
import '../providers.dart';
import '../services/data_service.dart';
import '../services/favorite_folder_service.dart';
import '../services/tag_service.dart';
import '../theme/app_design_system.dart';
import 'area_draw_screen.dart';
import 'grenade_detail/detail_badges_and_menus.dart';
import 'grenade_detail/detail_dialogs.dart';
import 'grenade_detail/detail_media_helpers.dart';
import 'grenade_detail/detail_step_widgets.dart';
import 'impact_point_picker_screen.dart';

export 'grenade_detail/video_player_widget.dart'
    show VideoPlayerWidget, VideoPlayerWidgetState;

/// 道具教学详情与编辑页面。
class GrenadeDetailScreen extends ConsumerStatefulWidget {
  final int grenadeId;
  final bool isEditing;
  // 为 true 时表示爆点已固定，改为设置投掷点坐标
  final bool pickThrowPoint;

  const GrenadeDetailScreen({
    super.key,
    required this.grenadeId,
    required this.isEditing,
    this.pickThrowPoint = false,
  });

  @override
  ConsumerState<GrenadeDetailScreen> createState() =>
      _GrenadeDetailScreenState();
}

class _GrenadeDetailScreenState extends ConsumerState<GrenadeDetailScreen> {
  static const String _authorHistoryKey = 'author_history';

  Grenade? grenade;
  final _titleController = TextEditingController();
  final _stepScrollController = ScrollController();
  final Map<int, GlobalKey> _stepKeys = <int, GlobalKey>{};
  String? _originalTitle;
  List<Tag>? _grenadeTags;
  List<String> _authorHistory = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadAuthorHistory();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _stepScrollController.dispose();
    super.dispose();
  }

  List<GrenadeStep> _sortedSteps() {
    final steps = grenade?.steps.toList() ?? <GrenadeStep>[];
    steps.sort((a, b) => a.stepIndex.compareTo(b.stepIndex));
    return steps;
  }

  Future<void> _focusStep(GrenadeStep step) async {
    final target = _stepKeys[step.id]?.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: AppMotion.panel,
      curve: AppMotion.enter,
      alignment: 0.08,
    );
  }

  Future<void> _loadData({bool resetTitle = true}) async {
    final isar = ref.read(isarProvider);
    grenade = await isar.grenades.get(widget.grenadeId);
    if (grenade != null) {
      grenade!.steps.loadSync();
      for (final step in grenade!.steps) {
        step.medias.loadSync();
      }
      if (resetTitle) {
        _titleController.text = grenade!.title;
        _originalTitle = grenade!.title;
      }
      final tagService = TagService(isar);
      _grenadeTags = await tagService.getGrenadeTags(grenade!.id);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAuthorHistory() async {
    final prefs = await SharedPreferences.getInstance();
    _authorHistory = prefs.getStringList(_authorHistoryKey) ?? [];
  }

  Future<void> _saveAuthorToHistory(String author) async {
    if (author.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _authorHistory.remove(author);
    _authorHistory.insert(0, author);
    if (_authorHistory.length > 10) {
      _authorHistory = _authorHistory.sublist(0, 10);
    }
    await prefs.setStringList(_authorHistoryKey, _authorHistory);
  }

  Future<void> _markAsLocallyEdited() async {
    if (grenade == null) return;
    final isar = ref.read(isarProvider);
    final now = DateTime.now();
    await isar.writeTxn(() async {
      final latest = await isar.grenades.get(grenade!.id);
      if (latest == null) return;
      latest.hasLocalEdits = true;
      latest.updatedAt = now;
      await isar.grenades.put(latest);
    });
    grenade!.hasLocalEdits = true;
    grenade!.updatedAt = now;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _updateGrenade({
    String? title,
    int? type,
    int? team,
    String? author,
    String? sourceUrl,
    String? sourceNote,
  }) async {
    if (grenade == null) return;
    final isar = ref.read(isarProvider);

    if (title != null) {
      grenade!.title = title;
      _originalTitle = title;
    }
    if (type != null) grenade!.type = type;
    if (team != null) grenade!.team = team;
    if (author != null) grenade!.author = author.isEmpty ? null : author;
    if (sourceUrl != null) {
      grenade!.sourceUrl = sourceUrl.isEmpty ? null : sourceUrl;
    }
    if (sourceNote != null) {
      grenade!.sourceNote = sourceNote.isEmpty ? null : sourceNote;
    }

    grenade!.updatedAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.grenades.put(grenade!);
    });
    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
  }

  Future<MapLayer?> _loadGrenadeLayer() async {
    if (grenade == null) return null;
    await grenade!.layer.load();
    final layer = grenade!.layer.value;
    if (layer == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法获取楼层信息'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    return layer;
  }

  Future<int?> _resolveMapId() async {
    if (grenade == null) return null;
    await grenade!.layer.load();
    final layer = grenade!.layer.value;
    if (layer == null) return null;
    await layer.map.load();
    return layer.map.value?.id;
  }

  int? _resolveMapIdSync() {
    if (grenade == null) return null;
    grenade!.layer.loadSync();
    final layer = grenade!.layer.value;
    if (layer == null) return null;
    layer.map.loadSync();
    return layer.map.value?.id;
  }

  Future<void> _handleFavoriteAction() async {
    if (grenade == null) return;
    final isar = ref.read(isarProvider);
    final folderService = FavoriteFolderService(isar);

    if (grenade!.isFavorite) {
      await folderService.setFavorite(grenade!.id, favorite: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)),
      );
      await _loadData(resetTitle: false);
      return;
    }

    final mapId = await _resolveMapId();
    if (mapId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法识别当前地图'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    if (!mounted) return;

    final folderId = await showFavoriteFolderPickerDialog(
      context,
      folderService: folderService,
      mapId: mapId,
    );
    if (folderId == null) return;

    await folderService.setFavorite(
      grenade!.id,
      favorite: true,
      folderId: folderId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入收藏夹'), duration: Duration(seconds: 1)),
    );
    await _loadData(resetTitle: false);
  }

  Future<void> _updateImpactPoint(double? x, double? y) async {
    if (grenade == null) return;
    final isar = ref.read(isarProvider);

    grenade!.impactXRatio = x;
    grenade!.impactYRatio = y;
    grenade!.updatedAt = DateTime.now();

    await isar.writeTxn(() async {
      await isar.grenades.put(grenade!);
    });

    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
  }

  Future<void> _viewImpactPoint() async {
    if (grenade == null) return;
    final layer = await _loadGrenadeLayer();
    if (layer == null || !mounted) return;
    final isWallbang = grenade!.type == GrenadeType.wallbang;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ImpactPointPickerScreen(
          grenadeId: grenade!.id,
          initialX: grenade!.impactXRatio,
          initialY: grenade!.impactYRatio,
          throwX: grenade!.xRatio,
          throwY: grenade!.yRatio,
          layerId: layer.id,
          readOnly: true,
          existingStrokes: isWallbang ? null : grenade!.impactAreaStrokes,
          grenadeType: grenade!.type,
          wallbangLineMode: isWallbang,
        ),
      ),
    );
  }

  Future<void> _pickThrowPoint() async {
    if (grenade == null ||
        grenade!.impactXRatio == null ||
        grenade!.impactYRatio == null) {
      return;
    }
    final layer = await _loadGrenadeLayer();
    if (layer == null || !mounted) return;

    final result = await Navigator.push<Offset>(
      context,
      MaterialPageRoute(
        builder: (_) => ImpactPointPickerScreen(
          grenadeId: grenade!.id,
          initialX: grenade!.impactXRatio,
          initialY: grenade!.impactYRatio,
          throwX: grenade!.xRatio,
          throwY: grenade!.yRatio,
          layerId: layer.id,
          grenadeType: grenade!.type,
          pickThrowPoint: true,
        ),
      ),
    );
    if (result == null) return;

    final isar = ref.read(isarProvider);
    grenade!.xRatio = result.dx;
    grenade!.yRatio = result.dy;
    grenade!.updatedAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.grenades.put(grenade!);
    });
    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ 投掷点已设置'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _pickImpactPoint() async {
    if (grenade == null) return;
    final isWallbang = grenade!.type == GrenadeType.wallbang;
    final layer = await _loadGrenadeLayer();
    if (layer == null || !mounted) return;

    final result = await Navigator.push<Offset>(
      context,
      MaterialPageRoute(
        builder: (_) => ImpactPointPickerScreen(
          grenadeId: grenade!.id,
          initialX: grenade!.impactXRatio,
          initialY: grenade!.impactYRatio,
          throwX: grenade!.xRatio,
          throwY: grenade!.yRatio,
          layerId: layer.id,
          grenadeType: grenade!.type,
          wallbangLineMode: isWallbang,
        ),
      ),
    );

    if (result == null) return;
    await _updateImpactPoint(result.dx, result.dy);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isWallbang ? '✓ 穿线方位已设置' : '✓ 爆点已设置'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _drawImpactArea() async {
    if (grenade == null) return;
    final layer = await _loadGrenadeLayer();
    if (layer == null || !mounted) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaDrawScreen.impactArea(
          layer: layer,
          impactX: grenade!.impactXRatio,
          impactY: grenade!.impactYRatio,
          existingStrokes: grenade!.impactAreaStrokes,
          grenadeType: grenade!.type,
        ),
      ),
    );

    if (result == null || result['strokes'] == null) return;
    final isar = ref.read(isarProvider);
    final newStrokes = result['strokes'] as String;
    await isar.writeTxn(() async {
      final g = await isar.grenades.get(grenade!.id);
      if (g != null) {
        g.impactAreaStrokes = newStrokes;
        g.updatedAt = DateTime.now();
        await isar.grenades.put(g);
      }
    });
    grenade!.impactAreaStrokes = newStrokes;
    grenade!.updatedAt = DateTime.now();
    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ 爆点区域已保存'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _clearImpactPoint() async {
    if (grenade == null) return;
    final isWallbang = grenade!.type == GrenadeType.wallbang;
    final confirm = await showClearImpactPointDialog(
      context,
      isWallbang: isWallbang,
    );
    if (confirm != true) return;

    final isar = ref.read(isarProvider);
    grenade!.impactXRatio = null;
    grenade!.impactYRatio = null;
    grenade!.impactAreaStrokes = null;
    grenade!.updatedAt = DateTime.now();

    await isar.writeTxn(() async {
      await isar.grenades.put(grenade!);
    });

    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isWallbang ? '穿线已清除' : '爆点已清除'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _deleteGrenade() async {
    if (grenade == null) return;
    final confirm = await showDetailDeleteConfirmDialog(
      context,
      title: '确认删除',
      content: '删除后无法恢复，确定要删除这个道具吗？',
    );
    if (confirm != true) return;

    final isar = ref.read(isarProvider);
    await DataService(isar).deleteGrenades([grenade!]);
    sendOverlayCommand('reload_data');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _startAddStep() async {
    final result = await showAddStepBottomSheet(context);
    if (result == null || !mounted) return;
    switch (result.action) {
      case AddStepAction.textOnly:
        await _saveStep(result.title, result.description);
      case AddStepAction.withImage:
        await _pickMediaForNewStep(result.title, result.description, true);
      case AddStepAction.withVideo:
        await _pickMediaForNewStep(result.title, result.description, false);
    }
  }

  Future<void> _saveStep(
    String title,
    String desc, {
    String? mediaPath,
    int? mediaType,
  }) async {
    final isar = ref.read(isarProvider);
    final step = GrenadeStep(
      title: title,
      description: desc,
      stepIndex: grenade!.steps.length,
    );

    try {
      await isar.writeTxn(() async {
        await isar.grenadeSteps.put(step);
        step.grenade.value = grenade;
        await step.grenade.save();

        if (mediaPath != null && mediaType != null) {
          final media = StepMedia(
            localPath: mediaPath,
            type: mediaType,
            sortOrder: 0,
          );
          await isar.stepMedias.put(media);
          media.step.value = step;
          await media.step.save();
          step.medias.add(media);
          await step.medias.save();
        }

        grenade!.steps.add(step);
        await grenade!.steps.save();
        grenade!.updatedAt = DateTime.now();
        await isar.grenades.put(grenade!);
      });
    } catch (_) {
      if (mediaPath != null) {
        await DataService.deleteMediaFile(mediaPath);
      }
      rethrow;
    }
    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
  }

  Future<void> _pickMediaForNewStep(
    String title,
    String desc,
    bool isImage,
  ) async {
    final dataPath = ref.read(isarProvider).directory ?? '';
    final path = await pickAndProcessDetailMedia(
      context,
      dataPath: dataPath,
      isImage: isImage,
    );
    if (path == null) return;
    if (!mounted) {
      await DataService.deleteMediaFile(path);
      return;
    }
    await _saveStep(
      title,
      desc,
      mediaPath: path,
      mediaType: isImage ? MediaType.image : MediaType.video,
    );
  }

  Future<void> _appendMediaToStep(GrenadeStep step, bool isImage) async {
    final isar = ref.read(isarProvider);
    final path = await pickAndProcessDetailMedia(
      context,
      dataPath: isar.directory ?? '',
      isImage: isImage,
    );
    if (path == null) return;
    if (!mounted) {
      await DataService.deleteMediaFile(path);
      return;
    }

    final maxSortOrder = step.medias.isEmpty
        ? -1
        : step.medias
            .toList()
            .map((m) => m.sortOrder)
            .reduce((a, b) => a > b ? a : b);
    final media = StepMedia(
      localPath: path,
      type: isImage ? MediaType.image : MediaType.video,
      sortOrder: maxSortOrder + 1,
    );
    try {
      await isar.writeTxn(() async {
        await isar.stepMedias.put(media);
        media.step.value = step;
        await media.step.save();
        step.medias.add(media);
        await step.medias.save();
      });
    } catch (_) {
      await DataService.deleteMediaFile(path);
      rethrow;
    }
    await _markAsLocallyEdited();
    if (mounted) setState(() {});
    sendOverlayCommand('reload_data');
  }

  Future<void> _editStep(GrenadeStep step) async {
    final result = await showEditStepBottomSheet(
      context,
      initialTitle: step.title,
      initialDescription: step.description,
    );
    if (result == null || !mounted) return;

    final isar = ref.read(isarProvider);
    step.title = result.title;
    step.description = result.description;
    await isar.writeTxn(() async {
      await isar.grenadeSteps.put(step);
      grenade!.updatedAt = DateTime.now();
      await isar.grenades.put(grenade!);
    });
    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('步骤已更新'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _editImage(StepMedia media) async {
    if (grenade == null) return;
    final updated = await editDetailStepImage(
      context,
      isar: ref.read(isarProvider),
      grenade: grenade!,
      media: media,
      onCommitted: () async {
        await _markAsLocallyEdited();
        sendOverlayCommand('reload_data');
      },
    );
    if (!updated || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('图片已更新'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _confirmDeleteMedia(StepMedia media) async {
    final confirm = await showDetailDeleteConfirmDialog(
      context,
      title: '确认删除',
      content: media.type == MediaType.image ? '确定要删除这张图片吗？' : '确定要删除这个视频吗？',
    );
    if (confirm != true) return;

    final isar = ref.read(isarProvider);
    await DataService(isar).deleteStepMedia(media);
    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
  }

  Future<void> _deleteStep(GrenadeStep step) async {
    final isar = ref.read(isarProvider);
    await DataService(isar).deleteStep(step);
    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
  }

  Future<void> _swapMediaOrder(
    GrenadeStep step,
    int fromIndex,
    int toIndex,
  ) async {
    final mediaList = step.medias.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (fromIndex < 0 ||
        fromIndex >= mediaList.length ||
        toIndex < 0 ||
        toIndex >= mediaList.length) {
      return;
    }

    final isar = ref.read(isarProvider);
    // 默认 sortOrder 全相同时先按当前顺序补齐索引
    final allSameSortOrder =
        mediaList.every((m) => m.sortOrder == mediaList.first.sortOrder);
    if (allSameSortOrder && mediaList.length > 1) {
      for (int i = 0; i < mediaList.length; i++) {
        mediaList[i].sortOrder = i;
      }
      await isar.writeTxn(() async {
        for (final m in mediaList) {
          await isar.stepMedias.put(m);
        }
      });
    }

    final fromMedia = mediaList[fromIndex];
    final toMedia = mediaList[toIndex];
    final tempOrder = fromMedia.sortOrder;
    fromMedia.sortOrder = toMedia.sortOrder;
    toMedia.sortOrder = tempOrder;

    await isar.writeTxn(() async {
      await isar.stepMedias.put(fromMedia);
      await isar.stepMedias.put(toMedia);
      grenade!.updatedAt = DateTime.now();
      await isar.grenades.put(grenade!);
    });

    await _markAsLocallyEdited();
    await _loadData(resetTitle: false);
    sendOverlayCommand('reload_data');
  }

  Future<void> _editAuthor() async {
    final author = await showEditAuthorBottomSheet(
      context,
      initialAuthor: grenade?.author ?? '',
      authorHistory: _authorHistory,
      defaultAuthor: defaultGrenadeAuthor,
    );
    if (author == null || !mounted) return;
    await _updateGrenade(author: author);
    if (author.isNotEmpty) {
      await _saveAuthorToHistory(author);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('作者已更新'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _editSource() async {
    final result = await showEditSourceBottomSheet(
      context,
      initialUrl: grenade?.sourceUrl ?? '',
      initialNote: grenade?.sourceNote ?? '',
    );
    if (result == null || !mounted) return;
    await _updateGrenade(sourceUrl: result.url, sourceNote: result.note);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('出处信息已更新'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  bool _hasTitleChanges() {
    if (!widget.isEditing || _originalTitle == null) return false;
    return _titleController.text != _originalTitle;
  }

  Future<bool> _onWillPop() async {
    if (!_hasTitleChanges()) return true;
    final result = await showUnsavedTitleDialog(context);
    if (result == 'save') {
      await _updateGrenade(title: _titleController.text);
      return true;
    }
    return result == 'discard';
  }

  Future<void> _handlePopInvoked(bool didPop) async {
    if (didPop) return;
    final shouldPop = await _onWillPop();
    if (shouldPop && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (grenade == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isEditing = widget.isEditing;
    final steps = _sortedSteps();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _handlePopInvoked(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: isEditing
              ? TextField(
                  controller: _titleController,
                  style: TextStyle(
                    color: Theme.of(context).appBarTheme.foregroundColor,
                    fontSize: 18,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '输入标题',
                    hintStyle: TextStyle(color: Theme.of(context).hintColor),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                      ),
                      tooltip: '保存标题',
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        _updateGrenade(title: _titleController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('标题已更新'),
                            duration: Duration(milliseconds: 500),
                          ),
                        );
                      },
                    ),
                  ),
                  onSubmitted: (val) => _updateGrenade(title: val),
                )
              : Text(grenade!.title),
          actions: [
            IconButton(
              icon: Icon(
                grenade!.isFavorite ? Icons.star : Icons.star_border,
                color: Colors.yellowAccent,
              ),
              onPressed: _handleFavoriteAction,
            ),
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _deleteGrenade,
              ),
          ],
        ),
        body: Column(
          children: [
            GrenadeDetailHeader(
              isEditing: isEditing,
              grenadeType: grenade!.type,
              grenadeTeam: grenade!.team,
              stepCount: steps.length,
              onTypeChanged: (value) => _updateGrenade(type: value),
            ),
            Expanded(
              child: GrenadeResponsiveStepLayout(
                steps: steps,
                onSelectStep: _focusStep,
                content: _buildStepList(isEditing, steps),
              ),
            ),
          ],
        ),
        floatingActionButton: isEditing
            ? FloatingActionButton.extended(
                onPressed: _startAddStep,
                icon: const Icon(Icons.add),
                label: const Text('添加步骤'),
                backgroundColor: Colors.orange,
              )
            : null,
      ),
    );
  }

  Widget _buildStepList(bool isEditing, List<GrenadeStep> steps) {
    final hasImpactPoint =
        grenade!.impactXRatio != null && grenade!.impactYRatio != null;
    final showImpactCard = isEditing || hasImpactPoint;

    if (steps.isEmpty && !showImpactCard) {
      return const Center(
        child: Text('暂无教学步骤', style: TextStyle(color: Colors.grey)),
      );
    }

    final mapId = _resolveMapIdSync();
    final tagService = TagService(ref.read(isarProvider));

    return ListView(
      controller: _stepScrollController,
      padding: const EdgeInsets.all(16),
      children: [
        if (showImpactCard)
          ImpactPointSectionCard(
            grenade: grenade!,
            isEditing: isEditing,
            pickThrowPoint: widget.pickThrowPoint,
            onViewImpactPoint: _viewImpactPoint,
            onPickThrowPoint: _pickThrowPoint,
            onPickImpactPoint: _pickImpactPoint,
            onClearImpactPoint: _clearImpactPoint,
            onDrawImpactArea: _drawImpactArea,
          ),
        if (mapId != null)
          GrenadeTagSection(
            grenadeId: grenade!.id,
            mapId: mapId,
            tagService: tagService,
            isEditing: isEditing,
            cachedTags: _grenadeTags,
            onTagsChanged: () {
              _loadData(resetTitle: false);
              sendOverlayCommand('reload_data');
            },
          ),
        ...steps.map(
          (step) => KeyedSubtree(
            key: _stepKeys.putIfAbsent(step.id, GlobalKey.new),
            child: GrenadeStepCard(
              step: step,
              isEditing: isEditing,
              onEditStep: () => _editStep(step),
              onAddImage: () => _appendMediaToStep(step, true),
              onAddVideo: () => _appendMediaToStep(step, false),
              onDeleteStep: () => _deleteStep(step),
              onSwapMediaOrder: (fromIndex, toIndex) =>
                  _swapMediaOrder(step, fromIndex, toIndex),
              onOpenFullscreenImage: (path) =>
                  showFullscreenDetailImage(context, path),
              onEditImage: _editImage,
              onDeleteMedia: _confirmDeleteMedia,
            ),
          ),
        ),
        GrenadeDetailFooter(
          grenade: grenade!,
          isEditing: isEditing,
          onEditAuthor: _editAuthor,
          onEditSource: _editSource,
        ),
      ],
    );
  }
}
