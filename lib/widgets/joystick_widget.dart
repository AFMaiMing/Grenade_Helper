import 'package:flutter/material.dart';

import 'joystick/joystick_pad.dart';

/// 摇杆底部操作面板。
class JoystickBottomSheet extends StatelessWidget {
  final double opacity;
  final int speedLevel;
  final Function(Offset direction) onMove;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final String? clusterName;

  const JoystickBottomSheet({
    super.key,
    required this.opacity,
    required this.speedLevel,
    required this.onMove,
    required this.onConfirm,
    required this.onCancel,
    this.clusterName,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2126).withValues(alpha: opacity),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gamepad, color: primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        clusterName != null ? '移动: $clusterName' : '摇杆移动',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '速度: $speedLevel档',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  JoystickPad(onMove: onMove),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '按住拖动持续移动',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.withValues(alpha: opacity),
                        side: BorderSide(
                          color: Colors.grey[600]!.withValues(alpha: opacity),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: opacity),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary.withValues(alpha: opacity),
                        foregroundColor:
                            Colors.white.withValues(alpha: opacity),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        '确认',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: opacity),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹出摇杆底部操作面板。
Future<void> showJoystickBottomSheet({
  required BuildContext context,
  required double opacity,
  required int speedLevel,
  required Function(Offset direction) onMove,
  required VoidCallback onConfirm,
  required VoidCallback onCancel,
  String? clusterName,
  Color barrierColor = Colors.black54,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => JoystickBottomSheet(
      opacity: opacity,
      speedLevel: speedLevel,
      onMove: onMove,
      onConfirm: () {
        Navigator.pop(ctx);
        onConfirm();
      },
      onCancel: () {
        Navigator.pop(ctx);
        onCancel();
      },
      clusterName: clusterName,
    ),
  );
}
