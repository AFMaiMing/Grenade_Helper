import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/screens/map_screen.dart';

Grenade _makeGrenade({
  required int id,
  required double xRatio,
  required double yRatio,
  int type = GrenadeType.smoke,
  int team = TeamType.all,
  bool isFavorite = false,
  bool isNewImport = false,
  double? impactXRatio,
  double? impactYRatio,
}) {
  return Grenade(
    title: 'Grenade $id',
    type: type,
    team: team,
    isFavorite: isFavorite,
    isNewImport: isNewImport,
    xRatio: xRatio,
    yRatio: yRatio,
  )
    ..id = id
    ..impactXRatio = impactXRatio
    ..impactYRatio = impactYRatio;
}

void main() {
  group('map_screen 公开导出契约与聚类回归测试', () {
    test('map_screen 导出三个地图状态 Provider 且默认值正确', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isEditModeProvider), isFalse);
      expect(container.read(selectedLayerIndexProvider), 0);
      expect(container.read(selectedTagIdsProvider), isEmpty);

      container.read(isEditModeProvider.notifier).state = true;
      container.read(selectedLayerIndexProvider.notifier).state = 2;
      container.read(selectedTagIdsProvider.notifier).state = {10, 20};

      expect(container.read(isEditModeProvider), isTrue);
      expect(container.read(selectedLayerIndexProvider), 2);
      expect(container.read(selectedTagIdsProvider), equals({10, 20}));
    });

    test('clusterGrenades 与 clusterGrenadesByImpact 处理空列表均返回空集合', () {
      expect(clusterGrenades(const []), isEmpty);
      expect(clusterGrenades(const [], threshold: 0.05), isEmpty);
      expect(clusterGrenadesByImpact(const []), isEmpty);
      expect(clusterGrenadesByImpact(const [], threshold: 0.05), isEmpty);
    });

    test('threshold <= 0 时禁用合并并保持各自独立成簇', () {
      final g1 = _makeGrenade(
        id: 1,
        xRatio: 0.2,
        yRatio: 0.3,
        impactXRatio: 0.4,
        impactYRatio: 0.5,
      );
      final g2 = _makeGrenade(
        id: 2,
        xRatio: 0.2,
        yRatio: 0.3,
        type: GrenadeType.flash,
        impactXRatio: 0.4,
        impactYRatio: 0.5,
      );
      final gNoImpact = _makeGrenade(
        id: 3,
        xRatio: 0.2,
        yRatio: 0.3,
      );
      final gWallbang = _makeGrenade(
        id: 4,
        xRatio: 0.2,
        yRatio: 0.3,
        type: GrenadeType.wallbang,
        impactXRatio: 0.4,
        impactYRatio: 0.5,
      );

      for (final threshold in [0.0, -0.02]) {
        final throwClusters = clusterGrenades([g1, g2, gNoImpact, gWallbang],
            threshold: threshold);
        expect(throwClusters, hasLength(4));
        expect(throwClusters.every((c) => c.grenades.length == 1), isTrue);

        final impactClusters = clusterGrenadesByImpact(
            [g1, g2, gNoImpact, gWallbang],
            threshold: threshold);
        expect(impactClusters, hasLength(2));
        expect(
          impactClusters.expand((c) => c.grenades).map((g) => g.id).toList(),
          equals([1, 2]),
        );
      }
    });

    test('9 宫格跨网格边界邻近点正确合并并计算质心均值', () {
      // 阈值 0.05 下，(0.049, 0.049) 与 (0.051, 0.051)、(0.052, 0.048) 落在不同网格但邻接
      final a = _makeGrenade(
        id: 1,
        xRatio: 0.049,
        yRatio: 0.049,
        impactXRatio: 0.149,
        impactYRatio: 0.149,
      );
      final b = _makeGrenade(
        id: 2,
        xRatio: 0.051,
        yRatio: 0.051,
        impactXRatio: 0.151,
        impactYRatio: 0.151,
      );
      final c = _makeGrenade(
        id: 3,
        xRatio: 0.052,
        yRatio: 0.048,
        impactXRatio: 0.152,
        impactYRatio: 0.148,
      );

      final throwClusters = clusterGrenades([a, b, c], threshold: 0.05);
      expect(throwClusters, hasLength(1));
      expect(throwClusters.first.grenades.map((g) => g.id), equals([1, 2, 3]));
      expect(
        throwClusters.first.xRatio,
        closeTo((0.049 + 0.051 + 0.052) / 3, 1e-9),
      );
      expect(
        throwClusters.first.yRatio,
        closeTo((0.049 + 0.051 + 0.048) / 3, 1e-9),
      );

      final impactClusters =
          clusterGrenadesByImpact([a, b, c], threshold: 0.05);
      expect(impactClusters, hasLength(1));
      expect(impactClusters.first.grenades.map((g) => g.id), equals([1, 2, 3]));
      expect(
        impactClusters.first.xRatio,
        closeTo((0.149 + 0.151 + 0.152) / 3, 1e-9),
      );
      expect(
        impactClusters.first.yRatio,
        closeTo((0.149 + 0.151 + 0.148) / 3, 1e-9),
      );
    });

    test('远距点与刚好达到阈值边界的点保持分离', () {
      final origin = _makeGrenade(
        id: 1,
        xRatio: 0.25,
        yRatio: 0.25,
        impactXRatio: 0.25,
        impactYRatio: 0.25,
      );
      final exactBoundary = _makeGrenade(
        id: 2,
        xRatio: 0.375,
        yRatio: 0.25,
        impactXRatio: 0.375,
        impactYRatio: 0.25,
      );
      final farAway = _makeGrenade(
        id: 3,
        xRatio: 0.75,
        yRatio: 0.75,
        impactXRatio: 0.75,
        impactYRatio: 0.75,
      );

      final throwClusters =
          clusterGrenades([origin, exactBoundary, farAway], threshold: 0.125);
      expect(throwClusters, hasLength(3));

      final impactClusters = clusterGrenadesByImpact(
          [origin, exactBoundary, farAway],
          threshold: 0.125);
      expect(impactClusters, hasLength(3));
    });

    test('GrenadeCluster 正确推导 primaryType、primaryTeam 与状态标记', () {
      final ctSmoke = _makeGrenade(
        id: 1,
        xRatio: 0.1,
        yRatio: 0.1,
        type: GrenadeType.smoke,
        team: TeamType.ct,
      );
      final tFlash = _makeGrenade(
        id: 2,
        xRatio: 0.1,
        yRatio: 0.1,
        type: GrenadeType.flash,
        team: TeamType.t,
        isFavorite: true,
      );
      final allHe = _makeGrenade(
        id: 3,
        xRatio: 0.1,
        yRatio: 0.1,
        type: GrenadeType.he,
        team: TeamType.all,
        isNewImport: true,
      );
      final ctSmokePlain = _makeGrenade(
        id: 4,
        xRatio: 0.1,
        yRatio: 0.1,
        type: GrenadeType.smoke,
        team: TeamType.ct,
      );

      final singleCluster = GrenadeCluster(
        xRatio: 0.1,
        yRatio: 0.1,
        grenades: [ctSmoke],
      );
      expect(singleCluster.primaryType, GrenadeType.smoke);
      expect(singleCluster.primaryTeam, TeamType.ct);
      expect(singleCluster.hasMultipleTypes, isFalse);
      expect(singleCluster.hasFavorite, isFalse);
      expect(singleCluster.hasNewImport, isFalse);

      final sameTypeCtWithAll = GrenadeCluster(
        xRatio: 0.1,
        yRatio: 0.1,
        grenades: [ctSmoke, ctSmokePlain],
      );
      expect(sameTypeCtWithAll.primaryType, GrenadeType.smoke);
      expect(sameTypeCtWithAll.primaryTeam, TeamType.ct);
      expect(sameTypeCtWithAll.hasMultipleTypes, isFalse);

      final mixedCluster = GrenadeCluster(
        xRatio: 0.1,
        yRatio: 0.1,
        grenades: [ctSmoke, tFlash, allHe],
      );
      expect(mixedCluster.primaryType, GrenadeType.smoke);
      expect(mixedCluster.primaryTeam, TeamType.all);
      expect(mixedCluster.hasMultipleTypes, isTrue);
      expect(mixedCluster.hasFavorite, isTrue);
      expect(mixedCluster.hasNewImport, isTrue);

      final tOnlyCluster = GrenadeCluster(
        xRatio: 0.1,
        yRatio: 0.1,
        grenades: [tFlash],
      );
      expect(tOnlyCluster.primaryTeam, TeamType.t);
      expect(tOnlyCluster.hasFavorite, isTrue);
      expect(tOnlyCluster.hasNewImport, isFalse);

      final allOnlyCluster = GrenadeCluster(
        xRatio: 0.1,
        yRatio: 0.1,
        grenades: [allHe],
      );
      expect(allOnlyCluster.primaryTeam, TeamType.all);
      expect(allOnlyCluster.hasNewImport, isTrue);
    });
  });
}
