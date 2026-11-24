import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/square_brush.dart';

/// 方形地图容器内的实际图像布局边界。
typedef PickerImageBounds = ({
  double width,
  double height,
  double offsetX,
  double offsetY,
});

/// 计算 1:1 地图图像在容器内居中缩放后的边界。
PickerImageBounds computePickerImageBounds(
  double containerWidth,
  double containerHeight,
) {
  const imageAspectRatio = 1.0;
  final containerAspectRatio = containerWidth / containerHeight;
  if (containerAspectRatio > imageAspectRatio) {
    final imageHeight = containerHeight;
    final imageWidth = containerHeight * imageAspectRatio;
    return (
      width: imageWidth,
      height: imageHeight,
      offsetX: (containerWidth - imageWidth) / 2,
      offsetY: 0.0,
    );
  }
  final imageWidth = containerWidth;
  final imageHeight = containerWidth / imageAspectRatio;
  return (
    width: imageWidth,
    height: imageHeight,
    offsetX: 0.0,
    offsetY: (containerHeight - imageHeight) / 2,
  );
}

/// 爆点只读范围覆盖绘制器。
class ImpactAreaPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  final Color color;
  final double opacity;
  final PickerImageBounds imageBounds;

  const ImpactAreaPainter({
    required this.strokes,
    required this.color,
    required this.imageBounds,
    required this.opacity,
  });

  List<Offset> _extractPoints(dynamic rawPoints) {
    if (rawPoints is! List) return const [];
    final points = <Offset>[];
    for (final p in rawPoints) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        points.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      } else if (p is Map && p['x'] is num && p['y'] is num) {
        points.add(
          Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
        );
      }
    }
    return points;
  }

  double _extractStrokeWidth(Map<String, dynamic> stroke) {
    final widthRatio =
        ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))?.toDouble();
    if (widthRatio != null) {
      final normalized = widthRatio > 1.0 ? widthRatio / 1000.0 : widthRatio;
      return (normalized * imageBounds.width).clamp(3.0, 120.0);
    }
    final strokeWidth = (stroke['strokeWidth'] as num?)?.toDouble();
    return strokeWidth ?? 15.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    for (final stroke in strokes) {
      final points = _extractPoints(stroke['points'] ?? stroke['p']);
      if (points.isEmpty) continue;
      final width = _extractStrokeWidth(stroke);
      final isEraser = stroke['isEraser'] == true || stroke['e'] == 1;
      final isShape = stroke['isShape'] == true || stroke['s'] == 1;
      if (!isShape && parseSquareBrush(stroke)) {
        final paint = Paint()
          ..color = isEraser ? Colors.transparent : color.withValues(alpha: 1.0)
          ..blendMode = isEraser ? BlendMode.clear : BlendMode.srcOver;
        paintSquareBrush(
          canvas,
          points.map(_toCanvasPoint).toList(),
          width,
          paint,
        );
        continue;
      }
      _drawStroke(canvas, points, width, isEraser, isShape);
    }
    canvas.restore();
  }

  void _drawStroke(
    Canvas canvas,
    List<Offset> points,
    double width,
    bool isEraser,
    bool isShape,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = isEraser ? Colors.transparent : color.withValues(alpha: 1.0)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = isShape ? PaintingStyle.fill : PaintingStyle.stroke;
    if (isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    final path = Path();
    final start = _toCanvasPoint(points[0]);
    path.moveTo(start.dx, start.dy);
    if (points.length == 1) {
      path.lineTo(start.dx, start.dy);
    }
    for (int i = 1; i < points.length; i++) {
      final p = _toCanvasPoint(points[i]);
      path.lineTo(p.dx, p.dy);
    }
    if (isShape) {
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  Offset _toCanvasPoint(Offset ratio) {
    return Offset(
      imageBounds.offsetX + ratio.dx * imageBounds.width,
      imageBounds.offsetY + ratio.dy * imageBounds.height,
    );
  }

  @override
  bool shouldRepaint(covariant ImpactAreaPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color ||
        oldDelegate.imageBounds != imageBounds;
  }
}

/// 投掷点与目标点之间的虚线（可选穿线箭头）绘制器。
class DashedLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final bool showArrow;
  final double arrowLength;

  const DashedLinePainter({
    required this.start,
    required this.end,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength = 4,
    this.gapLength = 4,
    this.showArrow = false,
    this.arrowLength = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalLength = (end - start).distance;
    if (totalLength < 1e-3) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final direction = (end - start) / totalLength;
    double currentLength = 0;
    bool draw = true;
    path.moveTo(start.dx, start.dy);

    while (currentLength < totalLength) {
      final segmentLength = draw ? dashLength : gapLength;
      final nextLength =
          (currentLength + segmentLength).clamp(0.0, totalLength);
      final nextPoint = start + direction * nextLength;
      if (draw) {
        path.lineTo(nextPoint.dx, nextPoint.dy);
      } else {
        path.moveTo(nextPoint.dx, nextPoint.dy);
      }
      currentLength = nextLength;
      draw = !draw;
    }

    canvas.drawPath(path, paint);

    if (showArrow && totalLength > 2.0) {
      final wingLength = math.min(arrowLength, totalLength * 0.45);
      const spreadAngle = 28 * math.pi / 180;
      final backAngle = math.atan2(-direction.dy, -direction.dx);
      final leftWing = Offset(
        end.dx + wingLength * math.cos(backAngle - spreadAngle),
        end.dy + wingLength * math.sin(backAngle - spreadAngle),
      );
      final rightWing = Offset(
        end.dx + wingLength * math.cos(backAngle + spreadAngle),
        end.dy + wingLength * math.sin(backAngle + spreadAngle),
      );
      final arrowPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final arrowPath = Path()
        ..moveTo(leftWing.dx, leftWing.dy)
        ..lineTo(end.dx, end.dy)
        ..lineTo(rightWing.dx, rightWing.dy);
      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DashedLinePainter oldDelegate) {
    return start != oldDelegate.start ||
        end != oldDelegate.end ||
        color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        dashLength != oldDelegate.dashLength ||
        gapLength != oldDelegate.gapLength ||
        showArrow != oldDelegate.showArrow ||
        arrowLength != oldDelegate.arrowLength;
  }
}
