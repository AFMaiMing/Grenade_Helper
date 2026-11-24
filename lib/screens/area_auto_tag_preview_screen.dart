import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:photo_view/photo_view.dart';

import '../models.dart';
import '../models/map_area.dart';
import '../providers.dart';
import '../services/area/area_geometry.dart';
import '../services/area_service.dart';
import '../widgets/path_image_provider.dart';
import 'area_auto_tag/area_preview_widgets.dart';
import 'area_auto_tag/area_scope_painter.dart';

/// 区域可视化自动打标签预览页面。
class AreaAutoTagPreviewScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;
  final MapArea area;

  const AreaAutoTagPreviewScreen({
    super.key,
    required this.gameMap,
    required this.area,
  });

  @override
  ConsumerState<AreaAutoTagPreviewScreen> createState() =>
      _AreaAutoTagPreviewScreenState();
}

class _AreaAutoTagPreviewScreenState
    extends ConsumerState<AreaAutoTagPreviewScreen> {
  late final PhotoViewController _photoViewController;
  late final AreaService _areaService;

  bool _isLoading = true;
  bool _isSyncing = false;
  bool _showImpact = false;
  bool _tagByImpact = false;
  bool _showOnlyMatched = false;

  MapLayer? _layer;
  List<Grenade> _grenades = [];
  Set<int> _inAreaThrowIds = {};
  Set<int> _inAreaImpactIds = {};
  List<AreaStrokeData> _strokes = [];

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    final isar = ref.read(isarProvider);
    _areaService = AreaService(isar);
    _strokes = parseAreaStrokes(widget.area.strokes);
    _loadData();
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final isar = ref.read(isarProvider);

    MapLayer? layer;
    if (widget.area.layerId != null) {
      layer = await isar.mapLayers.get(widget.area.layerId!);
    } else {
      widget.gameMap.layers.loadSync();
      if (widget.gameMap.layers.isNotEmpty) {
        layer = widget.gameMap.layers.first;
      }
    }

    if (layer == null) {
      if (!mounted) return;
      setState(() {
        _layer = null;
        _grenades = [];
        _inAreaThrowIds = {};
        _inAreaImpactIds = {};
        _isLoading = false;
      });
      return;
    }

    final grenades = await isar.grenades
        .filter()
        .layer((q) => q.idEqualTo(layer!.id))
        .findAll();

    final inAreaThrowIds = <int>{};
    final inAreaImpactIds = <int>{};
    for (final g in grenades) {
      if (_areaService.isPointInArea(g.xRatio, g.yRatio, widget.area)) {
        inAreaThrowIds.add(g.id);
      }
      if (g.impactXRatio != null &&
          g.impactYRatio != null &&
          _areaService.isPointInArea(
              g.impactXRatio!, g.impactYRatio!, widget.area)) {
        inAreaImpactIds.add(g.id);
      }
    }

    if (!mounted) return;
    setState(() {
      _layer = layer;
      _grenades = grenades;
      _inAreaThrowIds = inAreaThrowIds;
      _inAreaImpactIds = inAreaImpactIds;
      _isLoading = false;
    });
  }

  Future<void> _syncAreaTag() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final result = await _areaService.syncAreaTag(widget.area,
        useImpactPoint: _tagByImpact);

    if (!mounted) return;
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '${_tagByImpact ? "按爆点" : "按站位"}同步：处理${result.processedGrenades}个，命中${result.matchedGrenades}个，新增${result.addedLinks}条，移除${result.removedLinks}条'),
      backgroundColor: Colors.green,
    ));
  }

  int get _displayTotal {
    if (_showImpact) {
      return _grenades
          .where((g) => g.impactXRatio != null && g.impactYRatio != null)
          .length;
    }
    return _grenades.length;
  }

  int get _displayMatched =>
      _showImpact ? _inAreaImpactIds.length : _inAreaThrowIds.length;

  Future<void> _showGrenadeListForPoint(Grenade anchor) async {
    final matchedSet = _showImpact ? _inAreaImpactIds : _inAreaThrowIds;
    if (!matchedSet.contains(anchor.id)) return;

    final group = _grenades.where((g) {
      if (!matchedSet.contains(g.id)) return false;
      if (_showImpact) {
        if (anchor.impactXRatio == null ||
            anchor.impactYRatio == null ||
            g.impactXRatio == null ||
            g.impactYRatio == null) {
          return false;
        }
        return (g.impactXRatio! - anchor.impactXRatio!).abs() < 1e-6 &&
            (g.impactYRatio! - anchor.impactYRatio!).abs() < 1e-6;
      }
      return (g.xRatio - anchor.xRatio).abs() < 1e-6 &&
          (g.yRatio - anchor.yRatio).abs() < 1e-6;
    }).toList();

    final items = group.isEmpty ? [anchor] : group;
    if (!mounted) return;
    await showAreaMatchedGrenadesSheet(context, items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('区域可视化标注 - ${widget.area.name}'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新数据',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _layer == null
              ? const Center(child: Text('区域关联楼层不存在，无法预览'))
              : Column(
                  children: [
                    AreaPreviewHeader(
                      displayMatched: _displayMatched,
                      displayTotal: _displayTotal,
                      showImpact: _showImpact,
                      tagByImpact: _tagByImpact,
                      showOnlyMatched: _showOnlyMatched,
                      onShowImpactChanged: (v) =>
                          setState(() => _showImpact = v),
                      onTagByImpactChanged: (v) =>
                          setState(() => _tagByImpact = v),
                      onShowOnlyMatchedChanged: (v) =>
                          setState(() => _showOnlyMatched = v),
                    ),
                    Expanded(child: _buildMapPreview()),
                    AreaPreviewBottomBar(
                      isLoading: _isLoading,
                      isSyncing: _isSyncing,
                      onRefresh: _loadData,
                      onSync: _syncAreaTag,
                    ),
                  ],
                ),
    );
  }

  Widget _buildMapPreview() {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imageBounds = computeAreaPreviewImageBounds(
              constraints.maxWidth, constraints.maxHeight);
          return PhotoView.customChild(
            controller: _photoViewController,
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 4.0,
            initialScale: PhotoViewComputedScale.contained,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            child: Stack(
              children: [
                _buildLayerImage(constraints),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: AreaScopePainter(
                        strokes: _strokes,
                        color: Color(widget.area.colorValue),
                        imageBounds: imageBounds,
                      ),
                    ),
                  ),
                ),
                ..._buildMarkers(imageBounds),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLayerImage(BoxConstraints constraints) {
    final provider = imageProviderFromPath(_layer!.assetPath);
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
  }

  List<Widget> _buildMarkers(AreaPreviewImageBounds imageBounds) {
    const markerSize = 14.0;
    final widgets = <Widget>[];

    for (final g in _grenades) {
      double? x;
      double? y;
      bool matched;
      IconData icon;

      if (_showImpact) {
        if (g.impactXRatio == null || g.impactYRatio == null) continue;
        x = g.impactXRatio!;
        y = g.impactYRatio!;
        matched = _inAreaImpactIds.contains(g.id);
        icon = Icons.adjust;
      } else {
        x = g.xRatio;
        y = g.yRatio;
        matched = _inAreaThrowIds.contains(g.id);
        icon = Icons.place;
      }

      if (_showOnlyMatched && !matched) continue;
      final color = matched ? Colors.greenAccent : Colors.white54;
      widgets.add(Positioned(
        left: imageBounds.offsetX + x * imageBounds.width - markerSize / 2,
        top: imageBounds.offsetY + y * imageBounds.height - markerSize / 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: matched ? () => _showGrenadeListForPoint(g) : null,
          child: Container(
            width: markerSize,
            height: markerSize,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.4),
            ),
            child: Icon(icon, size: 10, color: color),
          ),
        ),
      ));
    }
    return widgets;
  }
}
