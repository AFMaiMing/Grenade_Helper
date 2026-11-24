import 'package:flutter/material.dart';

import '../../services/area/area_geometry.dart';
import '../../widgets/square_brush.dart';

/// 区域预览图像在容器内的布局边界。
typedef AreaPreviewImageBounds = ({
  double width,
  double height,
  double offsetX,
  double offsetY,
});

/// 计算 1:1 地图图像在区域预览容器内的居中边界。
AreaPreviewImageBounds computeAreaPreviewImageBounds(
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

/// 区域范围半透明覆盖绘制器。
class AreaScopePainter extends CustomPainter {
  static const double _overlayOpacity = 0.26;

  final List<AreaStrokeData> strokes;
  final Color color;
  final AreaPreviewImageBounds imageBounds;

  const AreaScopePainter({
    required this.strokes,
    required this.color,
    required this.imageBounds,
  });

  Offset _toScreen(Offset ratio) => Offset(
        imageBounds.offsetX + ratio.dx * imageBounds.width,
        imageBounds.offsetY + ratio.dy * imageBounds.height,
      );

  Paint _buildStrokePaint({
    required bool isEraser,
    required PaintingStyle style,
    double? strokeWidth,
    StrokeCap? strokeCap,
  }) {
    final paint = Paint()
      ..style = style
      ..isAntiAlias = true;
    if (isEraser) {
      paint.blendMode = BlendMode.clear;
    } else {
      paint.color = color.withValues(alpha: 1.0);
    }
    if (strokeWidth != null) paint.strokeWidth = strokeWidth;
    if (strokeCap != null) paint.strokeCap = strokeCap;
    return paint;
  }

  void _drawStroke(Canvas canvas, AreaStrokeData stroke) {
    if (stroke.points.isEmpty) return;
    final screenPoints = stroke.points.map(_toScreen).toList(growable: false);

    if (stroke.isShape && screenPoints.length >= 3) {
      final polyPaint = _buildStrokePaint(
        isEraser: stroke.isEraser,
        style: PaintingStyle.fill,
      );
      canvas.drawPath(Path()..addPolygon(screenPoints, true), polyPaint);
      return;
    }

    final diameterPx =
        (stroke.widthRatio * imageBounds.width).clamp(3.0, 120.0);
    final fillPaint = _buildStrokePaint(
      isEraser: stroke.isEraser,
      style: PaintingStyle.fill,
    );

    if (stroke.isSquare) {
      paintSquareBrush(canvas, screenPoints, diameterPx, fillPaint);
      return;
    }

    final radiusPx = diameterPx / 2;
    final bridgePaint = _buildStrokePaint(
      isEraser: stroke.isEraser,
      style: PaintingStyle.stroke,
      strokeWidth: diameterPx,
      strokeCap: StrokeCap.round,
    );

    for (int i = 0; i < screenPoints.length; i++) {
      canvas.drawCircle(screenPoints[i], radiusPx, fillPaint);
      if (i > 0) {
        canvas.drawLine(screenPoints[i - 1], screenPoints[i], bridgePaint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: _overlayOpacity),
    );
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AreaScopePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.color != color ||
        oldDelegate.imageBounds != imageBounds;
  }
}
