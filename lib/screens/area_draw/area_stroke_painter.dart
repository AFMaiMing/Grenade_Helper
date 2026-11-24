import 'package:flutter/material.dart';

import '../../widgets/square_brush.dart';
import 'area_draw_models.dart';

/// 区域笔画与钢笔多边形画布绘制器
class AreaStrokePainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<Offset> currentStroke;
  final double currentStrokeWidthRatio;
  final bool currentIsEraser;
  final bool currentIsSquare;
  final List<Offset> penPoints;
  final Color color;
  final double opacity;
  final DrawImageBounds imageBounds;
  final double markerScale;

  AreaStrokePainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentStrokeWidthRatio,
    required this.currentIsEraser,
    required this.currentIsSquare,
    required this.penPoints,
    required this.color,
    required this.opacity,
    required this.imageBounds,
    required this.markerScale,
  });

  Offset _toScreen(Offset ratio) => Offset(
        imageBounds.offsetX + ratio.dx * imageBounds.width,
        imageBounds.offsetY + ratio.dy * imageBounds.height,
      );

  void _drawStroke(
    Canvas canvas,
    List<Offset> points,
    double widthRatio,
    bool isEraser,
    bool isShape, {
    bool isSquare = false,
  }) {
    if (points.isEmpty) return;
    final screenPoints = points.map(_toScreen).toList(growable: false);

    if (isShape && screenPoints.length >= 3) {
      final polyPaint = isEraser
          ? (Paint()
            ..blendMode = BlendMode.clear
            ..style = PaintingStyle.fill
            ..isAntiAlias = true)
          : (Paint()
            ..color = color.withValues(alpha: 1.0)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true);
      final path = Path()..addPolygon(screenPoints, true);
      canvas.drawPath(path, polyPaint);
      return;
    }

    final diameterPx = (widthRatio * imageBounds.width).clamp(3.0, 120.0);
    final radiusPx = diameterPx / 2;

    final fillPaint = isEraser
        ? (Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.fill
          ..isAntiAlias = true)
        : (Paint()
          ..color = color.withValues(alpha: 1.0)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true);

    if (isSquare) {
      paintSquareBrush(canvas, screenPoints, diameterPx, fillPaint);
      return;
    }

    final bridgePaint = isEraser
        ? (Paint()
          ..blendMode = BlendMode.clear
          ..strokeWidth = diameterPx
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true)
        : (Paint()
          ..color = color.withValues(alpha: 1.0)
          ..strokeWidth = diameterPx
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true);

    for (var i = 0; i < screenPoints.length; i++) {
      canvas.drawCircle(screenPoints[i], radiusPx, fillPaint);
      if (i > 0) {
        canvas.drawLine(screenPoints[i - 1], screenPoints[i], bridgePaint);
      }
    }
  }

  void _drawActivePenOverlay(Canvas canvas) {
    if (penPoints.isEmpty) return;
    final screenPts = penPoints.map(_toScreen).toList(growable: false);

    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = (1.6 * markerScale).clamp(0.8, 2.5)
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final path = Path()..moveTo(screenPts.first.dx, screenPts.first.dy);
    for (var i = 1; i < screenPts.length; i++) {
      path.lineTo(screenPts[i].dx, screenPts[i].dy);
    }
    if (screenPts.length >= 3) {
      path.close();
    }
    canvas.drawPath(path, outlinePaint);

    final handleRadius = (5.0 * markerScale).clamp(2.5, 7.0);
    for (var i = 0; i < screenPts.length; i++) {
      final isFirst = i == 0 && screenPts.length >= 3;
      final fillPaint = Paint()
        ..color = isFirst ? Colors.greenAccent : Colors.white
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.black87
        ..strokeWidth = (1.4 * markerScale).clamp(0.7, 2.0)
        ..style = PaintingStyle.stroke;

      final r = isFirst ? handleRadius * 1.25 : handleRadius;
      canvas.drawCircle(screenPts[i], r, fillPaint);
      canvas.drawCircle(screenPts[i], r, strokePaint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    for (final stroke in strokes) {
      _drawStroke(
        canvas,
        stroke.points,
        stroke.widthRatio,
        stroke.isEraser,
        stroke.isShape,
        isSquare: stroke.isSquare,
      );
    }

    if (currentStroke.isNotEmpty) {
      _drawStroke(
        canvas,
        currentStroke,
        currentStrokeWidthRatio,
        currentIsEraser,
        false,
        isSquare: currentIsSquare,
      );
    }

    if (penPoints.length >= 3) {
      _drawStroke(
        canvas,
        penPoints,
        currentStrokeWidthRatio,
        false,
        true,
      );
    }

    canvas.restore();

    if (penPoints.isNotEmpty) {
      _drawActivePenOverlay(canvas);
    }
  }

  @override
  bool shouldRepaint(covariant AreaStrokePainter oldDelegate) => true;
}
