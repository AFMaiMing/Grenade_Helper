import 'dart:math' as math;

import '../../models/overlay_snapshot.dart';
import '../grenade_cluster_service.dart';

enum NavigationDirection { up, down, left, right }

class OverlayNavigationGeometry {
  OverlayNavigationGeometry._();

  static const double clusterThreshold = 0.03;

  static const List<double> speedLevels = [
    0.0025,
    0.003,
    0.004,
    0.0045,
    0.005,
  ];

  static const List<double> snapThresholdLevels = [
    0.02,
    0.022,
    0.024,
    0.027,
    0.03,
  ];

  static const double _diagonalFactor = 0.707;
  static const double _snappedSpeedFactor = 0.5;
  static const double _stepSpeedMultiplier = 8.0;
  static const double _stepEscapeMultiplier = 1.5;

  static double speedForLevel(int level) {
    return speedLevels[level.clamp(1, speedLevels.length) - 1];
  }

  static double snapThresholdForLevel(int level) {
    return snapThresholdLevels[level.clamp(1, snapThresholdLevels.length) - 1];
  }

  static NavigationDirection oppositeDirection(NavigationDirection direction) {
    switch (direction) {
      case NavigationDirection.up:
        return NavigationDirection.down;
      case NavigationDirection.down:
        return NavigationDirection.up;
      case NavigationDirection.left:
        return NavigationDirection.right;
      case NavigationDirection.right:
        return NavigationDirection.left;
    }
  }

  static ({double dx, double dy}) computeContinuousDelta(
    Set<NavigationDirection> activeDirections,
    double moveSpeed, {
    required bool isSnapped,
  }) {
    double dx = 0;
    double dy = 0;

    for (final dir in activeDirections) {
      switch (dir) {
        case NavigationDirection.up:
          dy -= moveSpeed;
        case NavigationDirection.down:
          dy += moveSpeed;
        case NavigationDirection.left:
          dx -= moveSpeed;
        case NavigationDirection.right:
          dx += moveSpeed;
      }
    }

    if (dx != 0 && dy != 0) {
      dx *= _diagonalFactor;
      dy *= _diagonalFactor;
    }

    if (isSnapped) {
      dx *= _snappedSpeedFactor;
      dy *= _snappedSpeedFactor;
    }

    return (dx: dx, dy: dy);
  }

  static ({double dx, double dy}) computeStepDelta(
    NavigationDirection direction,
    double moveSpeed,
    double snapThreshold, {
    required bool isSnapped,
  }) {
    var step = moveSpeed * _stepSpeedMultiplier;
    if (isSnapped) {
      step = math.max(step, snapThreshold * _stepEscapeMultiplier);
    }

    switch (direction) {
      case NavigationDirection.up:
        return (dx: 0, dy: -step);
      case NavigationDirection.down:
        return (dx: 0, dy: step);
      case NavigationDirection.left:
        return (dx: -step, dy: 0);
      case NavigationDirection.right:
        return (dx: step, dy: 0);
    }
  }

  static ({double x, double y}) applyDelta(
    double x,
    double y,
    double dx,
    double dy,
  ) {
    return (
      x: (x + dx).clamp(0.0, 1.0),
      y: (y + dy).clamp(0.0, 1.0),
    );
  }

  static double distanceSqToCluster(
    GrenadeCluster cluster,
    double crosshairX,
    double crosshairY,
  ) {
    final dx = cluster.anchor.xRatio - crosshairX;
    final dy = cluster.anchor.yRatio - crosshairY;
    return dx * dx + dy * dy;
  }

  static GrenadeCluster? findClusterByAnchorId(
    List<GrenadeCluster> clusters,
    int? anchorId,
  ) {
    if (anchorId == null) return null;
    for (final cluster in clusters) {
      if (cluster.anchor.id == anchorId) return cluster;
    }
    return null;
  }

  static GrenadeCluster? resolveCurrentCluster(
    List<GrenadeCluster> clusters,
    OverlayGrenadeItem? currentGrenade,
    int? lockedClusterAnchorId,
  ) {
    return GrenadeClusterService.findClusterForGrenade(
          clusters,
          currentGrenade,
        ) ??
        findClusterByAnchorId(clusters, lockedClusterAnchorId);
  }

  // 查找距离准星最近且未被当前逻辑抑制的聚类锚点
  static ({GrenadeCluster cluster, double distanceSq})?
      findNearestEligibleCluster(
    List<GrenadeCluster> clusters, {
    required double crosshairX,
    required double crosshairY,
    required bool ignoreCurrent,
    required int? currentClusterAnchorId,
    required int? suppressedAnchorId,
    required double suppressedReleaseRadiusSq,
  }) {
    ({GrenadeCluster cluster, double distanceSq})? nearest;

    for (final cluster in clusters) {
      if (ignoreCurrent &&
          suppressedAnchorId == null &&
          currentClusterAnchorId == cluster.anchor.id) {
        continue;
      }

      final distSq = distanceSqToCluster(cluster, crosshairX, crosshairY);
      if (suppressedAnchorId != null &&
          cluster.anchor.id == suppressedAnchorId &&
          distSq < suppressedReleaseRadiusSq) {
        continue;
      }

      if (nearest == null || distSq < nearest.distanceSq) {
        nearest = (cluster: cluster, distanceSq: distSq);
      }
    }

    return nearest;
  }
}
