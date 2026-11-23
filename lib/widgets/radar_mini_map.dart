import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/overlay_snapshot.dart';
import '../services/grenade_cluster_service.dart';
import 'path_image_provider.dart';
import 'radar/radar_overlays.dart';
import 'radar/radar_point_layer.dart';

/// 雷达小地图。
class RadarMiniMap extends StatefulWidget {
  final String mapAssetPath;
  final OverlayGrenadeItem? currentGrenade;
  final List<OverlayGrenadeItem> allGrenades;
  final double width;
  final double height;
  final double zoomLevel;
  final double crosshairX;
  final double crosshairY;
  final bool isSnapped;

  const RadarMiniMap({
    super.key,
    required this.mapAssetPath,
    required this.currentGrenade,
    required this.allGrenades,
    required this.crosshairX,
    required this.crosshairY,
    required this.isSnapped,
    this.width = 400,
    this.height = 150,
    this.zoomLevel = 1.3,
  });

  @override
  State<RadarMiniMap> createState() => _RadarMiniMapState();
}

class _RadarMiniMapState extends State<RadarMiniMap>
    with SingleTickerProviderStateMixin {
  static const double _smoothFactor = 0.35;

  late final Ticker _ticker;
  late List<GrenadeCluster> _cachedClusters;
  ImageProvider? _cachedMapImageProvider;

  double _animatedX = 0.5;
  double _animatedY = 0.5;

  @override
  void initState() {
    super.initState();
    _animatedX = widget.crosshairX;
    _animatedY = widget.crosshairY;
    _cachedClusters = GrenadeClusterService.buildClusters(widget.allGrenades);
    _cachedMapImageProvider = imageProviderFromPath(widget.mapAssetPath);
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant RadarMiniMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.allGrenades, widget.allGrenades)) {
      _cachedClusters = GrenadeClusterService.buildClusters(widget.allGrenades);
    }
    if (oldWidget.mapAssetPath != widget.mapAssetPath) {
      _cachedMapImageProvider = imageProviderFromPath(widget.mapAssetPath);
    }
    if ((widget.crosshairX - _animatedX).abs() >= 0.001 ||
        (widget.crosshairY - _animatedY).abs() >= 0.001) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  void _onTick(Duration elapsed) {
    final dx = widget.crosshairX - _animatedX;
    final dy = widget.crosshairY - _animatedY;

    if (dx.abs() < 0.001 && dy.abs() < 0.001) {
      _ticker.stop();
      if (_animatedX != widget.crosshairX || _animatedY != widget.crosshairY) {
        setState(() {
          _animatedX = widget.crosshairX;
          _animatedY = widget.crosshairY;
        });
      }
      return;
    }

    setState(() {
      _animatedX += dx * _smoothFactor;
      _animatedY += dy * _smoothFactor;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dx = (widget.crosshairX - _animatedX).abs();
    final dy = (widget.crosshairY - _animatedY).abs();
    final showPulsingDot = widget.isSnapped && dx < 0.005 && dy < 0.005;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            _buildZoomedMap(_animatedX, _animatedY),
            ...buildRadarPointWidgets(
              clusters: _cachedClusters,
              currentGrenade: widget.currentGrenade,
              isSnapped: widget.isSnapped,
              centerX: _animatedX,
              centerY: _animatedY,
              width: widget.width,
              height: widget.height,
              zoomLevel: widget.zoomLevel,
            ),
            if (showPulsingDot)
              const Center(
                child: RadarPulsingDot(color: Colors.orange, size: 14),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.isSnapped
                      ? Colors.orange.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            CustomPaint(
              size: Size(widget.width, widget.height),
              painter: RadarCrosshairPainter(isSnapped: widget.isSnapped),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomedMap(double centerX, double centerY) {
    final mapSize = widget.width > widget.height ? widget.width : widget.height;
    final zoomedSize = mapSize * widget.zoomLevel;
    final offsetX = (0.5 - centerX) * zoomedSize;
    final offsetY = (0.5 - centerY) * zoomedSize;
    final mapImageProvider = _cachedMapImageProvider;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: zoomedSize,
          maxHeight: zoomedSize,
          child: Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: mapImageProvider == null
                ? Container(color: Colors.grey[900])
                : Image(
                    image: mapImageProvider,
                    fit: BoxFit.cover,
                    width: zoomedSize,
                    height: zoomedSize,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey[900]),
                  ),
          ),
        ),
      ),
    );
  }
}
