import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';

import '../models.dart';
import '../providers.dart';
import '../widgets/path_image_provider.dart';
import 'impact_picker/impact_picker_painters.dart';
import 'impact_picker/impact_picker_widgets.dart';

/// 爆点坐标选择/查看页面
class ImpactPointPickerScreen extends ConsumerStatefulWidget {
  final int grenadeId;
  final double? initialX;
  final double? initialY;
  final double throwX;
  final double throwY;
  final int layerId;
  final String? existingStrokes;
  final int grenadeType;
  final bool readOnly;
  // 投掷点模式：爆点固定(initialX/Y)，点击地图设置投掷点(throwX/Y为初始值)
  final bool pickThrowPoint;
  final bool wallbangLineMode;

  const ImpactPointPickerScreen({
    super.key,
    required this.grenadeId,
    this.initialX,
    this.initialY,
    required this.throwX,
    required this.throwY,
    required this.layerId,
    this.existingStrokes,
    this.grenadeType = GrenadeType.smoke,
    this.readOnly = false,
    this.pickThrowPoint = false,
    this.wallbangLineMode = false,
  });

  @override
  ConsumerState<ImpactPointPickerScreen> createState() =>
      _ImpactPointPickerScreenState();
}

class _ImpactPointPickerScreenState
    extends ConsumerState<ImpactPointPickerScreen> {
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey();

  double? _selectedX;
  double? _selectedY;
  late final Offset _fixedPoint;
  MapLayer? _layer;
  List<Map<String, dynamic>> _drawingStrokes = [];

  bool get _throwMode => !widget.wallbangLineMode && widget.pickThrowPoint;
  String get _targetName =>
      widget.wallbangLineMode ? '穿线方位' : (_throwMode ? '投掷点' : '爆点');

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    if (_throwMode) {
      _fixedPoint = Offset(widget.initialX!, widget.initialY!);
      // 投掷点与爆点重合视为未设置
      if (widget.throwX != widget.initialX ||
          widget.throwY != widget.initialY) {
        _selectedX = widget.throwX;
        _selectedY = widget.throwY;
      }
    } else {
      _fixedPoint = Offset(widget.throwX, widget.throwY);
      _selectedX = widget.initialX;
      _selectedY = widget.initialY;
    }
    _loadLayer();

    if (widget.readOnly && widget.existingStrokes != null) {
      try {
        final parsed = jsonDecode(widget.existingStrokes!) as List;
        _drawingStrokes =
            parsed.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  Future<void> _loadLayer() async {
    final isar = ref.read(isarProvider);
    _layer = await isar.mapLayers.get(widget.layerId);
    if (mounted) setState(() {});
  }

  Offset? _getLocalPosition(Offset globalPosition) {
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final localPosition = box.globalToLocal(globalPosition);
    final size = box.size;
    final bounds = computePickerImageBounds(size.width, size.height);
    final tapX = localPosition.dx - bounds.offsetX;
    final tapY = localPosition.dy - bounds.offsetY;
    return Offset(tapX / bounds.width, tapY / bounds.height);
  }

  void _handleTap(TapUpDetails details) {
    final localRatio = _getLocalPosition(details.globalPosition);
    if (localRatio == null) return;

    if (localRatio.dx < 0 ||
        localRatio.dx > 1 ||
        localRatio.dy < 0 ||
        localRatio.dy > 1) {
      return;
    }

    setState(() {
      _selectedX = localRatio.dx;
      _selectedY = localRatio.dy;
    });
  }

  void _confirmSelection() {
    if (_selectedX != null && _selectedY != null) {
      Navigator.pop(context, Offset(_selectedX!, _selectedY!));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.wallbangLineMode
              ? '请先点击地图设置穿线方位'
              : '请先点击地图选择$_targetName位置'),
        ),
      );
    }
  }

  void _handleMouseWheelZoom(PointerScrollEvent event) {
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

    final Offset viewportCenter = renderBox.size.center(Offset.zero);
    final Offset cursorPosition = event.localPosition - viewportCenter;
    final double scaleRatio = newScale / currentScale;
    final Offset newPosition =
        cursorPosition * (1 - scaleRatio) + currentPosition * scaleRatio;

    _photoViewController.scale = newScale;
    _photoViewController.position = newPosition;
  }

  Color _getTypeColor() {
    switch (widget.grenadeType) {
      case GrenadeType.molotov:
        return Colors.orange;
      case GrenadeType.smoke:
      default:
        return Colors.white;
    }
  }

  String _resolveAppBarTitle() {
    if (widget.wallbangLineMode) {
      return widget.readOnly ? '查看穿线方位' : '设置穿线方位';
    }
    return widget.readOnly ? '查看爆点位置' : '选择$_targetName位置';
  }

  @override
  Widget build(BuildContext context) {
    if (_layer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_resolveAppBarTitle()),
        centerTitle: true,
        actions: [
          if (!widget.readOnly)
            TextButton(
              onPressed: _confirmSelection,
              child: Text(
                '确认',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final imageBounds = computePickerImageBounds(
                      constraints.maxWidth, constraints.maxHeight);

                  return Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        _handleMouseWheelZoom(event);
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
                          final double scale = snapshot.data?.scale ?? 1.0;
                          final double markerScale = 1.0 / scale;

                          return Stack(
                            key: _stackKey,
                            children: [
                              GestureDetector(
                                onTapUp: widget.readOnly ? null : _handleTap,
                                child: _buildLayerImage(constraints),
                              ),
                              ..._buildPickerLayers(imageBounds, markerScale),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (!widget.readOnly)
            ImpactPickerFooter(
              wallbangLineMode: widget.wallbangLineMode,
              hasSelection: _selectedX != null,
              targetName: _targetName,
            ),
        ],
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

  List<Widget> _buildPickerLayers(
    PickerImageBounds imageBounds,
    double markerScale,
  ) {
    final selected = _selectedX != null && _selectedY != null
        ? Offset(_selectedX!, _selectedY!)
        : null;
    final throwPoint = _throwMode ? selected : _fixedPoint;
    final impactPoint = _throwMode ? _fixedPoint : selected;

    return [
      if (throwPoint != null)
        ImpactPointMarker.throwPoint(
          imageBounds: imageBounds,
          markerScale: markerScale,
          point: throwPoint,
        ),
      if (throwPoint != null && impactPoint != null)
        _buildConnectionLine(imageBounds, throwPoint, impactPoint),
      if (!widget.wallbangLineMode && impactPoint != null)
        ImpactPointMarker.impact(
          imageBounds: imageBounds,
          markerScale: markerScale,
          point: impactPoint,
        ),
      if (!widget.wallbangLineMode &&
          widget.readOnly &&
          _drawingStrokes.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: ImpactAreaPainter(
                strokes: _drawingStrokes,
                color: _getTypeColor(),
                imageBounds: imageBounds,
                opacity: 0.6,
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildConnectionLine(
    PickerImageBounds imageBounds,
    Offset from,
    Offset to,
  ) {
    final startX = imageBounds.offsetX + from.dx * imageBounds.width;
    final startY = imageBounds.offsetY + from.dy * imageBounds.height;
    final endX = imageBounds.offsetX + to.dx * imageBounds.width;
    final endY = imageBounds.offsetY + to.dy * imageBounds.height;
    final isWallbang = widget.wallbangLineMode;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: DashedLinePainter(
            start: Offset(startX, startY),
            end: Offset(endX, endY),
            color: isWallbang
                ? Colors.cyanAccent.withValues(alpha: 0.9)
                : Colors.purpleAccent.withValues(alpha: 0.7),
            strokeWidth: 2,
            dashLength: isWallbang ? 7 : 5,
            gapLength: isWallbang ? 4 : 5,
            showArrow: isWallbang,
            arrowLength: 9.0,
          ),
        ),
      ),
    );
  }
}
