import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models.dart';
import '../../spawn_point_data.dart';
import '../../widgets/grenade_type_icon.dart';
import '../../widgets/square_brush.dart';
import 'map_clustering.dart';

void _paintMapMarkerLegacyIcon(
  Canvas canvas,
  int type, {
  required Offset center,
  required double size,
  required Color color,
  required TextDirection textDirection,
}) {
  final icon = GrenadeTypeIcon.legacyIconForType(type);
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        color: color,
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
      ),
    ),
    textDirection: textDirection,
    maxLines: 1,
  )..layout();
  painter.paint(
    canvas,
    Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
  );
}

void _drawPainterIconGlyph(
  Canvas canvas,
  IconData icon,
  Color color, {
  required Offset center,
  required double size,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        inherit: false,
        color: color,
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
      ),
    ),
    textDirection: textDirection,
  )..layout();
  painter.paint(
    canvas,
    Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
  );
}

void _drawPainterTypePicture(
  Canvas canvas,
  PictureInfo pictureInfo, {
  required Offset center,
  required double size,
}) {
  final sourceSize = pictureInfo.size;
  if (sourceSize.isEmpty) return;
  final scale = size / sourceSize.longestSide;
  final drawWidth = sourceSize.width * scale;
  final drawHeight = sourceSize.height * scale;

  canvas.save();
  canvas.translate(center.dx - drawWidth / 2, center.dy - drawHeight / 2);
  canvas.scale(scale, scale);
  canvas.drawPicture(pictureInfo.picture);
  canvas.restore();
}

Color _painterTeamColor(int team) {
  switch (team) {
    case TeamType.ct:
      return Colors.blueAccent;
    case TeamType.t:
      return Colors.amber;
    default:
      return Colors.white;
  }
}

Color _painterTypeColor(int type) {
  switch (type) {
    case GrenadeType.smoke:
      return Colors.white;
    case GrenadeType.flash:
      return Colors.yellow;
    case GrenadeType.molotov:
      return Colors.red;
    case GrenadeType.he:
      return Colors.green;
    case GrenadeType.wallbang:
      return Colors.cyan;
    default:
      return Colors.white;
  }
}

bool _sameTypePictureMap(
  Map<int, PictureInfo> left,
  Map<int, PictureInfo> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!identical(entry.value, right[entry.key])) return false;
  }
  return true;
}

class ImpactClusterBatchPainter extends CustomPainter {
  final List<GrenadeCluster> clusters;
  final MapImageBounds imageBounds;
  final double markerScale;
  final bool denseStyle;
  final TextDirection textDirection;
  final Map<int, PictureInfo> typePictures;
  final bool useLegacy;

  ImpactClusterBatchPainter({
    required this.clusters,
    required this.imageBounds,
    required this.markerScale,
    required this.denseStyle,
    required this.textDirection,
    required this.typePictures,
    required this.useLegacy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clusters.isEmpty) return;

    for (final cluster in clusters) {
      final center = Offset(
        imageBounds.offsetX + cluster.xRatio * imageBounds.width,
        imageBounds.offsetY + cluster.yRatio * imageBounds.height,
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(markerScale, markerScale);
      _paintCluster(canvas, cluster);
      canvas.restore();
    }
  }

  void _paintCluster(Canvas canvas, GrenadeCluster cluster) {
    final impactColor = cluster.grenades.length > 1
        ? Colors.purpleAccent
        : _painterTypeColor(cluster.primaryType);

    const baseRadius = 10.0;
    final fillPaint = Paint()
      ..color = Colors.black.withValues(alpha: denseStyle ? 0.28 : 0.4)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = impactColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset.zero, baseRadius, fillPaint);
    canvas.drawCircle(Offset.zero, baseRadius, borderPaint);

    final typePicture = typePictures[cluster.primaryType];
    if (useLegacy && cluster.grenades.length == 1) {
      _paintMapMarkerLegacyIcon(
        canvas,
        cluster.primaryType,
        center: Offset.zero,
        size: 11,
        color: impactColor,
        textDirection: textDirection,
      );
    } else if (typePicture != null && cluster.grenades.length == 1) {
      _drawPainterTypePicture(
        canvas,
        typePicture,
        center: Offset.zero,
        size: 12.5,
      );
    } else {
      _drawPainterIconGlyph(
        canvas,
        Icons.close,
        impactColor,
        center: Offset.zero,
        size: 12,
        textDirection: textDirection,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ImpactClusterBatchPainter oldDelegate) {
    return oldDelegate.clusters != clusters ||
        oldDelegate.markerScale != markerScale ||
        oldDelegate.denseStyle != denseStyle ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.useLegacy != useLegacy ||
        !_sameTypePictureMap(oldDelegate.typePictures, typePictures) ||
        oldDelegate.imageBounds.width != imageBounds.width ||
        oldDelegate.imageBounds.height != imageBounds.height ||
        oldDelegate.imageBounds.offsetX != imageBounds.offsetX ||
        oldDelegate.imageBounds.offsetY != imageBounds.offsetY;
  }
}

class SolidSvgColorMapper extends ColorMapper {
  final Color color;

  const SolidSvgColorMapper(this.color);

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color sourceColor,
  ) {
    return color;
  }
}

class ClusterBatchPainter extends CustomPainter {
  final List<GrenadeCluster> clusters;
  final MapImageBounds imageBounds;
  final double markerScale;
  final bool denseStyle;
  final TextDirection textDirection;
  final Map<int, PictureInfo> typePictures;
  final bool useLegacy;

  ClusterBatchPainter({
    required this.clusters,
    required this.imageBounds,
    required this.markerScale,
    required this.denseStyle,
    required this.textDirection,
    required this.typePictures,
    required this.useLegacy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clusters.isEmpty) return;

    for (final cluster in clusters) {
      final center = Offset(
        imageBounds.offsetX + cluster.xRatio * imageBounds.width,
        imageBounds.offsetY + cluster.yRatio * imageBounds.height,
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(markerScale, markerScale);
      _paintCluster(canvas, cluster);
      canvas.restore();
    }
  }

  void _paintCluster(Canvas canvas, GrenadeCluster cluster) {
    final borderColor =
        _painterTeamColor(cluster.primaryTeam).withValues(alpha: 0.5);
    final count = cluster.grenades.length;
    final iconColor = cluster.hasMultipleTypes
        ? Colors.purpleAccent.withValues(alpha: 0.9)
        : _painterTypeColor(cluster.primaryType);

    const baseRadius = 10.0;
    final fillPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset.zero, baseRadius, fillPaint);
    canvas.drawCircle(Offset.zero, baseRadius, borderPaint);

    final typePicture = typePictures[cluster.primaryType];
    if (!cluster.hasMultipleTypes && useLegacy) {
      _paintMapMarkerLegacyIcon(
        canvas,
        cluster.primaryType,
        center: Offset.zero,
        size: 11,
        color: iconColor,
        textDirection: textDirection,
      );
    } else if (!cluster.hasMultipleTypes && typePicture != null) {
      _drawPainterTypePicture(
        canvas,
        typePicture,
        center: Offset.zero,
        size: 12.5,
      );
    } else {
      _drawPainterIconGlyph(
        canvas,
        Icons.layers,
        iconColor,
        center: Offset.zero,
        size: 10,
        textDirection: textDirection,
      );
    }

    if (count > 1) {
      const badgeCenter = Offset(8, -8);
      canvas.drawCircle(
        badgeCenter,
        6,
        Paint()..color = Colors.orange,
      );
      _drawText(
        canvas,
        '$count',
        const TextStyle(
          fontSize: 8,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        center: badgeCenter,
      );
    }

    if (cluster.hasNewImport && !denseStyle) {
      canvas.drawCircle(
        const Offset(-8, -8),
        3,
        Paint()..color = Colors.red,
      );
    }

    if (cluster.hasFavorite && !denseStyle) {
      canvas.drawCircle(
        const Offset(-8, 8),
        2.5,
        Paint()..color = Colors.amberAccent,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    TextStyle style, {
    required Offset center,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();

    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant ClusterBatchPainter oldDelegate) {
    return oldDelegate.clusters != clusters ||
        oldDelegate.markerScale != markerScale ||
        oldDelegate.denseStyle != denseStyle ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.useLegacy != useLegacy ||
        !_sameTypePictureMap(oldDelegate.typePictures, typePictures) ||
        oldDelegate.imageBounds.width != imageBounds.width ||
        oldDelegate.imageBounds.height != imageBounds.height ||
        oldDelegate.imageBounds.offsetX != imageBounds.offsetX ||
        oldDelegate.imageBounds.offsetY != imageBounds.offsetY;
  }
}

// 虚线画笔，用于绘制投掷点到爆点或穿点的连线
class DashedLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final bool showArrow;
  final double arrowLength;

  DashedLinePainter({
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
      final angle = math.atan2(direction.dy, direction.dx);
      const spread = 28 * math.pi / 180;
      final wingLength = math.min(arrowLength, totalLength * 0.45);
      final leftWing = Offset(
        end.dx - wingLength * math.cos(angle - spread),
        end.dy - wingLength * math.sin(angle - spread),
      );
      final rightWing = Offset(
        end.dx - wingLength * math.cos(angle + spread),
        end.dy - wingLength * math.sin(angle + spread),
      );
      final arrowPath = Path()
        ..moveTo(leftWing.dx, leftWing.dy)
        ..lineTo(end.dx, end.dy)
        ..lineTo(rightWing.dx, rightWing.dy);
      final arrowPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
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

class ImpactAreaPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  final List<Offset> currentStroke;
  final double currentStrokeWidth;
  final bool isCurrentEraser;
  final Color color;
  final double opacity;
  final MapImageBounds imageBounds;

  ImpactAreaPainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentStrokeWidth,
    required this.isCurrentEraser,
    required this.color,
    required this.imageBounds,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 使用 saveLayer 创建整体透明度图层，避免笔画叠加导致透明度累积
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    for (final stroke in strokes) {
      final rawPoints = stroke['points'] ?? stroke['p'];
      if (rawPoints is! List) continue;
      final points = <Offset>[];
      for (final p in rawPoints) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          points
              .add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        } else if (p is Map && p['x'] is num && p['y'] is num) {
          points.add(
              Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
        }
      }
      if (points.isEmpty) continue;
      final widthRatio =
          ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))?.toDouble();
      final width = widthRatio != null
          ? ((widthRatio > 1.0 ? widthRatio / 1000.0 : widthRatio) *
                  imageBounds.width)
              .clamp(3.0, 120.0)
          : ((stroke['strokeWidth'] as num?)?.toDouble() ?? 15.0);
      final isEraser = stroke['isEraser'] as bool? ?? false;
      final isShape = stroke['isShape'] as bool? ?? false;
      if (!isShape && parseSquareBrush(stroke)) {
        final paint = Paint()
          ..color = isEraser ? Colors.transparent : color.withValues(alpha: 1.0)
          ..blendMode = isEraser ? BlendMode.clear : BlendMode.srcOver;
        paintSquareBrush(
            canvas, points.map(_limitPoint).toList(), width, paint);
        continue;
      }
      _drawStroke(canvas, points, width, isEraser, isShape: isShape);
    }

    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke, currentStrokeWidth, isCurrentEraser);
    }

    canvas.restore();
  }

  void _drawStroke(
    Canvas canvas,
    List<Offset> points,
    double width,
    bool isEraser, {
    bool isShape = false,
  }) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = isEraser ? Colors.transparent : color.withValues(alpha: 1.0)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style =
          isShape && !isEraser ? PaintingStyle.fill : PaintingStyle.stroke;

    if (isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    final path = Path();
    final start = _limitPoint(points[0]);
    path.moveTo(start.dx, start.dy);

    if (points.length == 1) {
      path.lineTo(start.dx, start.dy);
    }

    for (int i = 1; i < points.length; i++) {
      final p = _limitPoint(points[i]);
      path.lineTo(p.dx, p.dy);
    }

    if (isShape && !isEraser) {
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  // 将相对坐标转换为画布坐标，并限制在图片区域内
  Offset _limitPoint(Offset ratio) {
    return Offset(
      imageBounds.offsetX + ratio.dx * imageBounds.width,
      imageBounds.offsetY + ratio.dy * imageBounds.height,
    );
  }

  @override
  bool shouldRepaint(covariant ImpactAreaPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color;
  }
}

class SpawnPointOverlayPainter extends CustomPainter {
  final MapSpawnConfig config;
  final MapImageBounds imageBounds;
  final double photoScale;
  final double markerScale;
  final bool showSpawns;
  final bool showCasual;
  final bool showHostages;
  final Set<String> occupiedKeys;
  final String? selectedKey;
  final TextDirection textDirection;
  final ValueNotifier<String?> hoveredKey;

  SpawnPointOverlayPainter({
    required this.config,
    required this.imageBounds,
    required this.photoScale,
    required this.markerScale,
    required this.showSpawns,
    required this.showCasual,
    required this.showHostages,
    required this.occupiedKeys,
    required this.selectedKey,
    required this.textDirection,
    required this.hoveredKey,
  }) : super(repaint: hoveredKey);

  Color _scaleAlpha(Color c, double factor) =>
      c.withValues(alpha: (c.a * factor).clamp(0.0, 1.0));

  double _labelFontSize(double side, String label) {
    if (label.length >= 3) return side * 0.39;
    if (label.length == 2) return side * 0.48;
    return side * 0.56;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final safeScale = photoScale <= 0 ? 1.0 : photoScale;
    final mapSpan = math.min(imageBounds.width, imageBounds.height);
    final minSpacingPx =
        config.minSpacingRatio(includeCasual: showSpawns && showCasual) *
            mapSpan *
            safeScale;
    final showNum = minSpacingPx >= 13.5;
    final showCasualNum = minSpacingPx >= 16.5;
    final spawnSide = showNum
        ? (minSpacingPx * 0.72).clamp(12.0, 16.0)
        : (minSpacingPx * 0.62).clamp(6.0, 8.5);
    final activeHighlight = hoveredKey.value ?? selectedKey;

    ({SpawnPoint point, String label, Color color})? hoveredItem;

    void drawSquare(
      double side,
      double cornerRadius,
      Color fill,
      Color border,
      double strokeWidth,
    ) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: side, height: side),
        Radius.circular(cornerRadius),
      );
      canvas.drawRRect(rect, Paint()..color = fill);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }

    void drawCircle(
      double radius,
      Color fill,
      Color border,
      double strokeWidth,
    ) {
      canvas.drawCircle(Offset.zero, radius, Paint()..color = fill);
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }

    void paintPoint(
      SpawnPoint p, {
      required String key,
      required String label,
      required Color fillColor,
      required Color borderColor,
      required Color textColor,
      required Color highlightColor,
      required bool isCasual,
      required bool isHostage,
    }) {
      if (!isHostage && activeHighlight == key) {
        hoveredItem = (
          point: p,
          label: label,
          color: highlightColor,
        );
        return;
      }

      final hasGrenade = isHostage || occupiedKeys.contains(key);
      final shapeAlpha = hasGrenade ? 1.0 : 0.36;
      final labelAlpha = hasGrenade ? 1.0 : 0.50;

      final cx = imageBounds.offsetX + p.x * imageBounds.width;
      final cy = imageBounds.offsetY + p.y * imageBounds.height;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(markerScale, markerScale);

      if (isHostage) {
        drawCircle(spawnSide / 2, fillColor, borderColor, 1.0);
        if (showNum) {
          _paintLabel(
            canvas,
            label,
            _labelFontSize(spawnSide, label),
            textColor,
          );
        }
      } else if (isCasual) {
        if (!showCasualNum) {
          final s = (minSpacingPx * 0.48).clamp(5.0, 7.0);
          drawSquare(
            s,
            s * 0.24,
            _scaleAlpha(const Color(0x9905070A), shapeAlpha),
            _scaleAlpha(borderColor, shapeAlpha),
            1.0,
          );
        } else {
          final s = (minSpacingPx * 0.68).clamp(12.0, 15.5);
          drawSquare(
            s,
            2.8,
            _scaleAlpha(const Color(0xC7080B10), shapeAlpha),
            _scaleAlpha(borderColor, shapeAlpha),
            1.0,
          );
          _paintLabel(
            canvas,
            label,
            _labelFontSize(s, label),
            _scaleAlpha(textColor, labelAlpha),
          );
        }
      } else {
        drawSquare(
          spawnSide,
          showNum ? 3.0 : spawnSide * 0.24,
          _scaleAlpha(fillColor, shapeAlpha),
          _scaleAlpha(borderColor, shapeAlpha),
          1.0,
        );
        if (showNum) {
          _paintLabel(
            canvas,
            label,
            _labelFontSize(spawnSide, label),
            _scaleAlpha(textColor, labelAlpha),
          );
        }
      }

      canvas.restore();
    }

    if (showSpawns) {
      if (showCasual) {
        for (final s in config.casualCtSpawns) {
          paintPoint(
            s,
            key: 'cct-${s.id}',
            label: 'C${s.id}',
            fillColor: const Color(0xC7080B10),
            borderColor: const Color(0xD960A5FA),
            textColor: const Color(0xFF93C5FD),
            highlightColor: Colors.blueAccent,
            isCasual: true,
            isHostage: false,
          );
        }
        for (final s in config.casualTSpawns) {
          paintPoint(
            s,
            key: 'ct_c-${s.id}',
            label: 'C${s.id}',
            fillColor: const Color(0xC7080B10),
            borderColor: const Color(0xD9FBBF24),
            textColor: const Color(0xFFFDE68A),
            highlightColor: Colors.amber,
            isCasual: true,
            isHostage: false,
          );
        }
      }

      for (final s in config.ctSpawns) {
        paintPoint(
          s,
          key: 'ct-${s.id}',
          label: '${s.id}',
          fillColor:
              showNum ? const Color(0xD62563EB) : const Color(0xEB448AFF),
          borderColor: const Color(0xDEFFFFFF),
          textColor: Colors.white,
          highlightColor: Colors.blueAccent,
          isCasual: false,
          isHostage: false,
        );
      }

      for (final s in config.tSpawns) {
        paintPoint(
          s,
          key: 't-${s.id}',
          label: '${s.id}',
          fillColor:
              showNum ? const Color(0xDBD97706) : const Color(0xEBFFC107),
          borderColor: const Color(0xDEFFFFFF),
          textColor: Colors.white,
          highlightColor: Colors.amber,
          isCasual: false,
          isHostage: false,
        );
      }
    }

    if (showHostages) {
      for (final h in config.hostageSpawns) {
        paintPoint(
          h,
          key: 'h-${h.id}',
          label: 'H${h.id}',
          fillColor: const Color(0xDB10B981),
          borderColor: const Color(0xE6FFFFFF),
          textColor: Colors.white,
          highlightColor: const Color(0xFF10B981),
          isCasual: false,
          isHostage: true,
        );
      }
    }

    final hovered = hoveredItem;
    if (hovered != null) {
      final cx = imageBounds.offsetX + hovered.point.x * imageBounds.width;
      final cy = imageBounds.offsetY + hovered.point.y * imageBounds.height;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(markerScale, markerScale);
      drawSquare(
        28.0,
        6.5,
        hovered.color.withValues(alpha: 0.28),
        hovered.color.withValues(alpha: 0.9),
        1.6,
      );
      drawSquare(20.0, 4.0, hovered.color, Colors.white, 1.6);
      _paintLabel(
        canvas,
        hovered.label,
        hovered.label.length >= 3 ? 8.0 : 9.5,
        Colors.white,
      );
      canvas.restore();
    }
  }

  void _paintLabel(Canvas canvas, String text, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant SpawnPointOverlayPainter oldDelegate) {
    return oldDelegate.config != config ||
        oldDelegate.imageBounds != imageBounds ||
        oldDelegate.photoScale != photoScale ||
        oldDelegate.markerScale != markerScale ||
        oldDelegate.showSpawns != showSpawns ||
        oldDelegate.showCasual != showCasual ||
        oldDelegate.showHostages != showHostages ||
        oldDelegate.occupiedKeys.length != occupiedKeys.length ||
        !oldDelegate.occupiedKeys.containsAll(occupiedKeys) ||
        oldDelegate.selectedKey != selectedKey ||
        oldDelegate.textDirection != textDirection;
  }
}
