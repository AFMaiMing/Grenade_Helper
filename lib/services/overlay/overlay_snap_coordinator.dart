import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/overlay_snapshot.dart';
import '../grenade_cluster_service.dart';
import 'overlay_navigation_geometry.dart';

enum _SnapState { free, candidate, locked }

// 管理准星坐标、聚类吸附状态机、延迟确认及脱离抑制逻辑
class OverlaySnapCoordinator {
  static const double _snapReleaseMultiplier = 1.18;
  static const double _snapAcquireRadiusMultiplier = 0.92;
  static const double _snapLockedReleaseMultiplier = 1.55;
  static const Duration _snapCandidateDuration = Duration(milliseconds: 72);
  static const Duration _snapConfirmDuration = Duration(milliseconds: 100);
  static const Duration _suppressedResetDuration = Duration(milliseconds: 500);

  double _crosshairX = 0.5;
  double _crosshairY = 0.5;
  bool _isSnapped = false;
  bool _isSnapConfirmed = false;

  Timer? _snapConfirmTimer;
  int? _suppressedSnapGrenadeId;
  Timer? _suppressedSnapTimer;
  DateTime? _lastNavigationActivityAt;
  _SnapState _snapState = _SnapState.free;
  int? _candidateClusterAnchorId;
  DateTime? _candidateSince;
  int? _lockedClusterAnchorId;

  double get crosshairX => _crosshairX;
  double get crosshairY => _crosshairY;
  bool get isSnapped => _isSnapped;
  bool get isSnapConfirmed => _isSnapConfirmed;

  void initForGrenade(
    List<GrenadeCluster> clusters,
    OverlayGrenadeItem? grenade,
  ) {
    reset();
    if (grenade == null) {
      _crosshairX = 0.5;
      _crosshairY = 0.5;
      return;
    }

    final cluster =
        GrenadeClusterService.findClusterForGrenade(clusters, grenade);
    _crosshairX = cluster?.anchor.xRatio ?? grenade.xRatio;
    _crosshairY = cluster?.anchor.yRatio ?? grenade.yRatio;
    _lockedClusterAnchorId = cluster?.anchor.id ?? grenade.id;
    _snapState = _SnapState.locked;
    _isSnapped = true;
    _isSnapConfirmed = true;
  }

  void clearAllForMapClear() {
    reset();
    _lastNavigationActivityAt = null;
  }

  void moveBy(double dx, double dy) {
    final next = OverlayNavigationGeometry.applyDelta(
      _crosshairX,
      _crosshairY,
      dx,
      dy,
    );
    _crosshairX = next.x;
    _crosshairY = next.y;
  }

  void recordNavigationActivity({
    required bool Function() hasActiveNavigation,
    required VoidCallback onResnapReady,
  }) {
    _lastNavigationActivityAt = DateTime.now();
    if (_suppressedSnapGrenadeId != null) {
      _scheduleSuppressedSnapReset(
        hasActiveNavigation: hasActiveNavigation,
        onResnapReady: onResnapReady,
      );
    }
  }

  void releaseSnapForMove({
    required List<GrenadeCluster> clusters,
    required OverlayGrenadeItem? currentGrenade,
    required bool Function() hasActiveNavigation,
    required VoidCallback onResnapReady,
  }) {
    if (!_isSnapped) return;
    _isSnapped = false;
    final cluster = OverlayNavigationGeometry.resolveCurrentCluster(
      clusters,
      currentGrenade,
      _lockedClusterAnchorId,
    );
    if (cluster == null) return;

    _suppressedSnapGrenadeId = cluster.anchor.id;
    _lockedClusterAnchorId = null;
    if (_snapState == _SnapState.locked) {
      _setUnsnappedState(_SnapState.free);
    }
    _scheduleSuppressedSnapReset(
      hasActiveNavigation: hasActiveNavigation,
      onResnapReady: onResnapReady,
    );
  }

  void syncWithClusters(
    List<GrenadeCluster> clusters,
    OverlayGrenadeItem? currentGrenade,
  ) {
    final currentCluster = OverlayNavigationGeometry.resolveCurrentCluster(
      clusters,
      currentGrenade,
      _lockedClusterAnchorId,
    );
    if (_suppressedSnapGrenadeId != null &&
        OverlayNavigationGeometry.findClusterByAnchorId(
              clusters,
              _suppressedSnapGrenadeId,
            ) ==
            null) {
      _clearSuppressedTimer();
    }
    if (_candidateClusterAnchorId != null &&
        OverlayNavigationGeometry.findClusterByAnchorId(
              clusters,
              _candidateClusterAnchorId,
            ) ==
            null) {
      _candidateClusterAnchorId = null;
      _candidateSince = null;
      if (_snapState == _SnapState.candidate) {
        _setUnsnappedState(_SnapState.free);
      }
    }
    if (_lockedClusterAnchorId != null &&
        OverlayNavigationGeometry.findClusterByAnchorId(
              clusters,
              _lockedClusterAnchorId,
            ) ==
            null) {
      _lockedClusterAnchorId = null;
      if (_snapState == _SnapState.locked) {
        _setUnsnappedState(_SnapState.free);
      }
    }
    if (_isSnapped && currentCluster != null) {
      _lockedClusterAnchorId = currentCluster.anchor.id;
      _snapState = _SnapState.locked;
    }
  }

  void evaluateSnap({
    required List<GrenadeCluster> clusters,
    required OverlayGrenadeItem? currentGrenade,
    required double snapThreshold,
    required bool isMoving,
    required bool ignoreCurrent,
    required void Function(OverlayGrenadeItem targetGrenade) onSelectGrenade,
    required VoidCallback onSnapConfirmed,
  }) {
    if (clusters.isEmpty) {
      reset();
      return;
    }

    syncWithClusters(clusters, currentGrenade);
    _updateSuppressedClusterState(clusters, snapThreshold);

    final lockedReleaseRadiusSq =
        _squared(snapThreshold * _snapLockedReleaseMultiplier);
    final lockedCluster = OverlayNavigationGeometry.findClusterByAnchorId(
      clusters,
      _lockedClusterAnchorId,
    );
    if (lockedCluster != null &&
        !_isClusterSuppressed(lockedCluster, snapThreshold) &&
        OverlayNavigationGeometry.distanceSqToCluster(
              lockedCluster,
              _crosshairX,
              _crosshairY,
            ) <=
            lockedReleaseRadiusSq) {
      _applyLockedCluster(
        lockedCluster,
        currentGrenade: currentGrenade,
        preserveCurrentSelection: true,
        onSelectGrenade: onSelectGrenade,
        onSnapConfirmed: onSnapConfirmed,
      );
      return;
    }

    if (lockedCluster == null ||
        OverlayNavigationGeometry.distanceSqToCluster(
              lockedCluster,
              _crosshairX,
              _crosshairY,
            ) >
            lockedReleaseRadiusSq) {
      _lockedClusterAnchorId = null;
      if (_snapState == _SnapState.locked) {
        _setUnsnappedState(_SnapState.free);
      }
    }

    final currentClusterAnchorId =
        OverlayNavigationGeometry.resolveCurrentCluster(
      clusters,
      currentGrenade,
      _lockedClusterAnchorId,
    )?.anchor.id;
    final releaseRadiusSq = _squared(snapThreshold * _snapReleaseMultiplier);
    final nearestResult = OverlayNavigationGeometry.findNearestEligibleCluster(
      clusters,
      crosshairX: _crosshairX,
      crosshairY: _crosshairY,
      ignoreCurrent: ignoreCurrent,
      currentClusterAnchorId: currentClusterAnchorId,
      suppressedAnchorId: _suppressedSnapGrenadeId,
      suppressedReleaseRadiusSq: releaseRadiusSq,
    );

    if (nearestResult == null ||
        nearestResult.distanceSq >
            _squared(snapThreshold * _snapAcquireRadiusMultiplier)) {
      _setUnsnappedState(_SnapState.free);
      return;
    }

    final nearestCluster = nearestResult.cluster;
    if (!isMoving) {
      _applyLockedCluster(
        nearestCluster,
        currentGrenade: currentGrenade,
        onSelectGrenade: onSelectGrenade,
        onSnapConfirmed: onSnapConfirmed,
      );
      return;
    }

    // 连续移动时先进入短暂候选态，防止高速路过点位误触发吸附
    final now = DateTime.now();
    final anchorId = nearestCluster.anchor.id;
    if (_candidateClusterAnchorId != anchorId) {
      _candidateClusterAnchorId = anchorId;
      _candidateSince = now;
      _setUnsnappedState(_SnapState.candidate);
      return;
    }

    final candidateSince = _candidateSince ?? now;
    if (now.difference(candidateSince) < _snapCandidateDuration) {
      _setUnsnappedState(_SnapState.candidate);
      return;
    }

    _applyLockedCluster(
      nearestCluster,
      currentGrenade: currentGrenade,
      onSelectGrenade: onSelectGrenade,
      onSnapConfirmed: onSnapConfirmed,
    );
  }

  void _applyLockedCluster(
    GrenadeCluster cluster, {
    required OverlayGrenadeItem? currentGrenade,
    bool preserveCurrentSelection = false,
    required void Function(OverlayGrenadeItem targetGrenade) onSelectGrenade,
    required VoidCallback onSnapConfirmed,
  }) {
    final wasSnapped = _isSnapped;
    final previousGrenadeId = currentGrenade?.id;

    _crosshairX = cluster.anchor.xRatio;
    _crosshairY = cluster.anchor.yRatio;
    _lockedClusterAnchorId = cluster.anchor.id;
    _candidateClusterAnchorId = null;
    _candidateSince = null;
    _snapState = _SnapState.locked;

    final targetGrenade = preserveCurrentSelection &&
            currentGrenade != null &&
            cluster.containsGrenade(currentGrenade.id)
        ? currentGrenade
        : cluster.anchor;
    onSelectGrenade(targetGrenade);

    _isSnapped = true;
    _clearSuppressedTimer();

    if (!wasSnapped || previousGrenadeId != targetGrenade.id) {
      _isSnapConfirmed = false;
      _snapConfirmTimer?.cancel();
      _snapConfirmTimer = Timer(_snapConfirmDuration, () {
        if (_isSnapped && _lockedClusterAnchorId == cluster.anchor.id) {
          _isSnapConfirmed = true;
          onSnapConfirmed();
        }
      });
    }
  }

  void _scheduleSuppressedSnapReset({
    required bool Function() hasActiveNavigation,
    required VoidCallback onResnapReady,
  }) {
    _suppressedSnapTimer?.cancel();
    _suppressedSnapTimer = Timer(_suppressedResetDuration, () {
      final lastActivityAt = _lastNavigationActivityAt;
      if (lastActivityAt == null) {
        _clearSuppressedAndTrigger(onResnapReady);
        return;
      }

      final idleFor = DateTime.now().difference(lastActivityAt);
      if (idleFor < _suppressedResetDuration || hasActiveNavigation()) {
        _scheduleSuppressedSnapReset(
          hasActiveNavigation: hasActiveNavigation,
          onResnapReady: onResnapReady,
        );
        return;
      }

      _clearSuppressedAndTrigger(onResnapReady);
    });
  }

  void _clearSuppressedAndTrigger(VoidCallback onResnapReady) {
    if (_suppressedSnapGrenadeId == null) return;
    _clearSuppressedTimer();
    onResnapReady();
  }

  bool _isClusterSuppressed(GrenadeCluster cluster, double snapThreshold) {
    if (_suppressedSnapGrenadeId == null) return false;
    final distSq = OverlayNavigationGeometry.distanceSqToCluster(
      cluster,
      _crosshairX,
      _crosshairY,
    );
    final releaseRadiusSq = _squared(snapThreshold * _snapReleaseMultiplier);
    return cluster.anchor.id == _suppressedSnapGrenadeId &&
        distSq < releaseRadiusSq;
  }

  void _updateSuppressedClusterState(
    List<GrenadeCluster> clusters,
    double snapThreshold,
  ) {
    if (_suppressedSnapGrenadeId == null) return;
    final suppressedCluster = OverlayNavigationGeometry.findClusterByAnchorId(
      clusters,
      _suppressedSnapGrenadeId,
    );
    if (suppressedCluster == null) {
      _clearSuppressedTimer();
      return;
    }

    final releaseRadiusSq = _squared(snapThreshold * _snapReleaseMultiplier);
    if (OverlayNavigationGeometry.distanceSqToCluster(
          suppressedCluster,
          _crosshairX,
          _crosshairY,
        ) >
        releaseRadiusSq) {
      _clearSuppressedTimer();
    }
  }

  void _setUnsnappedState(_SnapState state) {
    _snapState = state;
    if (state != _SnapState.candidate) {
      _candidateClusterAnchorId = null;
      _candidateSince = null;
    }
    _isSnapped = false;
    _isSnapConfirmed = false;
    _snapConfirmTimer?.cancel();
  }

  void reset() {
    _snapState = _SnapState.free;
    _candidateClusterAnchorId = null;
    _candidateSince = null;
    _lockedClusterAnchorId = null;
    _clearSuppressedTimer();
    _isSnapped = false;
    _isSnapConfirmed = false;
    _snapConfirmTimer?.cancel();
  }

  void _clearSuppressedTimer() {
    _suppressedSnapGrenadeId = null;
    _suppressedSnapTimer?.cancel();
  }

  static double _squared(double value) => value * value;

  void dispose() {
    _snapConfirmTimer?.cancel();
    _snapConfirmTimer = null;
    _suppressedSnapTimer?.cancel();
    _suppressedSnapTimer = null;
  }
}
