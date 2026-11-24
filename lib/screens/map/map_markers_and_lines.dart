import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../widgets/grenade_type_icon.dart';
import 'map_clustering.dart';
import 'map_painters.dart';

Color mapTeamColor(int team) {
  switch (team) {
    case TeamType.ct:
      return Colors.blueAccent;
    case TeamType.t:
      return Colors.amber;
    default:
      return Colors.white;
  }
}

Color mapTypeColor(int type) {
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

// 道具列表与分组芯片使用的亮色映射，保持与主画布图标色值区分
Color mapGroupTypeColor(int type) {
  switch (type) {
    case GrenadeType.smoke:
      return Colors.white;
    case GrenadeType.he:
      return Colors.greenAccent;
    case GrenadeType.molotov:
      return Colors.deepOrangeAccent;
    case GrenadeType.flash:
      return Colors.yellowAccent;
    case GrenadeType.wallbang:
      return Colors.lightBlueAccent;
    default:
      return Colors.white;
  }
}

String mapTeamName(int team) {
  switch (team) {
    case TeamType.ct:
      return "CT";
    case TeamType.t:
      return "T";
    default:
      return "通用";
  }
}

String mapTypeName(int type) {
  switch (type) {
    case GrenadeType.smoke:
      return "烟雾";
    case GrenadeType.flash:
      return "闪光";
    case GrenadeType.molotov:
      return "燃烧";
    case GrenadeType.he:
      return "手雷";
    case GrenadeType.wallbang:
      return "穿点";
    default:
      return "";
  }
}

class MapImpactAreaOverlay extends ConsumerWidget {
  final Grenade grenade;
  final BoxConstraints constraints;

  const MapImpactAreaOverlay({
    super.key,
    required this.grenade,
    required this.constraints,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strokes = parseImpactStrokes(grenade.impactAreaStrokes);
    if (strokes.isEmpty) return const SizedBox.shrink();

    final imageBounds =
        computeMapImageBounds(constraints.maxWidth, constraints.maxHeight);
    final color = mapTypeColor(grenade.type);
    final opacity = ref.watch(impactAreaOpacityProvider);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: ImpactAreaPainter(
            strokes: strokes,
            currentStroke: const [],
            currentStrokeWidth: 15,
            isCurrentEraser: false,
            color: color,
            imageBounds: imageBounds,
            opacity: opacity,
          ),
        ),
      ),
    );
  }
}

class MapImpactClusterMarker extends StatelessWidget {
  final GrenadeCluster cluster;
  final double markerScale;
  final MapImageBounds imageBounds;
  final bool denseStyle;
  final double? overrideX;
  final double? overrideY;
  final bool isSelected;
  final bool isDragging;
  final bool isJoystickMoving;
  final VoidCallback onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  const MapImpactClusterMarker({
    super.key,
    required this.cluster,
    required this.markerScale,
    required this.imageBounds,
    required this.denseStyle,
    this.overrideX,
    this.overrideY,
    required this.isSelected,
    required this.isDragging,
    required this.isJoystickMoving,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (cluster.grenades.isEmpty) return const SizedBox.shrink();

    const double size = 20.0;
    const double baseHalfSize = size / 2;

    final effectiveX = overrideX ?? cluster.xRatio;
    final effectiveY = overrideY ?? cluster.yRatio;

    final left =
        imageBounds.offsetX + effectiveX * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + effectiveY * imageBounds.height - baseHalfSize;

    final useGlowEffects =
        !denseStyle || isDragging || isJoystickMoving || isSelected;
    final impactColor = cluster.grenades.length > 1
        ? Colors.purpleAccent
        : mapTypeColor(cluster.primaryType);

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: onTap,
          onLongPressStart: onLongPressStart,
          onLongPressMoveUpdate: onLongPressMoveUpdate,
          onLongPressEnd: onLongPressEnd,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: (isDragging || isJoystickMoving)
                  ? Colors.cyan.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: denseStyle ? 0.28 : 0.4),
              shape: BoxShape.circle,
              border: Border.all(
                color: (isDragging || isJoystickMoving)
                    ? Colors.cyan
                    : (isSelected ? Colors.white : impactColor),
                width: (isDragging || isJoystickMoving) ? 3 : 2,
              ),
              boxShadow: useGlowEffects
                  ? (isDragging || isJoystickMoving)
                      ? [
                          BoxShadow(
                            color: Colors.cyan.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 3,
                          ),
                        ]
                      : isSelected
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.6),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: impactColor.withValues(alpha: 0.3),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                  : null,
            ),
            child: Icon(
              (isDragging || isJoystickMoving) ? Icons.open_with : Icons.close,
              size: size * 0.6,
              color: (isDragging || isJoystickMoving)
                  ? Colors.white
                  : (isSelected ? Colors.white : impactColor),
            ),
          ),
        ),
      ),
    );
  }
}

class MapThrowClusterMarker extends StatelessWidget {
  final GrenadeCluster cluster;
  final double markerScale;
  final MapImageBounds imageBounds;
  final bool denseStyle;
  final bool useLegacyMarkers;
  final double? overrideX;
  final double? overrideY;
  final VoidCallback onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  const MapThrowClusterMarker({
    super.key,
    required this.cluster,
    required this.markerScale,
    required this.imageBounds,
    required this.denseStyle,
    required this.useLegacyMarkers,
    this.overrideX,
    this.overrideY,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final color = mapTeamColor(cluster.primaryTeam);
    final count = cluster.grenades.length;
    final showCountText = count > 1;
    const double baseHalfSize = 10.0;

    final effectiveX = overrideX ?? cluster.xRatio;
    final effectiveY = overrideY ?? cluster.yRatio;

    final left =
        imageBounds.offsetX + effectiveX * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + effectiveY * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: onTap,
          onLongPressStart: onLongPressStart,
          onLongPressMoveUpdate: onLongPressMoveUpdate,
          onLongPressEnd: onLongPressEnd,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: denseStyle
                      ? null
                      : [
                          if (cluster.hasFavorite)
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                        ],
                ),
                child: cluster.hasMultipleTypes
                    ? Icon(
                        Icons.layers,
                        size: 10,
                        color: Colors.purpleAccent.withValues(alpha: 0.9),
                      )
                    : GrenadeTypeIcon(
                        type: cluster.primaryType,
                        size: useLegacyMarkers ? 11 : 12.5,
                        color: mapTypeColor(cluster.primaryType),
                      ),
              ),
              if (showCountText)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (cluster.hasNewImport && !denseStyle)
                Positioned(
                  left: -2,
                  top: -2,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapThrowPointMarker extends StatelessWidget {
  final Grenade grenade;
  final double markerScale;
  final MapImageBounds imageBounds;
  final bool useLegacyMarkers;

  const MapThrowPointMarker({
    super.key,
    required this.grenade,
    required this.markerScale,
    required this.imageBounds,
    required this.useLegacyMarkers,
  });

  @override
  Widget build(BuildContext context) {
    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + grenade.xRatio * imageBounds.width - baseHalfSize;
    final top = imageBounds.offsetY +
        grenade.yRatio * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.orangeAccent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.orangeAccent.withValues(alpha: 0.4),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: GrenadeTypeIcon(
            type: grenade.type,
            size: useLegacyMarkers ? 11 : 12.5,
            color: mapTypeColor(grenade.type),
          ),
        ),
      ),
    );
  }
}

class MapSelectedThrowPointMarker extends StatelessWidget {
  final Grenade grenade;
  final double markerScale;
  final MapImageBounds imageBounds;
  final bool useLegacyMarkers;

  const MapSelectedThrowPointMarker({
    super.key,
    required this.grenade,
    required this.markerScale,
    required this.imageBounds,
    required this.useLegacyMarkers,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = mapTypeColor(grenade.type);
    const double baseHalfSize = 12.0;
    final left =
        imageBounds.offsetX + grenade.xRatio * imageBounds.width - baseHalfSize;
    final top = imageBounds.offsetY +
        grenade.yRatio * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            shape: BoxShape.circle,
            border: Border.all(
              color: typeColor,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: typeColor.withValues(alpha: 0.6),
                blurRadius: 8,
                spreadRadius: 3,
              ),
              BoxShadow(
                color: typeColor.withValues(alpha: 0.3),
                blurRadius: 16,
                spreadRadius: 6,
              ),
            ],
          ),
          child: GrenadeTypeIcon(
            type: grenade.type,
            size: useLegacyMarkers ? 13 : 15,
            color: typeColor,
          ),
        ),
      ),
    );
  }
}

class MapSelectedClusterMarker extends StatelessWidget {
  final GrenadeCluster cluster;
  final double markerScale;
  final MapImageBounds imageBounds;
  final bool useLegacyMarkers;

  const MapSelectedClusterMarker({
    super.key,
    required this.cluster,
    required this.markerScale,
    required this.imageBounds,
    required this.useLegacyMarkers,
  });

  @override
  Widget build(BuildContext context) {
    final color = mapTeamColor(cluster.primaryTeam);
    final count = cluster.grenades.length;
    final typeColor = cluster.hasMultipleTypes
        ? Colors.purpleAccent
        : mapTypeColor(cluster.primaryType);
    const double baseHalfSize = 14.0;

    final left =
        imageBounds.offsetX + cluster.xRatio * imageBounds.width - baseHalfSize;
    final top = imageBounds.offsetY +
        cluster.yRatio * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: typeColor,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: typeColor.withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: typeColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 8,
                  ),
                  if (cluster.hasFavorite)
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: cluster.hasMultipleTypes
                  ? Icon(Icons.layers, size: 14, color: typeColor)
                  : GrenadeTypeIcon(
                      type: cluster.primaryType,
                      size: useLegacyMarkers ? 15 : 17.5,
                      color: typeColor,
                    ),
            ),
            if (count > 1)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MapImpactMarker extends StatelessWidget {
  final Grenade grenade;
  final double markerScale;
  final MapImageBounds imageBounds;

  const MapImpactMarker({
    super.key,
    required this.grenade,
    required this.markerScale,
    required this.imageBounds,
  });

  @override
  Widget build(BuildContext context) {
    if (grenade.impactXRatio == null || grenade.impactYRatio == null) {
      return const SizedBox.shrink();
    }

    const double baseHalfSize = 8.0;
    final left = imageBounds.offsetX +
        grenade.impactXRatio! * imageBounds.width -
        baseHalfSize;
    final top = imageBounds.offsetY +
        grenade.impactYRatio! * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.purpleAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withValues(alpha: 0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.close, size: 10, color: Colors.purpleAccent),
        ),
      ),
    );
  }
}

class MapDashedSegmentLine extends StatelessWidget {
  final Grenade grenade;
  final MapImageBounds imageBounds;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final bool showArrow;
  final double arrowLength;

  const MapDashedSegmentLine({
    super.key,
    required this.grenade,
    required this.imageBounds,
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
    this.showArrow = false,
    this.arrowLength = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    if (grenade.impactXRatio == null || grenade.impactYRatio == null) {
      return const SizedBox.shrink();
    }
    final startX = imageBounds.offsetX + grenade.xRatio * imageBounds.width;
    final startY = imageBounds.offsetY + grenade.yRatio * imageBounds.height;
    final endX =
        imageBounds.offsetX + grenade.impactXRatio! * imageBounds.width;
    final endY =
        imageBounds.offsetY + grenade.impactYRatio! * imageBounds.height;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: DashedLinePainter(
            start: Offset(startX, startY),
            end: Offset(endX, endY),
            color: color,
            strokeWidth: strokeWidth,
            dashLength: dashLength,
            gapLength: gapLength,
            showArrow: showArrow,
            arrowLength: arrowLength,
          ),
        ),
      ),
    );
  }
}

class MapConnectionLine extends ConsumerWidget {
  final Grenade grenade;
  final double scale;
  final MapImageBounds imageBounds;

  const MapConnectionLine({
    super.key,
    required this.grenade,
    required this.scale,
    required this.imageBounds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineColorVal = ref.watch(mapLineColorProvider);
    final lineOpacity = ref.watch(mapLineOpacityProvider);
    final lineColor = Color(lineColorVal).withValues(alpha: lineOpacity);
    return MapDashedSegmentLine(
      grenade: grenade,
      imageBounds: imageBounds,
      color: lineColor,
      strokeWidth: 1.5 * scale,
      dashLength: 6 * scale,
      gapLength: 4 * scale,
    );
  }
}

class MapWallbangLine extends StatelessWidget {
  final Grenade grenade;
  final double scale;
  final MapImageBounds imageBounds;

  const MapWallbangLine({
    super.key,
    required this.grenade,
    required this.scale,
    required this.imageBounds,
  });

  @override
  Widget build(BuildContext context) {
    return MapDashedSegmentLine(
      grenade: grenade,
      imageBounds: imageBounds,
      color: Colors.cyanAccent.withValues(alpha: 0.9),
      strokeWidth: 2.0 * scale,
      dashLength: 7 * scale,
      gapLength: 4 * scale,
      showArrow: true,
      arrowLength: 9 * scale,
    );
  }
}
