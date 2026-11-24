import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/square_brush.dart';

const double kDefaultAreaBrushRatio = 0.018;
const double kMinAreaBrushRatio = 0.004;
const double kMaxAreaBrushRatio = 0.08;

typedef DrawImageBounds = ({
  double width,
  double height,
  double offsetX,
  double offsetY,
});

/// 区域与爆点绘图工具枚举
enum DrawTool {
  move,
  brush,
  pen,
  eraser,
  circle,
  square,
}

/// 单条笔触或多边形数据模型
class DrawStroke {
  final List<Offset> points;
  final double widthRatio;
  final bool isEraser;
  final bool isShape;
  final int shapeType;
  final Offset? center;
  final bool isSquare;

  const DrawStroke({
    required this.points,
    required this.widthRatio,
    required this.isEraser,
    this.isShape = false,
    this.shapeType = 0,
    this.center,
    this.isSquare = false,
  });
}

/// 多楼层标签绑定模式下的单层草稿状态
class LayerDraft {
  final String name;
  final int colorValue;
  final List<DrawStroke> strokes;

  const LayerDraft({
    required this.name,
    required this.colorValue,
    required this.strokes,
  });
}

/// 笔触编解码与几何辅助工具
class AreaDrawCodec {
  const AreaDrawCodec._();

  static List<DrawStroke> decodeStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      return data
          .map((stroke) {
            if (stroke is Map) {
              final pointsRaw = (stroke['q'] as List?) ??
                  (stroke['points'] as List?) ??
                  (stroke['p'] as List?) ??
                  const [];
              final points = _parseStrokePoints(
                pointsRaw,
                isDeltaPacked: stroke['q'] != null,
              );
              final rawWidthRatio =
                  ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))
                      ?.toDouble();
              final rawStrokeWidth =
                  (stroke['strokeWidth'] as num?)?.toDouble();
              final widthRatio = (rawWidthRatio != null
                      ? _normalizeWidthRatio(rawWidthRatio)
                      : (rawStrokeWidth != null
                          ? (rawStrokeWidth / 800.0)
                          : kDefaultAreaBrushRatio))
                  .clamp(kMinAreaBrushRatio, kMaxAreaBrushRatio);
              final isEraser =
                  _parseBoolFlag(stroke['isEraser'] ?? stroke['e']);
              final isShape = _parseBoolFlag(stroke['isShape'] ?? stroke['s']);
              final shapeType = (stroke['shapeType'] as num?)?.toInt() ?? 0;
              Offset? center;
              if (stroke['center'] is List &&
                  (stroke['center'] as List).length >= 2) {
                final c = stroke['center'] as List;
                if (c[0] is num && c[1] is num) {
                  center = Offset(
                    (c[0] as num).toDouble(),
                    (c[1] as num).toDouble(),
                  );
                }
              }
              return DrawStroke(
                points: points,
                widthRatio: widthRatio,
                isEraser: isEraser,
                isShape: isShape,
                shapeType: shapeType,
                center: center,
                isSquare: parseSquareBrush(stroke),
              );
            }

            final points =
                stroke is List ? _parseStrokePoints(stroke) : const <Offset>[];
            return DrawStroke(
              points: points,
              widthRatio: kDefaultAreaBrushRatio,
              isEraser: false,
            );
          })
          .where((s) => s.points.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('Error parsing strokes: $e');
      return const <DrawStroke>[];
    }
  }

  static String encodeStrokes(List<DrawStroke> strokes) {
    final data = strokes
        .map(
          (stroke) => <String, dynamic>{
            'points':
                stroke.points.map((p) => [p.dx, p.dy]).toList(growable: false),
            'widthRatio': stroke.widthRatio,
            'strokeWidth': (stroke.widthRatio * 800.0).clamp(4.0, 64.0),
            'isEraser': stroke.isEraser,
            if (stroke.isSquare) 'brushShape': 1,
            if (stroke.isShape) 'isShape': true,
            if (stroke.shapeType > 0) 'shapeType': stroke.shapeType,
            if (stroke.center != null)
              'center': [stroke.center!.dx, stroke.center!.dy],
          },
        )
        .toList();
    return jsonEncode(data);
  }

  static List<DrawStroke> cloneStrokes(List<DrawStroke> source) {
    return source
        .map(
          (stroke) => DrawStroke(
            points: List<Offset>.from(stroke.points),
            widthRatio: stroke.widthRatio,
            isEraser: stroke.isEraser,
            isShape: stroke.isShape,
            shapeType: stroke.shapeType,
            center: stroke.center,
            isSquare: stroke.isSquare,
          ),
        )
        .toList(growable: true);
  }

  static DrawImageBounds computeImageBounds(
    double containerWidth,
    double containerHeight,
  ) {
    const double imageAspectRatio = 1.0;
    final double containerAspectRatio = containerWidth / containerHeight;

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

  static List<Offset> generateCirclePoints(
    Offset center,
    double radius,
    int segments,
  ) {
    final points = <Offset>[];
    for (var i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * math.pi;
      final x = (center.dx + radius * math.cos(angle)).clamp(0.0, 1.0);
      final y = (center.dy + radius * math.sin(angle)).clamp(0.0, 1.0);
      points.add(Offset(x, y));
    }
    return points;
  }

  static List<Offset> generateSquarePoints(Offset center, double halfSize) {
    final left = (center.dx - halfSize).clamp(0.0, 1.0);
    final right = (center.dx + halfSize).clamp(0.0, 1.0);
    final top = (center.dy - halfSize).clamp(0.0, 1.0);
    final bottom = (center.dy + halfSize).clamp(0.0, 1.0);
    return [
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
      Offset(left, bottom),
      Offset(left, top),
    ];
  }

  static Offset computePolygonCenter(List<Offset> points) {
    if (points.isEmpty) return const Offset(0.5, 0.5);
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  static double _normalizeWidthRatio(double? raw) {
    if (raw == null) return kDefaultAreaBrushRatio;
    var value = raw;
    if (value > 1.0) {
      value /= 1000.0;
    }
    return value;
  }

  static bool _parseBoolFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  static List<Offset> _parseStrokePoints(List raw,
      {bool isDeltaPacked = false}) {
    if (raw.isEmpty) return const [];

    if (raw.first is num) {
      return _parseFlatNumericPoints(raw, isDeltaPacked: isDeltaPacked);
    }

    return raw
        .map((p) {
          if (p is Map && p['x'] is num && p['y'] is num) {
            return Offset(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            );
          }
          if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
            return Offset(
              (p[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            );
          }
          return null;
        })
        .whereType<Offset>()
        .toList();
  }

  static List<Offset> _parseFlatNumericPoints(
    List raw, {
    required bool isDeltaPacked,
  }) {
    if (raw.length < 2) return const [];
    final points = <Offset>[];
    double? x;
    double? y;
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final xRaw = raw[i];
      final yRaw = raw[i + 1];
      if (xRaw is! num || yRaw is! num) continue;

      if (isDeltaPacked) {
        final dx = xRaw.toDouble() / 1000.0;
        final dy = yRaw.toDouble() / 1000.0;
        if (x == null || y == null) {
          x = dx;
          y = dy;
        } else {
          x += dx;
          y += dy;
        }
      } else {
        x = xRaw.toDouble();
        y = yRaw.toDouble();
        if (x > 1.0 || y > 1.0) {
          x /= 1000.0;
          y /= 1000.0;
        }
      }

      points.add(Offset(x, y));
    }
    return points;
  }
}
