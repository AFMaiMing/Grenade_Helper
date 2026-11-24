import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:isar_community/isar.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../providers.dart';
import '../services/area_service.dart';
import '../widgets/color_picker_widget.dart';
import '../widgets/path_image_provider.dart';
import 'area_draw/area_draw_models.dart';
import 'area_draw/area_draw_toolbar.dart';
import 'area_draw/area_stroke_painter.dart';

/// 统一区域/爆点范围绘制界面
class AreaDrawScreen extends ConsumerStatefulWidget {
  final GameMap? gameMap;
  final MapLayer? layer;
  final int? layerId;
  final MapArea? area;
  final int? existingTagId;
  final String? initialName;
  final int? initialColor;
  final bool lockName;
  final bool isImpactAreaMode;
  final String? existingStrokes;
  final int grenadeType;
  final double? impactX;
  final double? impactY;

  const AreaDrawScreen({
    super.key,
    required GameMap this.gameMap,
    required MapLayer this.layer,
    this.area,
    this.existingTagId,
    this.initialName,
    this.initialColor,
    this.lockName = false,
  })  : isImpactAreaMode = false,
        layerId = null,
        existingStrokes = null,
        grenadeType = GrenadeType.smoke,
        impactX = null,
        impactY = null;

  const AreaDrawScreen.impactArea({
    super.key,
    this.layer,
    this.layerId,
    this.existingStrokes,
    this.grenadeType = GrenadeType.smoke,
    this.impactX,
    this.impactY,
  })  : isImpactAreaMode = true,
        gameMap = null,
        area = null,
        existingTagId = null,
        initialName = null,
        initialColor = null,
        lockName = true;

  @override
  ConsumerState<AreaDrawScreen> createState() => _AreaDrawScreenState();
}

class _AreaDrawScreenState extends ConsumerState<AreaDrawScreen> {
  static const String _lastUsedColorKey = 'area_draw_last_used_color';

  late final PhotoViewController _photoViewController;
  List<MapLayer> _availableLayers = [];
  MapLayer? _selectedLayer;
  final GlobalKey _stackKey = GlobalKey();
  final List<DrawStroke> _strokes = [];
  List<Offset> _currentStroke = [];
  double _currentStrokeWidthRatio = kDefaultAreaBrushRatio;
  bool _currentStrokeSquare = false;

  final List<Offset> _penPoints = [];
  int? _draggingPenPointIndex;

  double _shapeSize = 0.05;
  DrawStroke? _activeShape;

  // 重做栈：元素为被撤销的笔画或钢笔锚点
  final List<Object> _redoStack = [];

  final _nameController = TextEditingController();
  int _selectedColor = 0xFF4CAF50;
  DrawTool _activeTool = DrawTool.move;
  double _brushRatio = kDefaultAreaBrushRatio;
  bool _squareBrush = false;
  Map<int, MapArea> _tagAreasByLayerId = {};
  final Map<int, LayerDraft> _draftByLayerId = {};
  int? _lastUsedColor;

  bool get _isTagBoundMultiLayerMode =>
      !widget.isImpactAreaMode && widget.existingTagId != null;

  bool get _isDrawingActive => _activeTool != DrawTool.move;
  bool get _isEraserMode => _activeTool == DrawTool.eraser;
  bool get _canUndo => _penPoints.isNotEmpty || _strokes.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  int get _activeShapeIndex => _activeShape == null
      ? -1
      : _strokes.indexWhere((s) => identical(s, _activeShape));

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();

    if (widget.isImpactAreaMode) {
      _selectedColor = _resolveImpactColor(widget.grenadeType).toARGB32();
      if (widget.existingStrokes != null &&
          widget.existingStrokes!.isNotEmpty) {
        _loadStrokes(widget.existingStrokes!);
      }
      if (widget.layer != null) {
        _selectedLayer = widget.layer;
      } else if (widget.layerId != null) {
        _loadImpactLayer(widget.layerId!);
      }
      return;
    }

    final gameMap = widget.gameMap!;
    gameMap.layers.loadSync();
    _availableLayers = gameMap.layers.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _selectedLayer = widget.layer;
    if (widget.area != null && widget.area!.layerId != null) {
      final areaLayer =
          _availableLayers.where((l) => l.id == widget.area!.layerId);
      if (areaLayer.isNotEmpty) {
        _selectedLayer = areaLayer.first;
      }
    }

    if (widget.area != null) {
      _nameController.text = widget.area!.name;
      _selectedColor = widget.area!.colorValue;
      _loadStrokes(widget.area!.strokes);
    } else {
      if (widget.initialName != null && widget.initialName!.trim().isNotEmpty) {
        _nameController.text = widget.initialName!.trim();
      }
      if (widget.initialColor != null) {
        _selectedColor = widget.initialColor!;
      }
    }

    if (_isTagBoundMultiLayerMode && _selectedLayer != null) {
      _loadTagBoundAreas(preferredLayerId: _selectedLayer!.id);
    }
    _loadLastUsedColor();
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadImpactLayer(int layerId) async {
    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(layerId);
    if (mounted) {
      setState(() => _selectedLayer = layer);
    }
  }

  Color _resolveImpactColor(int grenadeType) {
    switch (grenadeType) {
      case GrenadeType.molotov:
        return Colors.orange;
      case GrenadeType.smoke:
      default:
        return Colors.white;
    }
  }

  Future<void> _loadLastUsedColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedColor = prefs.getInt(_lastUsedColorKey);
      if (savedColor == null || !mounted) return;
      _lastUsedColor = savedColor;

      if (widget.area != null) return;

      setState(() {
        _selectedColor = savedColor;
      });
      if (_isTagBoundMultiLayerMode) {
        _cacheCurrentLayerDraft();
      }
    } catch (_) {}
  }

  Future<void> _rememberLastUsedColor(int colorValue) async {
    _lastUsedColor = colorValue;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastUsedColorKey, colorValue);
    } catch (_) {}
  }

  bool _isAreaNewer(MapArea a, MapArea b) {
    if (a.updatedAt.isAfter(b.updatedAt)) return true;
    if (a.updatedAt.isBefore(b.updatedAt)) return false;
    if (a.createdAt.isAfter(b.createdAt)) return true;
    if (a.createdAt.isBefore(b.createdAt)) return false;
    return a.id > b.id;
  }

  Future<void> _loadTagBoundAreas({int? preferredLayerId}) async {
    if (!_isTagBoundMultiLayerMode || widget.gameMap == null) return;
    final isar = ref.read(isarProvider);
    final tagId = widget.existingTagId!;
    final all = await isar.mapAreas
        .filter()
        .mapIdEqualTo(widget.gameMap!.id)
        .tagIdEqualTo(tagId)
        .findAll();

    final latestByLayer = <int, MapArea>{};
    for (final area in all) {
      final layerId = area.layerId;
      if (layerId == null) continue;
      final previous = latestByLayer[layerId];
      if (previous == null || _isAreaNewer(area, previous)) {
        latestByLayer[layerId] = area;
      }
    }

    _tagAreasByLayerId = latestByLayer;
    for (final entry in latestByLayer.entries) {
      final layerId = entry.key;
      final area = entry.value;
      _draftByLayerId.putIfAbsent(
        layerId,
        () => LayerDraft(
          name: area.name,
          colorValue: area.colorValue,
          strokes: AreaDrawCodec.decodeStrokes(area.strokes),
        ),
      );
    }
    await _loadLayerAreaState(preferredLayerId ?? _selectedLayer!.id);
  }

  Future<void> _loadLayerAreaState(int layerId) async {
    if (!_isTagBoundMultiLayerMode || !mounted) return;
    final area = _tagAreasByLayerId[layerId];
    final draft = _draftByLayerId[layerId];
    final selected = _availableLayers.firstWhere(
      (l) => l.id == layerId,
      orElse: () => _selectedLayer!,
    );

    setState(() {
      _selectedLayer = selected;
      _strokes.clear();
      _currentStroke = [];
      _penPoints.clear();
      _activeShape = null;
      _redoStack.clear();

      if (draft != null) {
        if (!widget.lockName) {
          _nameController.text = draft.name;
        }
        _selectedColor = draft.colorValue;
        _strokes.addAll(AreaDrawCodec.cloneStrokes(draft.strokes));
      } else if (area != null) {
        if (!widget.lockName) {
          _nameController.text = area.name;
        }
        _selectedColor = area.colorValue;
        _loadStrokes(area.strokes);
      } else {
        if (!widget.lockName) {
          final fallbackName =
              (widget.initialName ?? widget.area?.name ?? '').trim();
          if (fallbackName.isNotEmpty) {
            _nameController.text = fallbackName;
          }
        }
        if (_lastUsedColor != null) {
          _selectedColor = _lastUsedColor!;
        } else if (widget.initialColor != null) {
          _selectedColor = widget.initialColor!;
        }
      }
    });
  }

  void _loadStrokes(String json) {
    final parsed = AreaDrawCodec.decodeStrokes(json);
    _strokes.addAll(parsed);
    final brushStrokes = _strokes.where((s) => !s.isShape).toList();
    if (brushStrokes.isNotEmpty) {
      _brushRatio = brushStrokes.last.widthRatio
          .clamp(kMinAreaBrushRatio, kMaxAreaBrushRatio);
      _squareBrush = brushStrokes.last.isSquare;
    }
  }

  void _cacheCurrentLayerDraft() {
    if (!_isTagBoundMultiLayerMode || _selectedLayer == null) return;
    final fallbackName = widget.area?.name ?? widget.initialName ?? '';
    final draftName = _nameController.text.trim().isEmpty
        ? fallbackName.trim()
        : _nameController.text.trim();
    final mergedStrokes = AreaDrawCodec.cloneStrokes(_strokes);
    if (_currentStroke.isNotEmpty) {
      mergedStrokes.add(DrawStroke(
        points: List<Offset>.from(_currentStroke),
        widthRatio: _currentStrokeWidthRatio,
        isEraser: _isEraserMode,
        isSquare: _currentStrokeSquare,
      ));
    }
    if (_penPoints.length >= 3) {
      mergedStrokes.add(DrawStroke(
        points: List<Offset>.from(_penPoints),
        widthRatio: kDefaultAreaBrushRatio,
        isEraser: false,
        isShape: true,
      ));
    }
    _draftByLayerId[_selectedLayer!.id] = LayerDraft(
      name: draftName,
      colorValue: _selectedColor,
      strokes: mergedStrokes,
    );
  }

  void _handleMouseWheelZoom(
    PointerScrollEvent event,
    BoxConstraints constraints,
  ) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final double scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) return;

    final double zoomFactor = scrollDelta > 0 ? 0.9 : 1.1;
    final double currentScale = _photoViewController.scale ?? 1.0;
    final Offset currentPosition = _photoViewController.position;

    const minScale = 0.8;
    const maxScale = 5.0;
    final double newScale =
        (currentScale * zoomFactor).clamp(minScale, maxScale);

    if ((newScale - currentScale).abs() < 0.0001) return;

    final Size size = renderBox.size;
    final Offset viewportCenter = size.center(Offset.zero);
    final Offset cursorPosition = event.localPosition - viewportCenter;

    final double scaleRatio = newScale / currentScale;
    final Offset newPosition =
        cursorPosition * (1 - scaleRatio) + currentPosition * scaleRatio;

    _photoViewController.scale = newScale;
    _photoViewController.position = newPosition;
  }

  Offset? _localToRatio(Offset localPos, DrawImageBounds imageBounds) {
    final ratio = Offset(
      (localPos.dx - imageBounds.offsetX) / imageBounds.width,
      (localPos.dy - imageBounds.offsetY) / imageBounds.height,
    );
    if (ratio.dx < 0 || ratio.dx > 1 || ratio.dy < 0 || ratio.dy > 1) {
      return null;
    }
    return ratio;
  }

  int? _hitTestPenVertex(
    Offset ratio,
    DrawImageBounds imageBounds,
    double scale,
  ) {
    if (_penPoints.isEmpty) return null;
    final hitRadiusRatio =
        (16.0 / (imageBounds.width * scale)).clamp(0.008, 0.045);
    final hitRadiusSq = hitRadiusRatio * hitRadiusRatio;
    for (var i = 0; i < _penPoints.length; i++) {
      final d = _penPoints[i] - ratio;
      if (d.dx * d.dx + d.dy * d.dy <= hitRadiusSq) {
        return i;
      }
    }
    return null;
  }

  void _commitPenPolygon({bool clearIfIncomplete = true}) {
    if (_penPoints.length >= 3) {
      _strokes.add(DrawStroke(
        points: List<Offset>.from(_penPoints),
        widthRatio: kDefaultAreaBrushRatio,
        isEraser: false,
        isShape: true,
        shapeType: 0,
      ));
      _penPoints.clear();
      _draggingPenPointIndex = null;
      _redoStack.clear();
      _cacheCurrentLayerDraft();
    } else if (clearIfIncomplete && _penPoints.isNotEmpty) {
      _penPoints.clear();
      _draggingPenPointIndex = null;
    }
  }

  void _placePresetShapeAt(Offset center) {
    final shapeType = _activeTool == DrawTool.circle
        ? 1
        : (_activeTool == DrawTool.square ? 2 : 0);
    if (shapeType == 0) return;

    final points = shapeType == 1
        ? AreaDrawCodec.generateCirclePoints(center, _shapeSize, 32)
        : AreaDrawCodec.generateSquarePoints(center, _shapeSize);

    final shape = DrawStroke(
      points: points,
      widthRatio: kDefaultAreaBrushRatio,
      isEraser: false,
      isShape: true,
      shapeType: shapeType,
      center: center,
    );
    setState(() {
      final idx = _activeShapeIndex;
      if (idx == -1) {
        _strokes.add(shape);
        _redoStack.clear();
      } else {
        _strokes[idx] = shape;
      }
      _activeShape = shape;
    });
    _cacheCurrentLayerDraft();
  }

  void _startNewShape() {
    setState(() => _activeShape = null);
  }

  void _updateActivePresetShape({int? targetShapeType}) {
    final idx = _activeShapeIndex;
    if (idx == -1) return;

    final existing = _strokes[idx];
    final center =
        existing.center ?? AreaDrawCodec.computePolygonCenter(existing.points);
    final shapeType = targetShapeType ?? existing.shapeType;
    final points = shapeType == 1
        ? AreaDrawCodec.generateCirclePoints(center, _shapeSize, 32)
        : AreaDrawCodec.generateSquarePoints(center, _shapeSize);

    setState(() {
      final updated = DrawStroke(
        points: points,
        widthRatio: existing.widthRatio,
        isEraser: false,
        isShape: true,
        shapeType: shapeType,
        center: center,
      );
      _strokes[idx] = updated;
      _activeShape = updated;
    });
    _cacheCurrentLayerDraft();
  }

  void _onCanvasTapDown(
    TapDownDetails details,
    DrawImageBounds imageBounds,
    double scale,
  ) {
    final ratio = _localToRatio(details.localPosition, imageBounds);
    if (ratio == null) return;

    if (_activeTool == DrawTool.pen) {
      final hitIdx = _hitTestPenVertex(ratio, imageBounds, scale);
      if (hitIdx == 0 && _penPoints.length >= 3) {
        setState(() => _commitPenPolygon());
        return;
      }
      if (hitIdx != null) {
        return;
      }
      setState(() {
        _penPoints.add(ratio);
        _redoStack.clear();
      });
      _cacheCurrentLayerDraft();
      return;
    }

    if (_activeTool == DrawTool.circle || _activeTool == DrawTool.square) {
      _placePresetShapeAt(ratio);
      return;
    }

    if (_activeTool == DrawTool.brush || _activeTool == DrawTool.eraser) {
      setState(() {
        _currentStroke = [ratio];
        _currentStrokeWidthRatio = _brushRatio;
        _currentStrokeSquare = _squareBrush;
      });
    }
  }

  void _onCanvasTapUp(TapUpDetails details) {
    if (_activeTool == DrawTool.brush || _activeTool == DrawTool.eraser) {
      _finishFreehandStroke();
    }
  }

  void _onPanStart(
    DragStartDetails details,
    DrawImageBounds imageBounds,
    double scale,
  ) {
    final ratio = _localToRatio(details.localPosition, imageBounds);
    if (ratio == null) return;

    if (_activeTool == DrawTool.pen) {
      final hitIdx = _hitTestPenVertex(ratio, imageBounds, scale);
      if (hitIdx != null) {
        _draggingPenPointIndex = hitIdx;
      }
      return;
    }

    if (_activeTool == DrawTool.circle || _activeTool == DrawTool.square) {
      _placePresetShapeAt(ratio);
      return;
    }

    if (_activeTool == DrawTool.brush || _activeTool == DrawTool.eraser) {
      setState(() {
        _currentStroke = [ratio];
        _currentStrokeWidthRatio = _brushRatio;
        _currentStrokeSquare = _squareBrush;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, DrawImageBounds imageBounds) {
    final clampedRatio = Offset(
      ((details.localPosition.dx - imageBounds.offsetX) / imageBounds.width)
          .clamp(0.0, 1.0),
      ((details.localPosition.dy - imageBounds.offsetY) / imageBounds.height)
          .clamp(0.0, 1.0),
    );

    if (_activeTool == DrawTool.pen) {
      final idx = _draggingPenPointIndex;
      if (idx != null && idx >= 0 && idx < _penPoints.length) {
        setState(() => _penPoints[idx] = clampedRatio);
      }
      return;
    }

    if (_activeTool == DrawTool.circle || _activeTool == DrawTool.square) {
      _placePresetShapeAt(clampedRatio);
      return;
    }

    if (_currentStroke.isEmpty) return;

    final last = _currentStroke.last;
    final delta = clampedRatio - last;
    final distance = delta.distance;
    final step = (_currentStrokeWidthRatio * 0.35).clamp(0.001, 0.04);

    setState(() {
      if (distance <= step) {
        _currentStroke.add(clampedRatio);
        return;
      }
      final unit = delta / distance;
      var travelled = step;
      while (travelled < distance) {
        _currentStroke.add(last + unit * travelled);
        travelled += step;
      }
      _currentStroke.add(clampedRatio);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_activeTool == DrawTool.pen) {
      if (_draggingPenPointIndex != null) {
        _draggingPenPointIndex = null;
        _cacheCurrentLayerDraft();
      }
      return;
    }
    _finishFreehandStroke();
  }

  void _finishFreehandStroke() {
    if (_currentStroke.isNotEmpty) {
      setState(() {
        _strokes.add(DrawStroke(
          points: List.from(_currentStroke),
          widthRatio: _currentStrokeWidthRatio,
          isEraser: _isEraserMode,
          isSquare: _currentStrokeSquare,
        ));
        _currentStroke = [];
        _redoStack.clear();
      });
      _cacheCurrentLayerDraft();
    }
  }

  void _switchTool(DrawTool nextTool) {
    if (_activeTool == nextTool) return;
    setState(() {
      if (_activeTool == DrawTool.pen) {
        _commitPenPolygon();
      }
      _activeTool = nextTool;
      if (nextTool == DrawTool.circle) {
        _updateActivePresetShape(targetShapeType: 1);
      } else if (nextTool == DrawTool.square) {
        _updateActivePresetShape(targetShapeType: 2);
      }
    });
  }

  void _undo() {
    setState(() {
      if (_penPoints.isNotEmpty) {
        _redoStack.add(_penPoints.removeLast());
      } else if (_strokes.isNotEmpty) {
        _redoStack.add(_strokes.removeLast());
      }
    });
    _cacheCurrentLayerDraft();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      final item = _redoStack.removeLast();
      if (item is Offset) {
        _penPoints.add(item);
      } else if (item is DrawStroke) {
        _strokes.add(item);
      }
    });
    _cacheCurrentLayerDraft();
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _penPoints.clear();
      _draggingPenPointIndex = null;
      _activeShape = null;
      _redoStack.clear();
    });
    _cacheCurrentLayerDraft();
  }

  Future<void> _selectLayer() async {
    if (_availableLayers.length <= 1 || _selectedLayer == null) return;
    final selected = await showDialog<MapLayer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择区域所属楼层'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _availableLayers
              .map(
                (l) => ListTile(
                  title: Text(l.name),
                  trailing: l.id == _selectedLayer!.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, l),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null || selected.id == _selectedLayer!.id) return;
    if (_penPoints.isNotEmpty) {
      _commitPenPolygon();
    }
    if (_isTagBoundMultiLayerMode) {
      _cacheCurrentLayerDraft();
      await _loadLayerAreaState(selected.id);
      return;
    }
    setState(() => _selectedLayer = selected);
  }

  Future<void> _save() async {
    if (_currentStroke.isNotEmpty) {
      _finishFreehandStroke();
    }
    if (_penPoints.isNotEmpty) {
      setState(() => _commitPenPolygon());
    }

    if (widget.isImpactAreaMode) {
      Navigator.pop(
          context, {'strokes': AreaDrawCodec.encodeStrokes(_strokes)});
      return;
    }

    final fallbackName = widget.area?.name ?? widget.initialName ?? '';
    final typedName = _nameController.text.trim();
    final name = typedName.isNotEmpty ? typedName : fallbackName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入区域名称'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);

    if (_isTagBoundMultiLayerMode) {
      _cacheCurrentLayerDraft();
      final hasAnyStroke =
          _draftByLayerId.values.any((e) => e.strokes.isNotEmpty);
      if (!hasAnyStroke) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请至少绘制一个楼层的区域范围'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final tagId = widget.existingTagId!;
      var savedCount = 0;
      var deletedCount = 0;

      for (final entry in _draftByLayerId.entries) {
        final layerId = entry.key;
        final draft = entry.value;
        final existing = _tagAreasByLayerId[layerId];
        if (draft.strokes.isEmpty) {
          if (existing != null) {
            await areaService.deleteArea(existing, deleteTag: false);
            _tagAreasByLayerId.remove(layerId);
            deletedCount++;
          }
          continue;
        }

        final strokesJson = AreaDrawCodec.encodeStrokes(draft.strokes);
        if (existing == null) {
          final created = await areaService.createArea(
            name: name,
            colorValue: draft.colorValue,
            strokes: strokesJson,
            mapId: widget.gameMap!.id,
            layerId: layerId,
            existingTagId: tagId,
          );
          _tagAreasByLayerId[layerId] = created;
          savedCount++;
          continue;
        }

        final changed = existing.name != name ||
            existing.colorValue != draft.colorValue ||
            existing.strokes != strokesJson ||
            existing.layerId != layerId;
        if (!changed) continue;

        await areaService.updateArea(
          area: existing,
          name: name,
          colorValue: draft.colorValue,
          strokes: strokesJson,
          layerId: layerId,
        );
        savedCount++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('区域 "$name" 已保存：更新/新建$savedCount层，清除$deletedCount层'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    } else if (widget.area != null) {
      if (_strokes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请绘制区域范围'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await areaService.updateArea(
        area: widget.area!,
        name: name,
        colorValue: _selectedColor,
        strokes: AreaDrawCodec.encodeStrokes(_strokes),
        layerId: _selectedLayer!.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('区域 "$name" 更新成功'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      if (_strokes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请绘制区域范围'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await areaService.createArea(
        name: name,
        colorValue: _selectedColor,
        strokes: AreaDrawCodec.encodeStrokes(_strokes),
        mapId: widget.gameMap!.id,
        layerId: _selectedLayer!.id,
        existingTagId: widget.existingTagId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('区域 "$name" 创建成功'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedLayer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isCompactToolbar = MediaQuery.of(context).size.width < 700;
    final overlayOpacity =
        widget.isImpactAreaMode ? ref.watch(impactAreaOpacityProvider) : 0.5;
    final drawColor = Color(_selectedColor);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isImpactAreaMode ? '绘制爆点区域' : '绘制区域 - ${_selectedLayer!.name}',
        ),
        actions: [
          if (!widget.isImpactAreaMode && _availableLayers.length > 1)
            IconButton(
              icon: const Icon(Icons.layers_outlined),
              tooltip: '切换所属楼层',
              onPressed: _selectLayer,
            ),
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _canUndo ? _undo : null,
            tooltip: '撤销 (Ctrl+Z)',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _canRedo ? _redo : null,
            tooltip: '重做 (Ctrl+Y)',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _canUndo ? _clear : null,
            tooltip: '清除',
          ),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
            if (_canUndo) _undo();
          },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              if (!widget.isImpactAreaMode) _buildAreaMetaHeader(),
              Expanded(
                child: ClipRect(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final imageBounds = AreaDrawCodec.computeImageBounds(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          _handleMouseWheelZoom(event, constraints);
                        }
                      },
                      child: PhotoView.customChild(
                        controller: _photoViewController,
                        backgroundDecoration:
                            const BoxDecoration(color: Colors.black),
                        minScale: PhotoViewComputedScale.contained * 0.8,
                        maxScale: PhotoViewComputedScale.covered * 3,
                        initialScale: PhotoViewComputedScale.contained,
                        child: StreamBuilder<PhotoViewControllerValue>(
                          stream: _photoViewController.outputStateStream,
                          builder: (context, snapshot) {
                            final scale = snapshot.data?.scale ?? 1.0;
                            final markerScale = 1.0 / scale;

                            return Stack(
                              key: _stackKey,
                              children: [
                                Builder(builder: (context) {
                                  final provider = imageProviderFromPath(
                                    _selectedLayer!.assetPath,
                                  );
                                  if (provider == null) {
                                    return Container(
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      color: Colors.black,
                                    );
                                  }
                                  return Image(
                                    image: provider,
                                    width: constraints.maxWidth,
                                    height: constraints.maxHeight,
                                    fit: BoxFit.contain,
                                  );
                                }),
                                if (widget.isImpactAreaMode &&
                                    widget.impactX != null &&
                                    widget.impactY != null)
                                  ImpactReferenceMarker(
                                    imageBounds: imageBounds,
                                    markerScale: markerScale,
                                    impactX: widget.impactX!,
                                    impactY: widget.impactY!,
                                  ),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: !_isDrawingActive,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (d) => _onCanvasTapDown(
                                        d,
                                        imageBounds,
                                        scale,
                                      ),
                                      onTapUp: _onCanvasTapUp,
                                      onPanStart: (d) => _onPanStart(
                                        d,
                                        imageBounds,
                                        scale,
                                      ),
                                      onPanUpdate: (d) =>
                                          _onPanUpdate(d, imageBounds),
                                      onPanEnd: _onPanEnd,
                                      child: CustomPaint(
                                        size: constraints.biggest,
                                        painter: AreaStrokePainter(
                                          strokes: _strokes,
                                          currentStroke: _currentStroke,
                                          currentStrokeWidthRatio:
                                              _currentStrokeWidthRatio,
                                          currentIsEraser: _isEraserMode,
                                          currentIsSquare: _currentStrokeSquare,
                                          penPoints: _penPoints,
                                          color: drawColor,
                                          opacity: overlayOpacity,
                                          imageBounds: imageBounds,
                                          markerScale: markerScale,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  }),
                ),
              ),
              AreaDrawBottomToolbar(
                compact: isCompactToolbar,
                drawColor: drawColor,
                isImpactAreaMode: widget.isImpactAreaMode,
                activeTool: _activeTool,
                brushRatio: _brushRatio,
                squareBrush: _squareBrush,
                penPointCount: _penPoints.length,
                shapeSize: _shapeSize,
                hasActiveShape: _activeShapeIndex != -1,
                onSelectTool: _switchTool,
                onSave: _save,
                onSquareBrushChanged: (square) =>
                    setState(() => _squareBrush = square),
                onBrushRatioChanged: (val) => setState(() => _brushRatio = val),
                onCommitPen: () => setState(() => _commitPenPolygon()),
                onClearPen: () => setState(() => _penPoints.clear()),
                onShapeSizeChanged: (val) {
                  setState(() => _shapeSize = val);
                  _updateActivePresetShape();
                },
                onStartNewShape: _startNewShape,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAreaMetaHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (!widget.lockName)
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '区域名称',
                  hintText: '如: A大, 中路...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            )
          else
            Expanded(
              child: Container(
                height: 40,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  '绑定标签：${_nameController.text.trim().isEmpty ? "未命名标签" : _nameController.text.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              final color = await showTagColorPickerDialog(
                context,
                initialColor: _selectedColor,
              );
              if (color != null) {
                setState(() => _selectedColor = color);
                _cacheCurrentLayerDraft();
                _rememberLastUsedColor(color);
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(_selectedColor).withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Color(_selectedColor)),
              ),
              child: Icon(
                Icons.palette,
                color: Color(_selectedColor),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
