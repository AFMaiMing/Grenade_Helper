import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/data/builtin_area_region_presets.dart';
import 'package:grenade_helper/data/builtin_maps.dart';
import 'package:grenade_helper/data/map_area_presets.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/spawn_point_data.dart';
import 'package:grenade_helper/theme/app_design_system.dart';

void main() {
  group('builtinMapsConfig 与地图匹配回归校验', () {
    test('内置地图列表顺序、图池分类与楼层配置保持一致', () {
      expect(
        builtinMapsConfig.map((config) => config.key).toList(),
        const [
          'mirage',
          'inferno',
          'dust2',
          'cache',
          'ancient',
          'anubis',
          'nuke',
          'overpass',
          'train',
          'vertigo',
          'cbble',
          'office',
          'italy',
        ],
      );
      expect(builtinMapsConfig.where((c) => c.isActiveDuty).length, 7);
      expect(builtinMapsConfig.where((c) => !c.isActiveDuty).length, 6);

      for (final config in builtinMapsConfig) {
        expect(config.floors, isNotEmpty);
        expect(config.floorNames.length, config.floors.length);
        expect(
            config.backgroundPath, 'assets/backgrounds/${config.key}_bg.webp');
        expect(
          config.legacyBackgroundPath,
          'assets/backgrounds/${config.key}_bg.png',
        );
        expect(config.iconPath, 'assets/icons/${config.key}_icon.svg');
      }

      final multiFloorKeys = builtinMapsConfig
          .where((c) => c.floors.length > 1)
          .map((c) => c.key)
          .toList();
      expect(multiFloorKeys, const ['nuke', 'vertigo']);
    });

    test('findBuiltinMapConfig、sortOrder 与旧路径归一化行为正确', () {
      final dust2ByIcon = GameMap(
        name: 'Dust II Custom',
        iconPath: r'assets\icons\DUST2_icon.SVG',
      );
      final nukeByLegacyBg = GameMap(
        name: 'Nuke',
        backgroundPath: r'ASSETS\BACKGROUNDS\nuke_bg.PNG',
      );
      final customMap = GameMap(
        name: 'Workshop Map',
        iconPath: 'custom/icon.svg',
        backgroundPath: 'custom/bg.png',
      );

      expect(findBuiltinMapConfig(dust2ByIcon)?.key, 'dust2');
      expect(findBuiltinMapConfig(nukeByLegacyBg)?.key, 'nuke');
      expect(findBuiltinMapConfig(customMap), isNull);

      expect(builtinMapSortOrder(dust2ByIcon), 2);
      expect(builtinMapSortOrder(nukeByLegacyBg), 6);
      expect(builtinMapSortOrder(customMap), builtinMapsConfig.length);

      expect(
        normalizeLegacyBuiltinAssetPath(
          r'  ASSETS\BACKGROUNDS\mirage_bg.PNG  ',
        ),
        'assets/backgrounds/mirage_bg.webp',
      );
      expect(
        normalizeLegacyBuiltinAssetPath('assets/backgrounds/mirage_bg.webp'),
        'assets/backgrounds/mirage_bg.webp',
      );
      expect(
        normalizeLegacyBuiltinAssetPath('custom/maps/my_map.png'),
        'custom/maps/my_map.png',
      );
      expect(normalizeLegacyBuiltinAssetPath('   '), '');
    });
  });

  group('区域标签与默认区域几何预设回归校验', () {
    test('mapAreaPresets、commonSystemTags 与 dimensionColors 条目完整', () {
      const expectedCounts = <String, int>{
        'dust2': 25,
        'cache': 43,
        'mirage': 22,
        'inferno': 37,
        'nuke': 19,
        'overpass': 15,
        'vertigo': 11,
        'ancient': 17,
        'anubis': 15,
        'train': 36,
      };

      expect(mapAreaPresets.keys.toSet(), expectedCounts.keys.toSet());
      for (final entry in expectedCounts.entries) {
        final names = mapAreaPresets[entry.key]!;
        expect(names.length, entry.value, reason: 'map=${entry.key}');
        expect(names.every((n) => n.trim().isNotEmpty), isTrue);
      }

      expect(commonSystemTags.keys, const [
        TagDimension.role,
        TagDimension.phase,
        TagDimension.spawn,
        TagDimension.purpose,
      ]);
      for (final list in commonSystemTags.values) {
        expect(list, isNotEmpty);
        expect(list.every((tag) => tag.trim().isNotEmpty), isTrue);
      }

      expect(dimensionColors.keys.toSet(), const {
        TagDimension.role,
        TagDimension.area,
        TagDimension.phase,
        TagDimension.spawn,
        TagDimension.purpose,
        TagDimension.custom,
      });
      for (final color in dimensionColors.values) {
        expect(color, isNonZero);
      }
    });

    test('builtinAreaRegionPresets 每图条目数、楼层归属与描边 JSON 合法', () {
      const expectedRegionCounts = <String, int>{
        'mirage': 22,
        'inferno': 36,
        'dust2': 24,
        'overpass': 15,
        'ancient': 17,
        'anubis': 15,
        'train': 36,
        'nuke': 19,
        'cache': 43,
        'vertigo': 11,
      };

      expect(
        builtinAreaRegionPresets.keys.toList(),
        expectedRegionCounts.keys.toList(),
      );

      final configByKey = {
        for (final config in builtinMapsConfig) config.key: config,
      };

      for (final entry in expectedRegionCounts.entries) {
        final mapKey = entry.key;
        final floorMap = builtinAreaRegionPresets[mapKey]!;
        expect(floorMap.keys, const ['_merged']);

        final presets = floorMap['_merged']!;
        expect(presets.length, entry.value, reason: 'map=$mapKey');

        final allowedFloors = configByKey[mapKey]!.floors.toSet();
        final presetNames = presets.map((p) => p.name).toSet();
        final configuredNames = mapAreaPresets[mapKey]!.toSet();
        expect(presetNames, configuredNames, reason: 'map=$mapKey');

        for (final preset in presets) {
          expect(preset.name.trim(), isNotEmpty);
          expect(preset.colorValue, isNonZero);

          if (preset.floorStrokesJson != null) {
            final decoded = jsonDecode(preset.floorStrokesJson!);
            expect(decoded, isA<Map<String, dynamic>>());
            final floorStrokes = decoded as Map<String, dynamic>;
            expect(floorStrokes, isNotEmpty);
            for (final floorEntry in floorStrokes.entries) {
              expect(allowedFloors.contains(floorEntry.key), isTrue);
              final strokes = floorEntry.value as List<dynamic>;
              expect(strokes, isNotEmpty);
              expect((strokes.first as Map<String, dynamic>)['q'], isList);
            }
          } else {
            expect(allowedFloors.contains(preset.floorKey), isTrue);
            final decoded = jsonDecode(preset.strokesJson!);
            expect(decoded, isA<List<dynamic>>());
            final strokes = decoded as List<dynamic>;
            expect(strokes, isNotEmpty);
            expect((strokes.first as Map<String, dynamic>)['q'], isList);
          }
        }
      }

      final nukeMultiFloor = builtinAreaRegionPresets['nuke']!['_merged']!
          .where((p) => p.floorStrokesJson != null)
          .map((p) => p.name)
          .toList();
      expect(nukeMultiFloor, const ['管道', '铁板', 'K1']);

      final vertigoMultiFloor = builtinAreaRegionPresets['vertigo']!['_merged']!
          .where((p) => p.floorStrokesJson != null)
          .map((p) => p.name)
          .toList();
      expect(vertigoMultiFloor, const ['A斜坡', 'B楼梯']);
    });
  });

  group('spawnPointData 出生点与人质点回归校验', () {
    test('全地图点位数量、休闲与人质标记及坐标范围完整一致', () {
      const expectedCounts = <String,
          ({
        int ct,
        int t,
        int casualCt,
        int casualT,
        int hostage,
      })>{
        'mirage': (ct: 5, t: 10, casualCt: 11, casualT: 7, hostage: 0),
        'inferno': (ct: 6, t: 5, casualCt: 10, casualT: 11, hostage: 0),
        'dust 2': (ct: 5, t: 15, casualCt: 10, casualT: 0, hostage: 0),
        'cache': (ct: 5, t: 10, casualCt: 11, casualT: 6, hostage: 0),
        'ancient': (ct: 5, t: 5, casualCt: 7, casualT: 7, hostage: 0),
        'anubis': (ct: 5, t: 11, casualCt: 11, casualT: 5, hostage: 0),
        'nuke': (ct: 5, t: 8, casualCt: 11, casualT: 8, hostage: 0),
        'overpass': (ct: 5, t: 11, casualCt: 11, casualT: 9, hostage: 0),
        'train': (ct: 8, t: 6, casualCt: 6, casualT: 8, hostage: 0),
        'vertigo': (ct: 5, t: 5, casualCt: 10, casualT: 10, hostage: 0),
        'cobblestone': (ct: 5, t: 5, casualCt: 11, casualT: 11, hostage: 0),
        'office': (ct: 15, t: 5, casualCt: 0, casualT: 10, hostage: 9),
        'italy': (ct: 15, t: 5, casualCt: 0, casualT: 10, hostage: 6),
      };

      expect(spawnPointData.keys.toList(), expectedCounts.keys.toList());

      for (final entry in expectedCounts.entries) {
        final mapKey = entry.key;
        final counts = entry.value;
        final config = spawnPointData[mapKey]!;

        expect(config.ctSpawns.length, counts.ct, reason: mapKey);
        expect(config.tSpawns.length, counts.t, reason: mapKey);
        expect(config.casualCtSpawns.length, counts.casualCt, reason: mapKey);
        expect(config.casualTSpawns.length, counts.casualT, reason: mapKey);
        expect(config.hostageSpawns.length, counts.hostage, reason: mapKey);
        expect(
          config.hasCasualSpawns,
          counts.casualCt > 0 || counts.casualT > 0,
        );
        expect(config.hasHostageSpawns, counts.hostage > 0);

        final allPoints = [
          ...config.ctSpawns,
          ...config.tSpawns,
          ...config.casualCtSpawns,
          ...config.casualTSpawns,
          ...config.hostageSpawns,
        ];
        for (final point in allPoints) {
          expect(point.id, greaterThan(0));
          expect(point.x, inInclusiveRange(0.0, 1.0));
          expect(point.y, inInclusiveRange(0.0, 1.0));
        }

        final baseSpacing = config.minSpacingRatio();
        final casualSpacing = config.minSpacingRatio(includeCasual: true);
        expect(baseSpacing, greaterThan(0.002));
        expect(baseSpacing, lessThanOrEqualTo(0.05));
        expect(casualSpacing, lessThanOrEqualTo(baseSpacing));
        expect(config.minSpacingRatio(), baseSpacing);
        expect(config.minSpacingRatio(includeCasual: true), casualSpacing);
      }

      for (final builtin in builtinMapsConfig) {
        expect(
          spawnPointData.containsKey(builtin.name.toLowerCase()),
          isTrue,
          reason: builtin.name,
        );
      }
    });

    test('MapSpawnConfig.minSpacingRatio 精确过滤重合点并按欧氏距离计算', () {
      const sample = MapSpawnConfig(
        ctSpawns: [
          SpawnPoint(1, 0.10, 0.10),
          SpawnPoint(2, 0.1005, 0.10),
          SpawnPoint(3, 0.10, 0.13),
        ],
        tSpawns: [
          SpawnPoint(1, 0.80, 0.80),
        ],
        casualCtSpawns: [
          SpawnPoint(4, 0.10, 0.09),
        ],
      );

      expect(sample.minSpacingRatio(), closeTo(0.03, 1e-9));
      expect(
        sample.minSpacingRatio(includeCasual: true),
        closeTo(0.01, 1e-9),
      );
    });
  });

  group('AppDesignSystem 设计系统回归校验', () {
    test('AppThemeExtension copyWith、lerp 与断点动效常量保持一致', () {
      const light = AppThemeExtension.light;
      const dark = AppThemeExtension.dark;

      expect(light.smoke, const Color(0xFF64727D));
      expect(light.flash, const Color(0xFFC39A00));
      expect(light.molotov, const Color(0xFFC53A2D));
      expect(light.he, const Color(0xFF258A49));
      expect(light.wallbang, const Color(0xFF007D91));

      expect(light.lerp(null, 0.5), same(light));
      expect(light.lerp(dark, 0.0).canvas, light.canvas);
      expect(light.lerp(dark, 1.0).canvas, dark.canvas);
      expect(
        light.copyWith(canvas: const Color(0xFF123456)).canvas,
        const Color(0xFF123456),
      );

      expect(AppBreakpoints.mobile, 720);
      expect(AppBreakpoints.expandedNavigation, 1280);
      expect(AppBreakpoints.mobileBottomBarHeight, 70);
      expect(AppBreakpoints.mobileBottomBarMinimumSafeArea, 10);
      expect(AppMotion.quick, const Duration(milliseconds: 150));
      expect(AppMotion.content, const Duration(milliseconds: 220));
      expect(AppMotion.panel, const Duration(milliseconds: 300));
    });
  });
}
