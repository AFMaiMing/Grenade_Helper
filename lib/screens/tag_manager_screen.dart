import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import '../providers.dart';
import '../services/area_service.dart';
import '../services/tag_service.dart';
import 'area_draw_screen.dart';
import 'tag_manager/tag_group_list.dart';
import 'tag_manager/tag_manager_dialogs.dart';

/// 地图标签管理页面。
class TagManagerScreen extends ConsumerStatefulWidget {
  final int mapId;
  final String mapName;

  const TagManagerScreen({
    super.key,
    required this.mapId,
    required this.mapName,
  });

  @override
  ConsumerState<TagManagerScreen> createState() => _TagManagerScreenState();
}

class _TagManagerScreenState extends ConsumerState<TagManagerScreen> {
  late TagService _tagService;
  List<Tag> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final isar = ref.read(isarProvider);
    _tagService = TagService(isar);
    await _tagService.initializeSystemTags(widget.mapId, widget.mapName);
    await _loadTags();
  }

  Future<void> _loadTags() async {
    if (mounted) setState(() => _isLoading = true);
    final tags = await _tagService.getAllTags(widget.mapId);
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _isLoading = false;
    });
  }

  static int _compareAreasByRecency(MapArea a, MapArea b) {
    if (a.updatedAt.isAfter(b.updatedAt)) return -1;
    if (a.updatedAt.isBefore(b.updatedAt)) return 1;
    if (a.createdAt.isAfter(b.createdAt)) return -1;
    if (a.createdAt.isBefore(b.createdAt)) return 1;
    return b.id.compareTo(a.id);
  }

  Future<List<AreaTemplateOption>> _loadAreaTemplateOptions() async {
    final isar = ref.read(isarProvider);
    final areas =
        await isar.mapAreas.filter().mapIdEqualTo(widget.mapId).findAll();
    if (areas.isEmpty) return const [];

    final layerNameById = <int, String>{};
    for (final area in areas) {
      final layerId = area.layerId;
      if (layerId == null || layerNameById.containsKey(layerId)) continue;
      final layer = await isar.mapLayers.get(layerId);
      if (layer != null) {
        layerNameById[layerId] = layer.name;
      }
    }

    final sorted = List<MapArea>.from(areas)..sort(_compareAreasByRecency);
    return sorted
        .map(
          (area) => AreaTemplateOption(
            areaId: area.id,
            label:
                '${area.name}${area.layerId != null ? " · ${layerNameById[area.layerId] ?? "未知楼层"}" : ""}',
          ),
        )
        .toList(growable: false);
  }

  Future<MapLayer?> _selectLayer(List<MapLayer> layers) async {
    return showDialog<MapLayer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择楼层'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: layers
              .map(
                (l) => ListTile(
                  title: Text(l.name),
                  onTap: () => Navigator.pop(ctx, l),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<MapArea?> _findLatestAreaForTag(int tagId) async {
    final isar = ref.read(isarProvider);
    final areas = await isar.mapAreas
        .filter()
        .mapIdEqualTo(widget.mapId)
        .tagIdEqualTo(tagId)
        .findAll();
    if (areas.isEmpty) return null;
    areas.sort(_compareAreasByRecency);
    return areas.first;
  }

  Future<void> _openAreaDrawForTag(Tag tag, {MapArea? area}) async {
    final isar = ref.read(isarProvider);
    final gameMap = await isar.gameMaps.get(widget.mapId);
    if (gameMap == null) return;

    await gameMap.layers.load();
    final layers = gameMap.layers.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (layers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('当前地图没有楼层，无法编辑区域'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    MapLayer? layer;
    if (area != null && area.layerId != null) {
      final matched = layers.where((l) => l.id == area.layerId);
      if (matched.isNotEmpty) layer = matched.first;
    }
    layer ??= layers.length == 1 ? layers.first : await _selectLayer(layers);
    if (layer == null || !mounted) return;
    final selectedLayer = layer;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) {
          final enableMultiLayer = tag.dimension == TagDimension.area;
          return AreaDrawScreen(
            gameMap: gameMap,
            layer: selectedLayer,
            area: area,
            existingTagId: enableMultiLayer ? tag.id : null,
            initialName: tag.name,
            initialColor: tag.colorValue,
            lockName: true,
          );
        },
      ),
    );
  }

  Future<void> _handleAreaTagPostSetup(
    Tag tag,
    Map<String, dynamic> dialogResult,
  ) async {
    if (tag.dimension != TagDimension.area) return;

    final setupMode = dialogResult['areaSetupMode'] as String? ?? 'none';
    if (setupMode == 'none') return;
    final continueEditAfterReuse =
        dialogResult['continueEditAfterReuse'] as bool? ?? false;

    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    final latestArea = await _findLatestAreaForTag(tag.id);

    if (setupMode == 'reuse') {
      final sourceAreaId = dialogResult['sourceAreaId'] as int?;
      if (sourceAreaId == null) return;
      final sourceArea = await isar.mapAreas.get(sourceAreaId);
      if (sourceArea == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('所选区域模板不存在'),
          backgroundColor: Colors.red,
        ));
        return;
      }

      final MapArea targetArea;
      if (latestArea != null) {
        await areaService.updateArea(
          area: latestArea,
          name: tag.name,
          colorValue: tag.colorValue,
          strokes: sourceArea.strokes,
          layerId: sourceArea.layerId,
        );
        targetArea = latestArea;
      } else {
        targetArea = await areaService.createArea(
          name: tag.name,
          colorValue: tag.colorValue,
          strokes: sourceArea.strokes,
          mapId: widget.mapId,
          layerId: sourceArea.layerId,
          existingTagId: tag.id,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已复用区域数据'),
        duration: Duration(seconds: 1),
      ));
      if (continueEditAfterReuse) {
        await _openAreaDrawForTag(tag, area: targetArea);
      }
      return;
    }

    if (setupMode == 'edit') {
      await _openAreaDrawForTag(tag, area: latestArea);
    }
  }

  Future<void> _createTag() async {
    final templateOptions = await _loadAreaTemplateOptions();
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => TagEditDialog(areaTemplateOptions: templateOptions),
    );
    if (result != null && result['action'] == 'save') {
      final createdTag = await _tagService.createTag(
        widget.mapId,
        result['name'],
        result['color'],
        dimension: result['dimension'],
      );
      await _handleAreaTagPostSetup(createdTag, result);
      await _loadTags();
    }
  }

  Future<void> _editTag(Tag tag) async {
    // 允许编辑系统标签，但提示可能会影响默认逻辑
    final templateOptions = await _loadAreaTemplateOptions();
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => TagEditDialog(
        initialName: tag.name,
        initialColor: tag.colorValue,
        initialDimension: tag.dimension,
        areaTemplateOptions: templateOptions,
      ),
    );
    if (result == null) return;
    if (result['action'] == 'delete') {
      await _deleteTag(tag);
      return;
    }
    if (result['action'] == 'save') {
      tag.name = result['name'];
      tag.colorValue = result['color'];
      tag.dimension = result['dimension'];
      await _tagService.updateTag(tag);
      await _handleAreaTagPostSetup(tag, result);
      await _loadTags();
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final isar = ref.read(isarProvider);
    final relatedAreaCount =
        await isar.mapAreas.filter().tagIdEqualTo(tag.id).count();
    if (!mounted) return;

    final result = await showDeleteTagConfirmDialog(
      context,
      tag,
      relatedAreaCount,
    );
    if (result?['confirm'] == true) {
      await _tagService.deleteTag(
        tag.id,
        deleteRelatedAreas: result?['deleteRelatedAreas'] == true,
      );
      await _loadTags();
    }
  }

  Future<void> _renameGroup(int dimension) async {
    final result = await showRenameTagGroupDialog(context, dimension);
    if (result != null && result.isNotEmpty) {
      TagDimension.setName(dimension, result);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.mapName} - 标签管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createTag,
            tooltip: '新建标签',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tags.isEmpty
              ? const Center(
                  child: Text('暂无标签', style: TextStyle(color: Colors.grey)),
                )
              : TagGroupList(
                  tags: _tags,
                  onRenameGroup: _renameGroup,
                  onEditTag: _editTag,
                  onDeleteTag: _deleteTag,
                ),
    );
  }
}
