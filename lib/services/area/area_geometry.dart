import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import '../../widgets/square_brush.dart';

const double _defaultBrushRatio = 0.018;
const double _minBrushRatio = 0.004;
const double _maxBrushRatio = 0.08;

class AreaStrokeData {
  final List<Offset> points;
  final double widthRatio;
  final bool isEraser;
  final bool isShape;
  final bool isSquare;

  const AreaStrokeData({
    required this.points,
    required this.widthRatio,
    required this.isEraser,
    this.isShape = false,
    this.isSquare = false,
  });
}

/// 按笔画顺序覆盖判断点位是否落在区域内（橡皮擦命中会移出区域）。
bool isPointInAreaJson(double x, double y, String strokesJson) {
  return isPointInParsedStrokes(x, y, parseAreaStrokes(strokesJson));
}

bool isPointInParsedStrokes(
  double x,
  double y,
  List<AreaStrokeData> strokes,
) {
  if (strokes.isEmpty) return false;
  final point = Offset(x, y);
  var isInside = false;
  for (final stroke in strokes) {
    if (stroke.points.isEmpty) continue;
    if (!_isPointOnStroke(point, stroke)) continue;
    isInside = !stroke.isEraser;
  }
  return isInside;
}

List<AreaStrokeData> parseAreaStrokes(String json) {
  try {
    final data = jsonDecode(json) as List;
    return data.map((stroke) {
      if (stroke is Map) {
        final pointsRaw = (stroke['q'] as List?) ??
            (stroke['points'] as List?) ??
            (stroke['p'] as List?) ??
            const [];
        final widthRatio = _normalizeWidthRatio(
          ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))?.toDouble(),
        ).clamp(_minBrushRatio, _maxBrushRatio);
        return AreaStrokeData(
          points: _parseStrokePoints(
            pointsRaw,
            isDeltaPacked: stroke['q'] != null,
          ),
          widthRatio: widthRatio,
          isEraser: _parseBoolFlag(stroke['isEraser'] ?? stroke['e']),
          isShape: _parseBoolFlag(stroke['isShape'] ?? stroke['s']),
          isSquare: parseSquareBrush(stroke),
        );
      }

      final points =
          stroke is List ? _parseStrokePoints(stroke) : const <Offset>[];
      return AreaStrokeData(
        points: points,
        widthRatio: _defaultBrushRatio,
        isEraser: false,
      );
    }).toList();
  } catch (_) {
    return const [];
  }
}

double _normalizeWidthRatio(double? raw) {
  if (raw == null) return _defaultBrushRatio;
  return raw > 1.0 ? raw / 1000.0 : raw;
}

bool _parseBoolFlag(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return false;
}

List<Offset> _parseStrokePoints(List raw, {bool isDeltaPacked = false}) {
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

List<Offset> _parseFlatNumericPoints(
  List raw, {
  required bool isDeltaPacked,
}) {
  if (raw.length < 2) return const [];
  final points = <Offset>[];
  double? x;
  double? y;
  for (int i = 0; i + 1 < raw.length; i += 2) {
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

bool _isPointOnStroke(Offset point, AreaStrokeData stroke) {
  final points = stroke.points;
  if (stroke.isShape && points.length >= 3) {
    return _isPointInPolygon(point, points);
  }
  final radius =
      (stroke.widthRatio / 2).clamp(_minBrushRatio / 2, _maxBrushRatio / 2);
  if (stroke.isSquare) {
    if (points.length == 1) {
      return _isPointInSquareSweep(point, points.first, points.first, radius);
    }
    for (int i = 0; i < points.length - 1; i++) {
      if (_isPointInSquareSweep(point, points[i], points[i + 1], radius)) {
        return true;
      }
    }
    return false;
  }

  final radiusSquared = radius * radius;
  if (points.length == 1) {
    final dx = point.dx - points.first.dx;
    final dy = point.dy - points.first.dy;
    return dx * dx + dy * dy <= radiusSquared;
  }

  for (int i = 0; i < points.length - 1; i++) {
    if (_distanceSquaredToSegment(point, points[i], points[i + 1]) <=
        radiusSquared) {
      return true;
    }
  }
  return false;
}

/// 利用切比雪夫距离判定点是否落在轴对齐方形笔刷扫掠带内。
bool _isPointInSquareSweep(Offset p, Offset a, Offset b, double h) {
  var lo = 0.0;
  var hi = 1.0;
  for (final (r, d) in [
    (p.dx - a.dx, b.dx - a.dx),
    (p.dy - a.dy, b.dy - a.dy),
  ]) {
    if (d.abs() < 1e-12) {
      if (r.abs() > h) return false;
      continue;
    }
    final t1 = (r - h) / d;
    final t2 = (r + h) / d;
    lo = math.max(lo, math.min(t1, t2));
    hi = math.min(hi, math.max(t1, t2));
    if (lo > hi) return false;
  }
  return true;
}

bool _isPointInPolygon(Offset point, List<Offset> polygon) {
  var inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].dx;
    final yi = polygon[i].dy;
    final xj = polygon[j].dx;
    final yj = polygon[j].dy;
    final denom = (yj - yi) == 0 ? 1e-12 : (yj - yi);
    final intersect = ((yi > point.dy) != (yj > point.dy)) &&
        (point.dx < (xj - xi) * (point.dy - yi) / denom + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

double _distanceSquaredToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;
  final abLen2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (abLen2 <= 1e-12) {
    return ap.dx * ap.dx + ap.dy * ap.dy;
  }

  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLen2).clamp(0.0, 1.0);
  final dx = p.dx - (a.dx + ab.dx * t);
  final dy = p.dy - (a.dy + ab.dy * t);
  return dx * dx + dy * dy;
}
