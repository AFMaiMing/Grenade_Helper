import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models.dart';
import 'map_clustering.dart';
import 'map_markers_and_lines.dart';
import 'map_painters.dart';

List<Widget> buildMapMarkerOverlayWidgets({
  required BuildContext context,
  required List<Grenade> list,
  required BoxConstraints constraints,
  required double scale,
  required double markerScale,
  required MapImageBounds imageBounds,
  required MapVisibleRatioRect visibleRatioRect,
  required double pointCullMarginX,
  required double pointCullMarginY,
  required double lineCullMarginX,
  required double lineCullMarginY,
  required bool isEditMode,
  required bool isImpactMode,
  required bool useLegacyMarkers,
  required int currentLayerId,
  required SpawnGrenadePartition spawnPartition,
  required GrenadeCluster? selectedClusterForImpact,
  required int? selectedImpactTypeFilter,
  required int? selectedImpactGroupId,
  required GrenadeCluster? draggingCluster,
  required GrenadeCluster? joystickCluster,
  required GrenadeCluster? draggingImpactCluster,
  required GrenadeCluster? joystickImpactCluster,
  required bool isBatchedClusterLongPressDragActive,
  required List<GrenadeCluster>? frozenThrowBatchClusters,
  required List<GrenadeCluster>? frozenImpactBatchClusters,
  required ValueNotifier<int> batchedDragVisualTick,
  required Map<int, PictureInfo> grenadeTypePictures,
  required double adaptiveClusterThreshold,
  required List<GrenadeCluster> Function(
    List<Grenade> grenades, {
    required double threshold,
  }) getThrowClusters,
  required List<GrenadeCluster> Function(
    List<Grenade> grenades, {
    required double threshold,
  }) getImpactClusters,
  required Widget Function(GrenadeCluster cluster, bool denseStyle)
      buildImpactClusterWidget,
  required Widget Function(GrenadeCluster cluster, bool denseStyle)
      buildThrowClusterWidget,
  required void Function({
    required List<GrenadeCluster> tapClusters,
    required List<GrenadeCluster> paintClusters,
    required bool enableHitTest,
    required bool clustersAreImpact,
  }) setBatchState,
}) {
  bool isThrowPointVisible(Grenade g) => isRatioPointVisible(
        g.xRatio,
        g.yRatio,
        visibleRect: visibleRatioRect,
        marginX: pointCullMarginX,
        marginY: pointCullMarginY,
      );

  bool isImpactPointVisible(Grenade g) {
    final x = g.impactXRatio;
    final y = g.impactYRatio;
    if (x == null || y == null) return false;
    return isRatioPointVisible(
      x,
      y,
      visibleRect: visibleRatioRect,
      marginX: pointCullMarginX,
      marginY: pointCullMarginY,
    );
  }

  final filteredIds = list.map((g) => g.id).toSet();
  final filteredSelectedGrenades = selectedClusterForImpact?.grenades
          .where((g) => filteredIds.contains(g.id))
          .toList() ??
      [];

  bool matchesSelectedFilters(Grenade g) {
    if (selectedImpactTypeFilter != null &&
        g.type != selectedImpactTypeFilter) {
      return false;
    }
    if (selectedImpactGroupId != null &&
        g.impactGroupId != selectedImpactGroupId) {
      return false;
    }
    return true;
  }

  final widgets = <Widget>[];
  if (selectedClusterForImpact != null) {
    // 去重避免同一爆点区域笔画重复叠加导致透明度加深
    final visitedStrokes = <String>{};
    for (final g in filteredSelectedGrenades.where(matchesSelectedFilters)) {
      if (g.impactAreaStrokes != null &&
          g.impactAreaStrokes!.isNotEmpty &&
          !visitedStrokes.contains(g.impactAreaStrokes)) {
        visitedStrokes.add(g.impactAreaStrokes!);
        widgets.add(MapImpactAreaOverlay(
          grenade: g,
          constraints: constraints,
        ));
      }
    }
  }

  if (isImpactMode) {
    final impactClusters = getImpactClusters(
      list,
      threshold: adaptiveClusterThreshold,
    );
    final denseMarkerStyle = shouldUseDenseMarkerStyle(
      grenadeCount: list.length,
      clusterCount: impactClusters.length,
    );
    final visibleImpactClusters = impactClusters
        .where((c) => isRatioPointVisible(
              c.xRatio,
              c.yRatio,
              visibleRect: visibleRatioRect,
              marginX: pointCullMarginX,
              marginY: pointCullMarginY,
            ))
        .toList(growable: false);
    final activeImpactCluster = draggingImpactCluster ?? joystickImpactCluster;
    final useBatchImpactClusterPainter =
        selectedClusterForImpact == null && isImpactMode;

    if (useBatchImpactClusterPainter) {
      final impactClustersForBatch = (isBatchedClusterLongPressDragActive &&
              activeImpactCluster != null &&
              frozenImpactBatchClusters != null)
          ? frozenImpactBatchClusters
          : (activeImpactCluster == null
              ? visibleImpactClusters
              : visibleImpactClusters
                  .where((c) => !isSameCluster(c, activeImpactCluster))
                  .toList(growable: false));
      setBatchState(
        tapClusters: impactClustersForBatch,
        paintClusters: const [],
        enableHitTest: impactClustersForBatch.isNotEmpty,
        clustersAreImpact: true,
      );
      if (impactClustersForBatch.isNotEmpty) {
        widgets.add(
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ImpactClusterBatchPainter(
                    clusters: impactClustersForBatch,
                    imageBounds: imageBounds,
                    markerScale: markerScale,
                    denseStyle: denseMarkerStyle,
                    textDirection: Directionality.of(context),
                    typePictures:
                        Map<int, PictureInfo>.unmodifiable(grenadeTypePictures),
                    useLegacy: useLegacyMarkers,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (activeImpactCluster != null) {
        widgets.add(
          ValueListenableBuilder<int>(
            valueListenable: batchedDragVisualTick,
            builder: (_, __, ___) =>
                buildImpactClusterWidget(activeImpactCluster, denseMarkerStyle),
          ),
        );
      }
    } else {
      widgets.addAll(visibleImpactClusters
          .map((c) => buildImpactClusterWidget(c, denseMarkerStyle)));
    }
  } else {
    final cachedClusters = getThrowClusters(
      spawnPartition.regularGrenades,
      threshold: adaptiveClusterThreshold,
    );
    final visibleClusters = selectedClusterForImpact == null
        ? cachedClusters
        : cachedClusters
            .where((c) => isSameCluster(c, selectedClusterForImpact))
            .toList();
    final visibleClustersInViewport = visibleClusters
        .where((c) => isRatioPointVisible(
              c.xRatio,
              c.yRatio,
              visibleRect: visibleRatioRect,
              marginX: pointCullMarginX,
              marginY: pointCullMarginY,
            ))
        .toList(growable: false);
    final activeThrowCluster = draggingCluster ?? joystickCluster;
    final visibleSpawnClusters = spawnPartition.spawnEntries
        .map((e) => e.cluster)
        .where((c) =>
            (activeThrowCluster == null ||
                !isSameCluster(c, activeThrowCluster)) &&
            isRatioPointVisible(
              c.xRatio,
              c.yRatio,
              visibleRect: visibleRatioRect,
              marginX: pointCullMarginX,
              marginY: pointCullMarginY,
            ))
        .toList(growable: false);
    final denseMarkerStyle = shouldUseDenseMarkerStyle(
      grenadeCount: list.length,
      clusterCount: cachedClusters.length,
    );
    final useBatchClusterPainter =
        selectedClusterForImpact == null && !isImpactMode;

    if (useBatchClusterPainter) {
      final throwClustersForBatch = (isBatchedClusterLongPressDragActive &&
              activeThrowCluster != null &&
              frozenThrowBatchClusters != null)
          ? frozenThrowBatchClusters
          : (activeThrowCluster == null
              ? visibleClustersInViewport
              : visibleClustersInViewport
                  .where((c) => !isSameCluster(c, activeThrowCluster))
                  .toList(growable: false));
      final tapClusters = visibleSpawnClusters.isEmpty
          ? throwClustersForBatch
          : [...throwClustersForBatch, ...visibleSpawnClusters];
      setBatchState(
        tapClusters: tapClusters,
        paintClusters: throwClustersForBatch,
        enableHitTest: tapClusters.isNotEmpty,
        clustersAreImpact: false,
      );
      if (throwClustersForBatch.isNotEmpty) {
        widgets.add(
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ClusterBatchPainter(
                    clusters: throwClustersForBatch,
                    imageBounds: imageBounds,
                    markerScale: markerScale,
                    denseStyle: denseMarkerStyle,
                    textDirection: Directionality.of(context),
                    typePictures:
                        Map<int, PictureInfo>.unmodifiable(grenadeTypePictures),
                    useLegacy: useLegacyMarkers,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (activeThrowCluster != null) {
        widgets.add(
          ValueListenableBuilder<int>(
            valueListenable: batchedDragVisualTick,
            builder: (_, __, ___) =>
                buildThrowClusterWidget(activeThrowCluster, denseMarkerStyle),
          ),
        );
      }
    } else {
      widgets.addAll(visibleClustersInViewport
          .map((c) => buildThrowClusterWidget(c, denseMarkerStyle)));
    }
  }

  if (selectedClusterForImpact != null) {
    widgets.addAll(filteredSelectedGrenades
        .where(matchesSelectedFilters)
        .where((g) =>
            g.impactXRatio != null &&
            g.impactYRatio != null &&
            isRatioSegmentVisible(
              g.xRatio,
              g.yRatio,
              g.impactXRatio!,
              g.impactYRatio!,
              visibleRect: visibleRatioRect,
              marginX: lineCullMarginX,
              marginY: lineCullMarginY,
            ))
        .map((g) => g.type == GrenadeType.wallbang
            ? MapWallbangLine(
                grenade: g,
                scale: markerScale,
                imageBounds: imageBounds,
              )
            : MapConnectionLine(
                grenade: g,
                scale: markerScale,
                imageBounds: imageBounds,
              )));
  }

  if (!isImpactMode && selectedClusterForImpact != null) {
    final subClusters = clusterGrenades(
      filteredSelectedGrenades,
      threshold: adaptiveClusterThreshold,
    );
    if (subClusters.length == 1 && filteredSelectedGrenades.length > 1) {
      if (isRatioPointVisible(
        subClusters.first.xRatio,
        subClusters.first.yRatio,
        visibleRect: visibleRatioRect,
        marginX: pointCullMarginX,
        marginY: pointCullMarginY,
      )) {
        widgets.add(MapSelectedClusterMarker(
          cluster: subClusters.first,
          markerScale: markerScale,
          imageBounds: imageBounds,
          useLegacyMarkers: useLegacyMarkers,
        ));
      }
    } else {
      widgets.addAll(filteredSelectedGrenades.where(isThrowPointVisible).map(
            (g) => MapSelectedThrowPointMarker(
              grenade: g,
              markerScale: markerScale,
              imageBounds: imageBounds,
              useLegacyMarkers: useLegacyMarkers,
            ),
          ));
    }
    widgets.addAll(filteredSelectedGrenades
        .where((g) =>
            g.impactXRatio != null &&
            g.impactYRatio != null &&
            isImpactPointVisible(g) &&
            g.type != GrenadeType.wallbang)
        .map((g) => MapImpactMarker(
              grenade: g,
              markerScale: markerScale,
              imageBounds: imageBounds,
            )));
  }

  if (isImpactMode && selectedClusterForImpact != null) {
    final displayGrenades =
        filteredSelectedGrenades.where(matchesSelectedFilters).toList();
    widgets.addAll(displayGrenades.where(isThrowPointVisible).map(
          (g) => MapThrowPointMarker(
            grenade: g,
            markerScale: markerScale,
            imageBounds: imageBounds,
            useLegacyMarkers: useLegacyMarkers,
          ),
        ));
  }

  return widgets;
}
