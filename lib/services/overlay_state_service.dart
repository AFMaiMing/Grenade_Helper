import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../models/overlay_snapshot.dart';
import 'grenade_cluster_service.dart';
import 'overlay/overlay_navigation_geometry.dart';
import 'overlay/overlay_navigation_runner.dart';
import 'overlay/overlay_snap_coordinator.dart';
import 'settings_service.dart';

export 'overlay/overlay_navigation_geometry.dart' show NavigationDirection;

// 管理悬浮窗地图快照、类型筛选、道具步骤切换与方向导航状态
class OverlayStateService extends ChangeNotifier {
  OverlayMapSnapshot? _snapshot;
  List<OverlayGrenadeItem> _allGrenades = const [];
  List<OverlayGrenadeItem> _filteredGrenades = const [];
  List<GrenadeCluster> _clusters = const [];

  int _currentGrenadeIndex = 0;
  int _currentStepIndex = 0;

  final Set<int> _activeFilters = {
    GrenadeType.smoke,
    GrenadeType.flash,
    GrenadeType.molotov,
    GrenadeType.he,
    GrenadeType.wallbang,
  };

  final OverlaySnapCoordinator _snapCoordinator = OverlaySnapCoordinator();
  final OverlayNavigationRunner _navigationRunner = OverlayNavigationRunner();
  final Map<int, int> _lastViewedGrenadeByMap = {};

  int _navSpeedLevel = 3;
  bool _navigationLocked = false;
  double _overlayOpacity = 0.9;
  int _overlaySizeIndex = 1;
  VoidCallback? _videoTogglePlayPauseCallback;

  int get navSpeedLevel => _navSpeedLevel;
  bool get navigationLocked => _navigationLocked;
  double get overlayOpacity => _overlayOpacity;
  int get overlaySizeIndex => _overlaySizeIndex;

  String? get mapName => _snapshot?.mapName;
  String? get layerAssetPath => _snapshot?.layerAssetPath;
  List<OverlayGrenadeItem> get filteredGrenades => _filteredGrenades;
  List<OverlayGrenadeItem> get allGrenades => _allGrenades;
  int get currentGrenadeIndex => _currentGrenadeIndex;
  int get currentStepIndex => _currentStepIndex;
  Set<int> get activeFilters => _activeFilters;

  double get crosshairX => _snapCoordinator.crosshairX;
  double get crosshairY => _snapCoordinator.crosshairY;
  bool get isSnapped => _snapCoordinator.isSnapped;
  bool get isSnapConfirmed => _snapCoordinator.isSnapConfirmed;

  bool get hasMap => _snapshot != null;

  OverlayGrenadeItem? get currentGrenade {
    if (_filteredGrenades.isEmpty ||
        _currentGrenadeIndex < 0 ||
        _currentGrenadeIndex >= _filteredGrenades.length) {
      return null;
    }
    return _filteredGrenades[_currentGrenadeIndex];
  }

  List<OverlayGrenadeItem> get currentClusterGrenades {
    final cluster = GrenadeClusterService.findClusterForGrenade(
      _clusters,
      currentGrenade,
    );
    return cluster?.members ?? const [];
  }

  int get currentClusterIndex {
    final cluster = currentClusterGrenades;
    if (cluster.isEmpty || currentGrenade == null) return 0;
    return cluster.indexWhere((g) => g.id == currentGrenade!.id);
  }

  double get _moveSpeed =>
      OverlayNavigationGeometry.speedForLevel(_navSpeedLevel);
  double get _snapThreshold =>
      OverlayNavigationGeometry.snapThresholdForLevel(_navSpeedLevel);

  void setNavigationLocked(bool locked) {
    if (_navigationLocked == locked) return;
    _navigationLocked = locked;
    if (locked) {
      stopAllNavigation();
    } else {
      notifyListeners();
    }
  }

  void setNavSpeedLevel(int level) {
    final next = level.clamp(1, 5);
    if (_navSpeedLevel == next) return;
    _navSpeedLevel = next;
    notifyListeners();
  }

  void increaseNavSpeed() {
    if (_navSpeedLevel < 5) {
      setNavSpeedLevel(_navSpeedLevel + 1);
    }
  }

  void decreaseNavSpeed() {
    if (_navSpeedLevel > 1) {
      setNavSpeedLevel(_navSpeedLevel - 1);
    }
  }

  void setVideoTogglePlayPauseCallback(VoidCallback? callback) {
    _videoTogglePlayPauseCallback = callback;
  }

  void triggerVideoTogglePlayPause() {
    _videoTogglePlayPauseCallback?.call();
  }

  void refresh() {
    notifyListeners();
  }

  void setOpacity(double value) {
    _overlayOpacity = value;
    notifyListeners();
  }

  Future<void> setOverlaySize(int index) async {
    _overlaySizeIndex = index;
    final s = SettingsService.calculateSizePixels(index);
    try {
      await windowManager.setSize(Size(s.$1, s.$2));
    } catch (e) {
      debugPrint('[OverlayStateService] Error resizing window: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _navigationRunner.dispose();
    _snapCoordinator.dispose();
    super.dispose();
  }

  void applyMapSnapshot(OverlayMapSnapshot snapshot) {
    final sameLayer = _snapshot != null &&
        _snapshot!.mapId == snapshot.mapId &&
        _snapshot!.layerId == snapshot.layerId;

    if (sameLayer) {
      final wasEmpty = _filteredGrenades.isEmpty;
      _snapshot = snapshot;
      _allGrenades = snapshot.grenades;
      _applyFilters(preserveStep: true);
      if (wasEmpty && _filteredGrenades.isNotEmpty) {
        _snapCoordinator.initForGrenade(_clusters, currentGrenade);
      }
      notifyListeners();
      return;
    }

    _rememberCurrentGrenadeForMap();
    _snapshot = snapshot;
    _allGrenades = snapshot.grenades;
    _applyFilters();

    final lastGrenadeId = _lastViewedGrenadeByMap[snapshot.mapId];
    if (lastGrenadeId != null) {
      final idx = _filteredGrenades.indexWhere((g) => g.id == lastGrenadeId);
      _currentGrenadeIndex = idx >= 0 ? idx : 0;
    } else {
      _currentGrenadeIndex = 0;
    }
    _currentStepIndex = 0;
    _snapCoordinator.initForGrenade(_clusters, currentGrenade);
    notifyListeners();
  }

  void clearMap() {
    _rememberCurrentGrenadeForMap();
    _snapshot = null;
    _allGrenades = const [];
    _filteredGrenades = const [];
    _clusters = const [];
    _currentGrenadeIndex = 0;
    _currentStepIndex = 0;
    _snapCoordinator.clearAllForMapClear();
    notifyListeners();
  }

  void toggleFilter(int type) {
    if (_activeFilters.contains(type)) {
      if (_activeFilters.length > 1) {
        _activeFilters.remove(type);
      }
    } else {
      _activeFilters.add(type);
    }
    _applyFilters();
    notifyListeners();
  }

  void prevGrenade() => _shiftClusterGrenade(-1);

  void nextGrenade() => _shiftClusterGrenade(1);

  void prevStep() => _shiftStepIndex(-1);

  void nextStep() => _shiftStepIndex(1);

  void startNavigation(NavigationDirection direction) {
    if (_navigationLocked) return;
    _navigationRunner.start(
      direction,
      onMoveTick: _updateCrosshairPosition,
      onAllStoppedByHeartbeat: _finishNavigationAndNotify,
    );
  }

  void stopNavigation(NavigationDirection direction) {
    _navigationRunner.stop(
      direction,
      onAllStopped: _finishNavigationAndNotify,
    );
  }

  void stopAllNavigation() {
    _navigationRunner.stopAll(onStopped: _finishNavigationAndNotify);
  }

  void navigateDirection(NavigationDirection direction) {
    if (_navigationLocked) return;
    _recordNavigationActivity();

    final wasSnapped = _snapCoordinator.isSnapped;
    final delta = OverlayNavigationGeometry.computeStepDelta(
      direction,
      _moveSpeed,
      _snapThreshold,
      isSnapped: wasSnapped,
    );
    _releaseSnapForMoveIfNeeded();
    _snapCoordinator.moveBy(delta.dx, delta.dy);

    _evaluateSnap(ignoreCurrent: false);
    notifyListeners();
  }

  void setGrenadeIndex(int index) {
    if (index >= 0 && index < _filteredGrenades.length) {
      _currentGrenadeIndex = index;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  void _rememberCurrentGrenadeForMap() {
    if (_snapshot != null && currentGrenade != null) {
      _lastViewedGrenadeByMap[_snapshot!.mapId] = currentGrenade!.id;
    }
  }

  void _applyFilters({bool preserveStep = false}) {
    final currentGrenadeId = currentGrenade?.id;
    final previousStepIndex = _currentStepIndex;

    _filteredGrenades = GrenadeClusterService.sortGrenades(
      _allGrenades.where((g) => _activeFilters.contains(g.type)),
    );
    _clusters = GrenadeClusterService.buildClusters(
      _filteredGrenades,
      threshold: OverlayNavigationGeometry.clusterThreshold,
    );
    _snapCoordinator.syncWithClusters(_clusters, currentGrenade);

    if (_filteredGrenades.isEmpty) {
      _currentGrenadeIndex = 0;
      _currentStepIndex = 0;
      return;
    }

    if (currentGrenadeId != null) {
      final idx = _filteredGrenades.indexWhere((g) => g.id == currentGrenadeId);
      _currentGrenadeIndex = idx >= 0 ? idx : 0;
      if (preserveStep && idx >= 0) {
        final stepCount = _filteredGrenades[idx].steps.length;
        _currentStepIndex =
            stepCount > 0 ? previousStepIndex.clamp(0, stepCount - 1) : 0;
        return;
      }
    } else {
      _currentGrenadeIndex = 0;
    }

    _currentStepIndex = 0;
  }

  void _shiftClusterGrenade(int delta) {
    final cluster = currentClusterGrenades;
    if (cluster.length <= 1) return;

    final targetClusterIdx = currentClusterIndex + delta;
    if (targetClusterIdx < 0 || targetClusterIdx >= cluster.length) return;

    final targetGrenade = cluster[targetClusterIdx];
    final globalIdx =
        _filteredGrenades.indexWhere((g) => g.id == targetGrenade.id);
    if (globalIdx >= 0 && globalIdx != _currentGrenadeIndex) {
      _currentGrenadeIndex = globalIdx;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  void _shiftStepIndex(int delta) {
    final grenade = currentGrenade;
    if (grenade == null || grenade.steps.isEmpty) return;
    final count = grenade.steps.length;
    _currentStepIndex = (_currentStepIndex + delta + count) % count;
    notifyListeners();
  }

  void _updateCrosshairPosition() {
    if (!_navigationRunner.isActive) return;
    _recordNavigationActivity();

    final delta = OverlayNavigationGeometry.computeContinuousDelta(
      _navigationRunner.activeDirections,
      _moveSpeed,
      isSnapped: _snapCoordinator.isSnapped,
    );
    _releaseSnapForMoveIfNeeded();
    _snapCoordinator.moveBy(delta.dx, delta.dy);

    _evaluateSnap(ignoreCurrent: false);
    notifyListeners();
  }

  void _finishNavigationAndNotify() {
    _evaluateSnap(ignoreCurrent: false);
    notifyListeners();
  }

  void _recordNavigationActivity() {
    _snapCoordinator.recordNavigationActivity(
      hasActiveNavigation: () => _navigationRunner.isActive,
      onResnapReady: _finishNavigationAndNotify,
    );
  }

  void _releaseSnapForMoveIfNeeded() {
    _snapCoordinator.releaseSnapForMove(
      clusters: _clusters,
      currentGrenade: currentGrenade,
      hasActiveNavigation: () => _navigationRunner.isActive,
      onResnapReady: _finishNavigationAndNotify,
    );
  }

  void _evaluateSnap({required bool ignoreCurrent}) {
    if (_filteredGrenades.isEmpty || _clusters.isEmpty) {
      _snapCoordinator.reset();
      return;
    }
    _snapCoordinator.evaluateSnap(
      clusters: _clusters,
      currentGrenade: currentGrenade,
      snapThreshold: _snapThreshold,
      isMoving: _navigationRunner.isActive,
      ignoreCurrent: ignoreCurrent,
      onSelectGrenade: (targetGrenade) {
        final globalIdx = _filteredGrenades
            .indexWhere((grenade) => grenade.id == targetGrenade.id);
        if (globalIdx >= 0) {
          _currentGrenadeIndex = globalIdx;
        }
        _currentStepIndex = 0;
      },
      onSnapConfirmed: notifyListeners,
    );
  }
}
