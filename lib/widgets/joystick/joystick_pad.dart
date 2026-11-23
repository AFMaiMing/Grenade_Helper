import 'dart:async';

import 'package:flutter/material.dart';

/// 虚拟摇杆交互盘，支持按住持续输出归一化方向向量。
class JoystickPad extends StatefulWidget {
  final Function(Offset direction) onMove;
  final double baseRadius;
  final double knobRadius;

  const JoystickPad({
    super.key,
    required this.onMove,
    this.baseRadius = 60.0,
    this.knobRadius = 25.0,
  });

  @override
  State<JoystickPad> createState() => _JoystickPadState();
}

class _JoystickPadState extends State<JoystickPad> {
  static const List<
      ({
        double? top,
        double? bottom,
        double? left,
        double? right,
        IconData icon
      })> _directionIndicators = [
    (
      top: 8.0,
      bottom: null,
      left: null,
      right: null,
      icon: Icons.arrow_drop_up
    ),
    (
      top: null,
      bottom: 8.0,
      left: null,
      right: null,
      icon: Icons.arrow_drop_down
    ),
    (top: null, bottom: null, left: 8.0, right: null, icon: Icons.arrow_left),
    (top: null, bottom: null, left: null, right: 8.0, icon: Icons.arrow_right),
  ];

  Offset _knobPosition = Offset.zero;
  Timer? _moveTimer;

  double get _maxDistance => widget.baseRadius - widget.knobRadius;

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _startTimer() {
    _stopTimer();
    _moveTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_knobPosition == Offset.zero) return;
      final normalizedDirection = Offset(
        _knobPosition.dx / _maxDistance,
        _knobPosition.dy / _maxDistance,
      );
      // 忽略中心小幅度误触死区。
      if (normalizedDirection.distance > 0.1) {
        widget.onMove(normalizedDirection);
      }
    });
  }

  void _stopTimer() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  void _onPanStart(DragStartDetails details) {
    _startTimer();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final newPosition = _knobPosition + details.delta;
    final distance = newPosition.distance;

    setState(() {
      _knobPosition = distance <= _maxDistance
          ? newPosition
          : Offset.fromDirection(newPosition.direction, _maxDistance);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _stopTimer();
    setState(() => _knobPosition = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        width: widget.baseRadius * 2,
        height: widget.baseRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.3),
          border: Border.all(
            color: primary.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.1),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final indicator in _directionIndicators)
              Positioned(
                top: indicator.top,
                bottom: indicator.bottom,
                left: indicator.left,
                right: indicator.right,
                child: Icon(
                  indicator.icon,
                  color: Colors.grey[700],
                  size: 20,
                ),
              ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[600],
              ),
            ),
            Transform.translate(
              offset: _knobPosition,
              child: Container(
                width: widget.knobRadius * 2,
                height: widget.knobRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[700],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.control_camera,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
