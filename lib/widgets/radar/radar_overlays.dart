import 'package:flutter/material.dart';

/// 雷达缩略图中心十字准星绘制器。
class RadarCrosshairPainter extends CustomPainter {
  final bool isSnapped;

  const RadarCrosshairPainter({this.isSnapped = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isSnapped
          ? Colors.orange.withValues(alpha: 0.4)
          : Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const gap = 20.0;
    const length = 10.0;

    final segments = <(Offset, Offset)>[
      (Offset(centerX, centerY - gap - length), Offset(centerX, centerY - gap)),
      (Offset(centerX, centerY + gap), Offset(centerX, centerY + gap + length)),
      (Offset(centerX - gap - length, centerY), Offset(centerX - gap, centerY)),
      (Offset(centerX + gap, centerY), Offset(centerX + gap + length, centerY)),
    ];

    for (final (start, end) in segments) {
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarCrosshairPainter oldDelegate) =>
      oldDelegate.isSnapped != isSnapped;
}

/// 雷达吸附目标脉冲指示圆点。
class RadarPulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const RadarPulsingDot({
    super.key,
    required this.color,
    required this.size,
  });

  @override
  State<RadarPulsingDot> createState() => _RadarPulsingDotState();
}

class _RadarPulsingDotState extends State<RadarPulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final scale = _animation.value;
        return Container(
          width: widget.size * scale,
          height: widget.size * scale,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5),
                blurRadius: 8 * scale,
                spreadRadius: 2 * scale,
              ),
            ],
          ),
        );
      },
    );
  }
}
