import 'package:flutter/material.dart';

import '../../models.dart';
import '../../models/overlay_snapshot.dart';
import '../../services/grenade_cluster_service.dart';

/// 雷达小地图上除当前吸附点之外的聚类标记渲染。
List<Widget> buildRadarPointWidgets({
  required List<GrenadeCluster> clusters,
  required OverlayGrenadeItem? currentGrenade,
  required bool isSnapped,
  required double centerX,
  required double centerY,
  required double width,
  required double height,
  required double zoomLevel,
}) {
  final mapSize = width > height ? width : height;
  final visibleClusters = isSnapped && currentGrenade != null
      ? clusters.where((c) => !c.containsGrenade(currentGrenade.id))
      : clusters;

  final widgets = <Widget>[];
  for (final cluster in visibleClusters) {
    final anchor = cluster.anchor;
    final screenX = width / 2 + (anchor.xRatio - centerX) * mapSize * zoomLevel;
    final screenY =
        height / 2 + (anchor.yRatio - centerY) * mapSize * zoomLevel;

    // 跳过视口外过远的点位，减少无效绘制。
    if (screenX < -10 ||
        screenX > width + 10 ||
        screenY < -10 ||
        screenY > height + 10) {
      widgets.add(const SizedBox.shrink());
      continue;
    }

    final count = cluster.members.length;
    final types = cluster.members.map((g) => g.type).toSet();
    final color = types.length == 1
        ? _radarGrenadeColor(types.first)
        : Colors.white.withValues(alpha: 0.8);
    final size = count > 1 ? 14.0 : 8.0;

    widgets.add(
      Positioned(
        left: screenX - size / 2,
        top: screenY - size / 2,
        child: _RadarPointMarker(
          color: color,
          size: size,
          count: count,
        ),
      ),
    );
  }
  return widgets;
}

Color _radarGrenadeColor(int type) => switch (type) {
      GrenadeType.smoke => Colors.grey,
      GrenadeType.flash => Colors.yellow,
      GrenadeType.molotov => Colors.red,
      GrenadeType.he => Colors.green,
      GrenadeType.wallbang => Colors.cyan,
      _ => Colors.white,
    };

class _RadarPointMarker extends StatelessWidget {
  final Color color;
  final double size;
  final int count;

  const _RadarPointMarker({
    required this.color,
    required this.size,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final isCluster = count > 1;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.8),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: isCluster
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: isCluster
          ? Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }
}
