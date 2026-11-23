import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/cloud_package.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/overlay_snapshot.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/providers.dart';
import 'package:grenade_helper/services/settings_service.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

Future<void> _initIsarCoreForTest() async {
  final libraries = <Abi, String>{};
  final packageConfigFile = File(
    p.join(Directory.current.path, '.dart_tool', 'package_config.json'),
  );
  if (await packageConfigFile.exists()) {
    final decoded = jsonDecode(await packageConfigFile.readAsString());
    if (decoded is Map && decoded['packages'] is List) {
      for (final pkg in decoded['packages'] as List) {
        if (pkg is Map && pkg['name'] == 'isar_community_flutter_libs') {
          final rootUri = pkg['rootUri'] as String?;
          if (rootUri != null && rootUri.isNotEmpty) {
            final rootPath = Uri.parse(rootUri).toFilePath();
            final winDll = File(p.join(rootPath, 'windows', 'libisar.dll'));
            if (await winDll.exists()) {
              libraries[Abi.windowsX64] = winDll.path;
            }
          }
          break;
        }
      }
    }
  }
  await Isar.initializeIsarCore(libraries: libraries);
}

Future<Isar> _openTestIsar(Directory dir, String name) {
  return Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema,
      ImportHistorySchema,
      ImpactGroupSchema,
      FavoriteFolderSchema,
      TagSchema,
      GrenadeTagSchema,
      MapAreaSchema,
    ],
    directory: dir.path,
    name: name,
  );
}

/// 等待监听中的异步 Provider 产出满足条件的非加载态数据
Future<List<Grenade>> _waitForFilteredData(
  ProviderContainer container,
  int layerId,
  bool Function(List<Grenade>) predicate,
) async {
  final completer = Completer<List<Grenade>>();
  late final ProviderSubscription<AsyncValue<List<Grenade>>> sub;
  sub = container.listen<AsyncValue<List<Grenade>>>(
    filteredGrenadesProvider(layerId),
    (_, next) {
      next.whenData((list) {
        if (!completer.isCompleted && predicate(list)) {
          completer.complete(list);
        }
      });
    },
    fireImmediately: true,
  );
  try {
    return await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

void main() {
  setUpAll(() async {
    await _initIsarCoreForTest();
  });

  group('Providers baseline & intToThemeMode', () {
    test('intToThemeMode maps persisted integers consistently', () {
      expect(intToThemeMode(1), ThemeMode.light);
      expect(intToThemeMode(2), ThemeMode.dark);
      expect(intToThemeMode(0), ThemeMode.system);
      expect(intToThemeMode(-1), ThemeMode.system);
      expect(intToThemeMode(99), ThemeMode.system);
    });

    test('global providers expose expected initial values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), 2);
      expect(container.read(teamFilterProvider), TeamType.all);
      expect(container.read(onlyFavoritesProvider), isFalse);
      expect(
        container.read(typeFilterProvider),
        equals(<int>{
          GrenadeType.smoke,
          GrenadeType.flash,
          GrenadeType.molotov,
          GrenadeType.he,
          GrenadeType.wallbang,
        }),
      );
      expect(container.read(showSpawnPointsProvider), isFalse);
      expect(container.read(showCasualSpawnPointsProvider), isFalse);
      expect(container.read(showHostagePointsProvider), isFalse);
      expect(container.read(mapLineColorProvider), 0xFFE040FB);
      expect(container.read(mapLineOpacityProvider), 0.6);
      expect(container.read(impactAreaOpacityProvider), 0.4);
    });
  });

  group('TagDimension & model constants', () {
    test('constant values remain unchanged', () {
      expect(GrenadeType.smoke, 0);
      expect(GrenadeType.flash, 1);
      expect(GrenadeType.molotov, 2);
      expect(GrenadeType.he, 3);
      expect(GrenadeType.wallbang, 4);

      expect(TeamType.all, 0);
      expect(TeamType.ct, 1);
      expect(TeamType.t, 2);
      expect(TeamType.onlyAll, 3);

      expect(MediaType.image, 0);
      expect(MediaType.video, 1);

      expect(TagDimension.role, 0);
      expect(TagDimension.area, 1);
      expect(TagDimension.phase, 2);
      expect(TagDimension.spawn, 3);
      expect(TagDimension.purpose, 4);
      expect(TagDimension.custom, 99);
    });

    test('TagDimension custom names override and reset cleanly', () {
      final saved = TagDimension.getCustomNames();
      addTearDown(() => TagDimension.loadFromMap(saved));

      TagDimension.loadFromMap(const {});
      expect(TagDimension.getName(TagDimension.role), '角色');
      expect(TagDimension.getName(TagDimension.area), '区域');
      expect(TagDimension.getName(TagDimension.phase), '阶段');
      expect(TagDimension.getName(TagDimension.spawn), '身位');
      expect(TagDimension.getName(TagDimension.purpose), '目的');
      expect(TagDimension.getName(TagDimension.custom), '自定义');
      expect(TagDimension.getName(12345), '未知');

      TagDimension.setName(TagDimension.phase, '  进点时机  ');
      expect(TagDimension.getName(TagDimension.phase), '进点时机');

      final snapshot = TagDimension.getCustomNames();
      snapshot[TagDimension.area] = '不应污染内部状态';
      expect(TagDimension.getName(TagDimension.area), '区域');

      TagDimension.setName(TagDimension.phase, '   ');
      expect(TagDimension.getName(TagDimension.phase), '阶段');
    });
  });

  group('OverlaySnapshot serialization & Isar mapping', () {
    test('OverlayInitConfig round-trips through JSON cleanly', () {
      final config = OverlayInitConfig(
        x: 240.5,
        y: 120.25,
        sizeIndex: 2,
        opacity: 0.75,
        navSpeedLevel: 4,
        useLegacyIcons: true,
        hotkeys: {
          HotkeyAction.toggleOverlay: HotkeyConfig(
            key: LogicalKeyboardKey.keyG,
            modifiers: {LogicalKeyboardKey.alt},
          ),
          HotkeyAction.nextGrenade: HotkeyConfig(
            key: LogicalKeyboardKey.pageDown,
          ),
        },
        mapSnapshot: const OverlayMapSnapshot(
          mapId: 7,
          mapName: 'Mirage',
          layerId: 11,
          layerAssetPath: 'assets/maps/mirage.svg',
          grenades: [
            OverlayGrenadeItem(
              id: 101,
              title: 'VIP 烟',
              type: GrenadeType.smoke,
              xRatio: 0.42,
              yRatio: 0.63,
              steps: [
                OverlayStepItem(
                  stepIndex: 0,
                  title: '站位',
                  description: '贴紧垃圾桶',
                  medias: [
                    OverlayMediaItem(
                      localPath: 'media/step0.png',
                      type: MediaType.image,
                      sortOrder: 0,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final jsonMap = config.toJson();
      expect(
        jsonMap.keys,
        containsAll([
          'x',
          'y',
          'sizeIndex',
          'opacity',
          'navSpeedLevel',
          'useLegacyIcons',
          'hotkeys',
          'mapSnapshot',
        ]),
      );

      final encoded = jsonEncode(jsonMap);
      final decoded = OverlayInitConfig.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(decoded.x, 240.5);
      expect(decoded.y, 120.25);
      expect(decoded.sizeIndex, 2);
      expect(decoded.opacity, 0.75);
      expect(decoded.navSpeedLevel, 4);
      expect(decoded.useLegacyIcons, isTrue);
      expect(
        decoded.hotkeys[HotkeyAction.toggleOverlay]?.key,
        LogicalKeyboardKey.keyG,
      );
      expect(
        decoded.hotkeys[HotkeyAction.toggleOverlay]?.modifiers,
        contains(LogicalKeyboardKey.alt),
      );
      expect(
        decoded.hotkeys[HotkeyAction.nextGrenade]?.key,
        LogicalKeyboardKey.pageDown,
      );

      final snap = decoded.mapSnapshot!;
      expect(snap.mapId, 7);
      expect(snap.mapName, 'Mirage');
      expect(snap.layerId, 11);
      expect(snap.layerAssetPath, 'assets/maps/mirage.svg');
      expect(snap.grenades, hasLength(1));
      expect(snap.grenades.first.id, 101);
      expect(snap.grenades.first.title, 'VIP 烟');
      expect(snap.grenades.first.type, GrenadeType.smoke);
      expect(snap.grenades.first.xRatio, 0.42);
      expect(snap.grenades.first.yRatio, 0.63);
      expect(snap.grenades.first.steps.first.description, '贴紧垃圾桶');
      expect(
        snap.grenades.first.steps.first.medias.first.localPath,
        'media/step0.png',
      );
    });

    test('Overlay snapshot classes preserve JSON fallback defaults', () {
      final emptyConfig = OverlayInitConfig.fromJson(const {});
      expect(emptyConfig.x, 100.0);
      expect(emptyConfig.y, 100.0);
      expect(emptyConfig.sizeIndex, 1);
      expect(emptyConfig.opacity, 0.9);
      expect(emptyConfig.navSpeedLevel, 3);
      expect(emptyConfig.useLegacyIcons, isFalse);
      expect(emptyConfig.hotkeys, isEmpty);
      expect(emptyConfig.mapSnapshot, isNull);
      expect(OverlayInitConfig.decodeHotkeys(null), isEmpty);

      final minimalSnap =
          OverlayMapSnapshot.fromJson({'mapId': 1, 'layerId': 2});
      expect(minimalSnap.mapName, '');
      expect(minimalSnap.layerAssetPath, '');
      expect(minimalSnap.grenades, isEmpty);

      final minimalGrenade = OverlayGrenadeItem.fromJson({
        'id': 3,
        'xRatio': 0.1,
        'yRatio': 0.2,
      });
      expect(minimalGrenade.title, '');
      expect(minimalGrenade.type, GrenadeType.smoke);
      expect(minimalGrenade.steps, isEmpty);

      final minimalStep = OverlayStepItem.fromJson(const {});
      expect(minimalStep.stepIndex, 0);
      expect(minimalStep.title, '');
      expect(minimalStep.description, '');
      expect(minimalStep.medias, isEmpty);

      final minimalMedia = OverlayMediaItem.fromJson(const {});
      expect(minimalMedia.localPath, '');
      expect(minimalMedia.type, MediaType.image);
      expect(minimalMedia.sortOrder, 0);
    });

    test('OverlayMapSnapshot.fromIsar sorts steps and medias and locks lists',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('gh_overlay_isar_');
      final isar = await _openTestIsar(tempDir, 'overlay_snapshot_test');
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final map = GameMap(name: 'Inferno');
      final layer = MapLayer(
        name: 'Default',
        assetPath: 'assets/maps/inferno.svg',
        sortOrder: 0,
      );
      final grenade = Grenade(
        title: '棺材烟',
        type: GrenadeType.smoke,
        xRatio: 0.3,
        yRatio: 0.4,
      );
      final step2 = GrenadeStep(title: 'S2', description: '出手', stepIndex: 1);
      final step0 = GrenadeStep(title: 'S0', description: '站位', stepIndex: 0);
      final media1 = StepMedia(
        localPath: 'b.mp4',
        type: MediaType.video,
        sortOrder: 1,
      );
      final media0 = StepMedia(
        localPath: 'a.png',
        type: MediaType.image,
        sortOrder: 0,
      );

      await isar.writeTxn(() async {
        await isar.gameMaps.put(map);
        await isar.mapLayers.put(layer);
        map.layers.add(layer);
        await map.layers.save();

        await isar.grenades.put(grenade);
        grenade.layer.value = layer;
        await grenade.layer.save();

        await isar.grenadeSteps.putAll([step2, step0]);
        grenade.steps.addAll([step2, step0]);
        await grenade.steps.save();

        await isar.stepMedias.putAll([media1, media0]);
        step0.medias.addAll([media1, media0]);
        await step0.medias.save();
      });

      final snapshot = OverlayMapSnapshot.fromIsar(map, layer);
      expect(snapshot.mapId, map.id);
      expect(snapshot.layerId, layer.id);
      expect(snapshot.grenades, hasLength(1));

      final snapGrenade = snapshot.grenades.first;
      expect(snapGrenade.steps.map((s) => s.stepIndex).toList(), [0, 1]);
      expect(
        snapGrenade.steps.first.medias.map((m) => m.localPath).toList(),
        ['a.png', 'b.mp4'],
      );
      expect(
        () => (snapshot.grenades as List).clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('CloudPackage & CloudPackageIndex', () {
    test(
        'CloudPackage parses defaults, serializes conditionally, and picks URL',
        () {
      final minimal = CloudPackage.fromJson({
        'id': 'pkg-1',
        'name': 'Mirage Basics',
        'url': 'https://r2.example.com/mirage.cs2pkg',
      });
      expect(minimal.description, '');
      expect(minimal.author, '未知');
      expect(minimal.map, isNull);
      expect(minimal.version, '1.0.0');
      expect(minimal.updated, '');
      expect(minimal.cdnUrl, isNull);
      expect(
          minimal.getDownloadUrl(true), 'https://r2.example.com/mirage.cs2pkg');
      expect(minimal.toJson().containsKey('cdnUrl'), isFalse);

      const withEmptyCdn = CloudPackage(
        id: 'pkg-2',
        name: 'Dust2',
        description: 'Desc',
        author: 'Tester',
        map: 'dust2',
        version: '2.1.0',
        updated: '2026-01-01',
        url: 'https://main.example.com/d2.cs2pkg',
        cdnUrl: '',
      );
      expect(
        withEmptyCdn.getDownloadUrl(true),
        'https://main.example.com/d2.cs2pkg',
      );

      const withCdn = CloudPackage(
        id: 'pkg-3',
        name: 'Anubis',
        description: 'Desc',
        author: 'Author',
        version: '1.2.0',
        updated: '2026-02-01',
        url: 'https://main.example.com/anubis.cs2pkg',
        cdnUrl: 'https://cdn.example.com/anubis.cs2pkg',
      );
      expect(
        withCdn.getDownloadUrl(true),
        'https://cdn.example.com/anubis.cs2pkg',
      );
      expect(
        withCdn.getDownloadUrl(false),
        'https://main.example.com/anubis.cs2pkg',
      );

      final json = withCdn.toJson();
      expect(json['cdnUrl'], 'https://cdn.example.com/anubis.cs2pkg');
      final roundTrip = CloudPackage.fromJson(json);
      expect(roundTrip.id, withCdn.id);
      expect(roundTrip.version, '1.2.0');
      expect(roundTrip.cdnUrl, withCdn.cdnUrl);
    });

    test('CloudPackageIndex parses full and empty payloads', () {
      final emptyIndex = CloudPackageIndex.fromJson(const {});
      expect(emptyIndex.version, 1);
      expect(emptyIndex.updated, isNull);
      expect(emptyIndex.sources, isEmpty);
      expect(emptyIndex.packages, isEmpty);

      final index = CloudPackageIndex.fromJson({
        'version': 2,
        'updated': '2026-03-01',
        'sources': ['contrib/a.json'],
        'packages': [
          {
            'id': 'p1',
            'name': 'Pkg 1',
            'url': 'https://example.com/p1.cs2pkg',
            'map': 'ancient',
          },
        ],
      });
      expect(index.version, 2);
      expect(index.updated, '2026-03-01');
      expect(index.sources, ['contrib/a.json']);
      expect(index.packages, hasLength(1));
      expect(index.packages.first.map, 'ancient');
      expect(() => (index.packages as List).clear(), throwsUnsupportedError);
    });
  });

  group('filteredGrenadesProvider', () {
    test('filters grenades by layer, type, team, and favorite reactively',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('gh_provider_filter_');
      final isar = await _openTestIsar(tempDir, 'provider_filter_test');
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final layer1 = MapLayer(name: 'L1', assetPath: '', sortOrder: 0);
      final layer2 = MapLayer(name: 'L2', assetPath: '', sortOrder: 1);

      final gSmokeAllFav = Grenade(
        title: 'Smoke All Fav',
        type: GrenadeType.smoke,
        team: TeamType.all,
        isFavorite: true,
        xRatio: 0.1,
        yRatio: 0.1,
      );
      final gFlashCt = Grenade(
        title: 'Flash CT',
        type: GrenadeType.flash,
        team: TeamType.ct,
        isFavorite: false,
        xRatio: 0.2,
        yRatio: 0.2,
      );
      final gWallbangTFav = Grenade(
        title: 'Wallbang T Fav',
        type: GrenadeType.wallbang,
        team: TeamType.t,
        isFavorite: true,
        xRatio: 0.3,
        yRatio: 0.3,
      );
      final gOtherLayer = Grenade(
        title: 'Other Layer',
        type: GrenadeType.smoke,
        team: TeamType.all,
        isFavorite: true,
        xRatio: 0.4,
        yRatio: 0.4,
      );

      await isar.writeTxn(() async {
        await isar.mapLayers.putAll([layer1, layer2]);
        await isar.grenades
            .putAll([gSmokeAllFav, gFlashCt, gWallbangTFav, gOtherLayer]);

        gSmokeAllFav.layer.value = layer1;
        gFlashCt.layer.value = layer1;
        gWallbangTFav.layer.value = layer1;
        gOtherLayer.layer.value = layer2;

        await gSmokeAllFav.layer.save();
        await gFlashCt.layer.save();
        await gWallbangTFav.layer.save();
        await gOtherLayer.layer.save();
      });

      final container = ProviderContainer(
        overrides: [isarProvider.overrideWithValue(isar)],
      );
      addTearDown(container.dispose);

      // 保持 autoDispose Provider 订阅以接收异步更新
      final keepAliveSub = container.listen(
        filteredGrenadesProvider(layer1.id),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(keepAliveSub.close);

      final initial = await _waitForFilteredData(
        container,
        layer1.id,
        (list) => list.length == 3,
      );
      expect(
        initial.map((g) => g.title),
        unorderedEquals(['Smoke All Fav', 'Flash CT', 'Wallbang T Fav']),
      );

      container.read(typeFilterProvider.notifier).state = {
        GrenadeType.smoke,
        GrenadeType.wallbang,
      };
      expect(
        container
            .read(filteredGrenadesProvider(layer1.id))
            .requireValue
            .map((g) => g.title),
        unorderedEquals(['Smoke All Fav', 'Wallbang T Fav']),
      );

      container.read(teamFilterProvider.notifier).state = TeamType.onlyAll;
      expect(
        container
            .read(filteredGrenadesProvider(layer1.id))
            .requireValue
            .map((g) => g.title),
        ['Smoke All Fav'],
      );

      container.read(typeFilterProvider.notifier).state = {
        GrenadeType.smoke,
        GrenadeType.flash,
        GrenadeType.molotov,
        GrenadeType.he,
        GrenadeType.wallbang,
      };
      container.read(teamFilterProvider.notifier).state = TeamType.ct;
      expect(
        container
            .read(filteredGrenadesProvider(layer1.id))
            .requireValue
            .map((g) => g.title),
        ['Flash CT'],
      );

      container.read(teamFilterProvider.notifier).state = TeamType.t;
      expect(
        container
            .read(filteredGrenadesProvider(layer1.id))
            .requireValue
            .map((g) => g.title),
        ['Wallbang T Fav'],
      );

      container.read(teamFilterProvider.notifier).state = TeamType.all;
      container.read(onlyFavoritesProvider.notifier).state = true;
      expect(
        container
            .read(filteredGrenadesProvider(layer1.id))
            .requireValue
            .map((g) => g.title),
        unorderedEquals(['Smoke All Fav', 'Wallbang T Fav']),
      );

      final gMolotovAllFav = Grenade(
        title: 'Molotov All Fav',
        type: GrenadeType.molotov,
        team: TeamType.all,
        isFavorite: true,
        xRatio: 0.5,
        yRatio: 0.5,
      );
      await isar.writeTxn(() async {
        await isar.grenades.put(gMolotovAllFav);
        gMolotovAllFav.layer.value = layer1;
        await gMolotovAllFav.layer.save();
      });

      final updated = await _waitForFilteredData(
        container,
        layer1.id,
        (list) => list.any((g) => g.title == 'Molotov All Fav'),
      );
      expect(
        updated.map((g) => g.title),
        unorderedEquals(['Smoke All Fav', 'Wallbang T Fav', 'Molotov All Fav']),
      );
    });
  });
}
