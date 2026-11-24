import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/overlay_snapshot.dart';
import 'package:grenade_helper/services/grenade_cluster_service.dart';
import 'package:grenade_helper/services/media_handle_service.dart';
import 'package:grenade_helper/services/overlay_ipc_client.dart';
import 'package:grenade_helper/services/overlay_state_service.dart';

OverlayGrenadeItem _makeGrenade({
  required int id,
  required double x,
  required double y,
  int type = GrenadeType.smoke,
  String title = '',
  List<OverlayStepItem> steps = const [],
}) {
  return OverlayGrenadeItem(
    id: id,
    title: title.isEmpty ? 'G$id' : title,
    type: type,
    xRatio: x,
    yRatio: y,
    steps: steps,
  );
}

OverlayStepItem _makeStep(int index) {
  return OverlayStepItem(
    stepIndex: index,
    title: 'Step $index',
    description: 'Desc $index',
    medias: const [],
  );
}

OverlayMapSnapshot _makeSnapshot({
  int mapId = 1,
  int layerId = 10,
  String mapName = 'Mirage',
  List<OverlayGrenadeItem> grenades = const [],
}) {
  return OverlayMapSnapshot(
    mapId: mapId,
    mapName: mapName,
    layerId: layerId,
    layerAssetPath: 'assets/maps/mirage.png',
    grenades: grenades,
  );
}

void main() {
  group('GrenadeClusterService sorting and clustering', () {
    test(
        'defaultThreshold remains 0.03 and compareGrenades prioritizes y, x, id',
        () {
      expect(GrenadeClusterService.defaultThreshold, 0.03);

      final items = [
        _makeGrenade(id: 3, x: 0.2, y: 0.5),
        _makeGrenade(id: 2, x: 0.2, y: 0.5),
        _makeGrenade(id: 4, x: 0.1, y: 0.5),
        _makeGrenade(id: 1, x: 0.9, y: 0.2),
      ];

      final sorted = GrenadeClusterService.sortGrenades(items);
      expect(sorted.map((g) => g.id).toList(), [1, 4, 2, 3]);
    });

    test(
        'buildClusters applies strict < threshold boundary and immutable lists',
        () {
      expect(GrenadeClusterService.buildClusters(const []), isEmpty);

      // 坐标差值恰好等于 0.03 时因严格小于判定不得聚入同一簇
      final anchor = _makeGrenade(id: 10, x: 0.20, y: 0.20);
      final inside = _makeGrenade(id: 11, x: 0.229, y: 0.20);
      final onBoundary = _makeGrenade(id: 12, x: 0.23, y: 0.20);
      final far = _makeGrenade(id: 13, x: 0.80, y: 0.80);

      final clusters = GrenadeClusterService.buildClusters([
        far,
        onBoundary,
        inside,
        anchor,
      ]);

      expect(clusters, hasLength(3));
      expect(clusters[0].anchor.id, 10);
      expect(clusters[0].members.map((g) => g.id).toList(), [10, 11]);
      expect(clusters[1].members.map((g) => g.id).toList(), [12]);
      expect(clusters[2].members.map((g) => g.id).toList(), [13]);

      expect(() => clusters.add(clusters.first), throwsUnsupportedError);
      expect(() => clusters[0].members.add(far), throwsUnsupportedError);

      expect(
        GrenadeClusterService.findClusterForGrenade(clusters, inside)
            ?.anchor
            .id,
        10,
      );
      expect(
        GrenadeClusterService.findClusterForGrenade(clusters, null),
        isNull,
      );
      expect(
        GrenadeClusterService.findClusterForGrenade(
          clusters,
          _makeGrenade(id: 999, x: 0, y: 0),
        ),
        isNull,
      );
    });
  });

  group('OverlayStateService snapshot, filtering, and step switching', () {
    test('initial defaults, snapshot loading, memory per map, and clearMap',
        () {
      final state = OverlayStateService();
      addTearDown(state.dispose);

      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      expect(state.hasMap, isFalse);
      expect(state.currentGrenade, isNull);
      expect(state.crosshairX, 0.5);
      expect(state.crosshairY, 0.5);
      expect(state.navSpeedLevel, 3);
      expect(state.overlayOpacity, 0.9);
      expect(state.overlaySizeIndex, 1);
      expect(
        state.activeFilters,
        equals({
          GrenadeType.smoke,
          GrenadeType.flash,
          GrenadeType.molotov,
          GrenadeType.he,
          GrenadeType.wallbang,
        }),
      );

      final g1 = _makeGrenade(
        id: 1,
        x: 0.2,
        y: 0.2,
        steps: [_makeStep(0), _makeStep(1)],
      );
      final g2 = _makeGrenade(
        id: 2,
        x: 0.21,
        y: 0.2,
        steps: [_makeStep(0), _makeStep(1), _makeStep(2)],
      );
      final g3 = _makeGrenade(id: 3, x: 0.7, y: 0.7, steps: [_makeStep(0)]);

      state.applyMapSnapshot(
          _makeSnapshot(mapId: 1, layerId: 10, grenades: [g3, g2, g1]));
      expect(notifyCount, 1);
      expect(state.hasMap, isTrue);
      expect(state.mapName, 'Mirage');
      expect(state.currentGrenade?.id, 1);
      expect(state.crosshairX, 0.2);
      expect(state.crosshairY, 0.2);
      expect(state.isSnapped, isTrue);
      expect(state.isSnapConfirmed, isTrue);

      state.nextGrenade();
      expect(state.currentGrenade?.id, 2);
      state.nextStep();
      state.nextStep();
      expect(state.currentStepIndex, 2);

      // 同地图同图层刷新快照时应保留当前选中道具并将步骤索引限制在合法范围内
      final g2Reduced = _makeGrenade(
        id: 2,
        x: 0.21,
        y: 0.2,
        steps: [_makeStep(0), _makeStep(1)],
      );
      state.applyMapSnapshot(
        _makeSnapshot(mapId: 1, layerId: 10, grenades: [g1, g2Reduced, g3]),
      );
      expect(state.currentGrenade?.id, 2);
      expect(state.currentStepIndex, 1);

      // 切换到其他地图再切回原地图时应恢复上次查看的点位
      state.applyMapSnapshot(
        _makeSnapshot(
            mapId: 2, layerId: 20, mapName: 'Inferno', grenades: [g3]),
      );
      expect(state.currentGrenade?.id, 3);
      state.applyMapSnapshot(
        _makeSnapshot(mapId: 1, layerId: 10, grenades: [g1, g2Reduced, g3]),
      );
      expect(state.currentGrenade?.id, 2);
      expect(state.currentStepIndex, 0);

      state.clearMap();
      expect(state.hasMap, isFalse);
      expect(state.allGrenades, isEmpty);
      expect(state.filteredGrenades, isEmpty);
      expect(state.currentGrenade, isNull);
      expect(state.isSnapped, isFalse);
    });

    test('toggleFilter preserves at least one filter and updates selection',
        () {
      final state = OverlayStateService();
      addTearDown(state.dispose);

      final smoke =
          _makeGrenade(id: 1, x: 0.2, y: 0.2, type: GrenadeType.smoke);
      final flash =
          _makeGrenade(id: 2, x: 0.4, y: 0.4, type: GrenadeType.flash);
      state.applyMapSnapshot(_makeSnapshot(grenades: [smoke, flash]));

      state.toggleFilter(GrenadeType.smoke);
      expect(state.filteredGrenades.map((g) => g.id).toList(), [2]);
      expect(state.currentGrenade?.id, 2);

      state.toggleFilter(GrenadeType.molotov);
      state.toggleFilter(GrenadeType.he);
      state.toggleFilter(GrenadeType.wallbang);
      expect(state.activeFilters, {GrenadeType.flash});

      // 仅剩最后一个激活类型时，不允许全部关闭
      state.toggleFilter(GrenadeType.flash);
      expect(state.activeFilters, {GrenadeType.flash});
      expect(state.filteredGrenades, hasLength(1));

      state.toggleFilter(GrenadeType.smoke);
      expect(state.filteredGrenades, hasLength(2));
    });

    test('cluster grenade navigation and step cycling respect boundaries', () {
      final state = OverlayStateService();
      addTearDown(state.dispose);

      final a = _makeGrenade(
        id: 1,
        x: 0.3,
        y: 0.3,
        steps: [_makeStep(0), _makeStep(1)],
      );
      final b = _makeGrenade(
        id: 2,
        x: 0.31,
        y: 0.3,
        steps: [_makeStep(0), _makeStep(1), _makeStep(2)],
      );
      final isolated = _makeGrenade(id: 3, x: 0.8, y: 0.8);

      state.applyMapSnapshot(_makeSnapshot(grenades: [a, b, isolated]));
      expect(state.currentClusterGrenades.map((g) => g.id).toList(), [1, 2]);
      expect(state.currentClusterIndex, 0);

      // 簇内切换不循环越界且自动重置步骤索引
      state.prevGrenade();
      expect(state.currentGrenade?.id, 1);
      state.nextStep();
      expect(state.currentStepIndex, 1);

      state.nextGrenade();
      expect(state.currentGrenade?.id, 2);
      expect(state.currentStepIndex, 0);
      state.nextGrenade();
      expect(state.currentGrenade?.id, 2);

      // 步骤切换支持双向循环取模
      state.prevStep();
      expect(state.currentStepIndex, 2);
      state.nextStep();
      expect(state.currentStepIndex, 0);

      // setGrenadeIndex 对越界值静默忽略
      state.setGrenadeIndex(2);
      expect(state.currentGrenade?.id, 3);
      state.setGrenadeIndex(99);
      expect(state.currentGrenade?.id, 3);
      state.prevStep();
      expect(state.currentStepIndex, 0);
    });
  });

  group('OverlayStateService four-direction navigation and snapping', () {
    test('navigateDirection moves in all four directions and clamps to [0, 1]',
        () {
      final state = OverlayStateService();
      addTearDown(state.dispose);

      // 放置两个远离中心区域的点位以免步进过程中意外吸附干扰纯位移校验
      state.applyMapSnapshot(
        _makeSnapshot(grenades: [_makeGrenade(id: 1, x: 0.5, y: 0.5)]),
      );

      state.navigateDirection(NavigationDirection.right);
      final rightX = state.crosshairX;
      expect(rightX, greaterThan(0.5));
      expect(state.crosshairY, 0.5);
      expect(state.isSnapped, isFalse);

      state.navigateDirection(NavigationDirection.down);
      expect(state.crosshairX, closeTo(rightX, 1e-9));
      expect(state.crosshairY, greaterThan(0.5));

      state.navigateDirection(NavigationDirection.left);
      expect(state.crosshairX, lessThan(rightX));

      state.navigateDirection(NavigationDirection.up);
      expect(state.crosshairY, closeTo(0.5, 1e-9));

      for (var i = 0; i < 40; i++) {
        state.navigateDirection(NavigationDirection.left);
        state.navigateDirection(NavigationDirection.up);
      }
      expect(state.crosshairX, 0.0);
      expect(state.crosshairY, 0.0);

      for (var i = 0; i < 40; i++) {
        state.navigateDirection(NavigationDirection.right);
        state.navigateDirection(NavigationDirection.down);
      }
      expect(state.crosshairX, 1.0);
      expect(state.crosshairY, 1.0);
    });

    test('four-direction step snaps to adjacent point and confirms after 100ms',
        () async {
      final state = OverlayStateService();
      addTearDown(state.dispose);

      // 速度档位 3 对应步长 0.004 * 8 = 0.032，脱离步长 max(0.032, 0.024 * 1.5 = 0.036) = 0.036
      final center = _makeGrenade(id: 1, x: 0.500, y: 0.500);
      final rightTarget = _makeGrenade(id: 2, x: 0.540, y: 0.500);
      final downTarget = _makeGrenade(id: 3, x: 0.540, y: 0.540);
      final leftTarget = _makeGrenade(id: 4, x: 0.500, y: 0.540);

      state.applyMapSnapshot(
        _makeSnapshot(grenades: [center, rightTarget, downTarget, leftTarget]),
      );
      expect(state.currentGrenade?.id, 1);

      state.navigateDirection(NavigationDirection.right);
      expect(state.currentGrenade?.id, 2);
      expect(state.isSnapped, isTrue);
      expect(state.crosshairX, 0.540);
      expect(state.isSnapConfirmed, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(state.isSnapConfirmed, isTrue);

      state.navigateDirection(NavigationDirection.down);
      expect(state.currentGrenade?.id, 3);
      expect(state.crosshairX, 0.540);
      expect(state.crosshairY, 0.540);

      state.navigateDirection(NavigationDirection.left);
      expect(state.currentGrenade?.id, 4);
      expect(state.crosshairX, 0.500);
      expect(state.crosshairY, 0.540);

      // 向上返回原点 (id: 1) 验证四个方向形成闭环切换
      state.navigateDirection(NavigationDirection.up);
      expect(state.currentGrenade?.id, center.id);
      expect(state.crosshairX, 0.500);
      expect(state.crosshairY, 0.500);
    });

    test(
        'continuous navigation, opposite cancellation, speed, and lock control',
        () async {
      final state = OverlayStateService();
      addTearDown(state.dispose);

      state.applyMapSnapshot(
        _makeSnapshot(grenades: [_makeGrenade(id: 1, x: 0.5, y: 0.5)]),
      );

      state.setNavSpeedLevel(99);
      expect(state.navSpeedLevel, 5);
      state.decreaseNavSpeed();
      expect(state.navSpeedLevel, 4);
      state.setNavSpeedLevel(0);
      expect(state.navSpeedLevel, 1);
      state.increaseNavSpeed();
      expect(state.navSpeedLevel, 2);

      // 向右启动后立刻按下反方向左键应取消向右移动
      state.startNavigation(NavigationDirection.right);
      expect(state.crosshairX, greaterThan(0.5));
      final afterRightX = state.crosshairX;

      state.startNavigation(NavigationDirection.left);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      state.stopNavigation(NavigationDirection.left);
      expect(state.crosshairX, lessThan(afterRightX));
      expect(state.isSnapped, isFalse);

      // 静止超过 500ms 后抑制标记解除，若仍在吸附半径内应自动回吸点位
      await Future<void>.delayed(const Duration(milliseconds: 560));
      expect(state.isSnapped, isTrue);
      expect(state.currentGrenade?.id, 1);

      // 锁定导航后应阻止单步和连续移动
      state.setNavigationLocked(true);
      expect(state.navigationLocked, isTrue);
      final lockedX = state.crosshairX;
      final lockedY = state.crosshairY;
      state.navigateDirection(NavigationDirection.right);
      state.startNavigation(NavigationDirection.down);
      expect(state.crosshairX, lockedX);
      expect(state.crosshairY, lockedY);

      state.setNavigationLocked(false);
      state.stopAllNavigation();
    });

    test('opacity, refresh, and video toggle callback trigger listeners', () {
      final state = OverlayStateService();
      addTearDown(state.dispose);

      var notifications = 0;
      var videoToggled = 0;
      state.addListener(() => notifications++);

      state.setOpacity(0.65);
      expect(state.overlayOpacity, 0.65);
      state.refresh();
      expect(notifications, 2);

      state.setVideoTogglePlayPauseCallback(() => videoToggled++);
      state.triggerVideoTogglePlayPause();
      expect(videoToggled, 1);
      state.setVideoTogglePlayPauseCallback(null);
      state.triggerVideoTogglePlayPause();
      expect(videoToggled, 1);
    });
  });

  group('IPC client arg parsing & MediaHandleService contracts', () {
    test('OverlayIpcClient.parseArgs extracts valid port and token only', () {
      expect(
        OverlayIpcClient.parseArgs(
            ['--overlay', '--port', '8123', '--token', 'abc']),
        (port: 8123, token: 'abc'),
      );
      expect(
        OverlayIpcClient.parseArgs(['--port', 'not-int', '--token', 'abc']),
        isNull,
      );
      expect(
        OverlayIpcClient.parseArgs(['--port', '8123', '--token', '']),
        isNull,
      );
    });

    test(
        'MediaHandleService normalizes paths and dispatches local + external releasers',
        () async {
      final previousExternal = MediaHandleService.externalReleaser;
      final tokenA = Object();
      final tokenB = Object();
      addTearDown(() {
        MediaHandleService.unregister(tokenA);
        MediaHandleService.unregister(tokenB);
        MediaHandleService.externalReleaser = previousExternal;
      });

      var releasedA = 0;
      var releasedB = 0;
      List<String>? externalReceived;

      final samplePath =
          '${Directory.current.path}${Platform.pathSeparator}sample_video.mp4';
      MediaHandleService.register(tokenA, ' $samplePath ', () async {
        releasedA++;
      });
      MediaHandleService.register(tokenB, samplePath, () async {
        releasedB++;
        throw StateError('ignore failure');
      });
      MediaHandleService.externalReleaser = (paths) async {
        externalReceived = paths;
      };

      final queryPath =
          Platform.isWindows ? samplePath.toUpperCase() : samplePath;
      await MediaHandleService.releasePaths([queryPath, ' $queryPath ', '']);

      expect(releasedA, 1);
      expect(releasedB, 1);
      expect(externalReceived, [queryPath]);
    });
  });
}
