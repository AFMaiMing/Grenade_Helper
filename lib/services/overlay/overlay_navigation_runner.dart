import 'dart:async';

import 'package:flutter/foundation.dart';

import 'overlay_navigation_geometry.dart';

class OverlayNavigationRunner {
  static const Duration _moveInterval = Duration(milliseconds: 16);
  static const Duration _heartbeatInterval = Duration(milliseconds: 50);
  static const int _heartbeatTimeoutMs = 80;

  final Set<NavigationDirection> _activeDirections = {};
  final Map<NavigationDirection, DateTime> _lastHeartbeat = {};
  Timer? _moveTimer;
  Timer? _heartbeatTimer;

  bool get isActive => _activeDirections.isNotEmpty;
  Set<NavigationDirection> get activeDirections => _activeDirections;

  void start(
    NavigationDirection direction, {
    required VoidCallback onMoveTick,
    required VoidCallback onAllStoppedByHeartbeat,
  }) {
    final now = DateTime.now();
    // 反向按键按下时立即取消原方向，避免轴向抵消滞留
    final opposite = OverlayNavigationGeometry.oppositeDirection(direction);
    if (_activeDirections.remove(opposite)) {
      _lastHeartbeat.remove(opposite);
    }

    _activeDirections.add(direction);
    for (final dir in _activeDirections) {
      _lastHeartbeat[dir] = now;
    }

    _startMoveTimer(onMoveTick);
    _startHeartbeatTimer(onAllStoppedByHeartbeat);
  }

  void stop(
    NavigationDirection direction, {
    required VoidCallback onAllStopped,
  }) {
    _activeDirections.remove(direction);
    if (_activeDirections.isEmpty) {
      _stopMoveTimer();
      onAllStopped();
    }
  }

  void stopAll({required VoidCallback onStopped}) {
    _activeDirections.clear();
    _stopMoveTimer();
    onStopped();
  }

  void _startMoveTimer(VoidCallback onMoveTick) {
    if (_moveTimer != null) return;
    _moveTimer = Timer.periodic(_moveInterval, (_) => onMoveTick());
    onMoveTick();
  }

  void _stopMoveTimer() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  void _startHeartbeatTimer(VoidCallback onAllStoppedByHeartbeat) {
    if (_heartbeatTimer != null) return;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final now = DateTime.now();
      final expired = <NavigationDirection>[];

      for (final dir in _activeDirections) {
        final last = _lastHeartbeat[dir];
        if (last != null &&
            now.difference(last).inMilliseconds > _heartbeatTimeoutMs) {
          expired.add(dir);
        }
      }

      if (expired.isNotEmpty) {
        for (final dir in expired) {
          _activeDirections.remove(dir);
          _lastHeartbeat.remove(dir);
        }
        if (_activeDirections.isEmpty) {
          _stopMoveTimer();
          onAllStoppedByHeartbeat();
        }
      }

      if (_activeDirections.isEmpty) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
      }
    });
  }

  void dispose() {
    _moveTimer?.cancel();
    _moveTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}
