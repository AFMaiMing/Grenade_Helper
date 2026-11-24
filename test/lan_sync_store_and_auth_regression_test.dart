import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/cloud_package.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/services/cloud_package_service.dart';
import 'package:grenade_helper/services/lan_sync/lan_sync_auth.dart';
import 'package:grenade_helper/services/lan_sync/lan_sync_discovery_service.dart';
import 'package:grenade_helper/services/lan_sync/lan_sync_local_store.dart';
import 'package:grenade_helper/services/lan_sync/lan_sync_receive_controller.dart';
import 'package:grenade_helper/services/lan_sync/lan_sync_transfer_client.dart';
import 'package:grenade_helper/services/map_management_service.dart';
import 'package:grenade_helper/services/update_service.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _DirectHttpOverrides extends HttpOverrides {}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _initIsarCoreForTest();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LanSyncAuth 令牌与签名校验', () {
    test('generatePairCode 生成 6 位纯数字配对码', () {
      for (var i = 0; i < 20; i++) {
        final code = LanSyncAuth.generatePairCode();
        expect(code, matches(RegExp(r'^\d{6}$')));
      }
    });

    test('generateSecret 与 generateNonce 生成无填充 URL-safe 随机串', () {
      final s1 = LanSyncAuth.generateSecret(bytes: 24);
      final s2 = LanSyncAuth.generateSecret(bytes: 24);
      final nonce = LanSyncAuth.generateNonce(bytes: 12);

      expect(s1.length, 32);
      expect(s1.contains('='), isFalse);
      expect(s1, isNot(equals(s2)));
      expect(nonce.length, 16);
      expect(nonce.contains('='), isFalse);
    });

    test('sha256Hex 与 sha256FileHex 产出一致摘要', () async {
      final bytes = utf8.encode('abc');
      const expected =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      expect(LanSyncAuth.sha256Hex(bytes), expected);

      final tempDir = await Directory.systemTemp.createTemp('gh_lan_auth_sha_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File(p.join(tempDir.path, 'sample.bin'))
        ..writeAsBytesSync(bytes);
      expect(await LanSyncAuth.sha256FileHex(file.path), expected);
    });

    test('buildSigningPayload、hmacSha256Hex 与 constantTimeEquals 行为一致', () {
      final payload = LanSyncAuth.buildSigningPayload(
        method: 'post',
        path: '/v1/transfer/package',
        timestampMs: '1700000000000',
        nonce: 'nonce123',
        bodySha256: 'deadbeef',
        peerId: 'peer-1',
      );
      expect(
        payload,
        'POST\n/v1/transfer/package\n1700000000000\nnonce123\ndeadbeef\npeer-1',
      );

      final signA = LanSyncAuth.hmacSha256Hex(
        secret: 'secret-key',
        payload: payload,
      );
      final signB = LanSyncAuth.hmacSha256Hex(
        secret: 'secret-key',
        payload: payload,
      );
      final signWrongSecret = LanSyncAuth.hmacSha256Hex(
        secret: 'other-key',
        payload: payload,
      );

      expect(signA, hasLength(64));
      expect(LanSyncAuth.constantTimeEquals(signA, signB), isTrue);
      expect(
        LanSyncAuth.constantTimeEquals(signA, signWrongSecret),
        isFalse,
      );
      expect(LanSyncAuth.constantTimeEquals('abc', 'abcd'), isFalse);
      expect(LanSyncAuth.constantTimeEquals('abc', 'abd'), isFalse);
    });
  });

  group('LanSyncLocalStore 节点、历史与开关读写', () {
    test('loadOrCreateStableNodeId 首次生成并持久化稳定节点标识', () async {
      final store = LanSyncLocalStore();
      final first = await store.loadOrCreateStableNodeId();
      final second = await store.loadOrCreateStableNodeId();

      expect(first, startsWith('node_'));
      expect(second, first);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lan_sync_stable_node_id_v1'), first);
    });

    test('savePeers 与 loadPeers 过滤无效节点并按最近使用时间降序排列', () async {
      final store = LanSyncLocalStore();
      final t1 = DateTime(2026, 1, 1, 10);
      final t2 = DateTime(2026, 1, 2, 10);
      final t3 = DateTime(2026, 1, 3, 10);

      await store.savePeers([
        LanSyncPeerEntry(
          id: 'p1',
          name: 'Peer 1',
          host: '192.168.1.10',
          port: 39527,
          peerId: 'remote-1',
          sharedSecret: 'sec-1',
          isPaired: true,
          remoteDeviceName: 'Desk',
          createdAt: t1,
          updatedAt: t1,
          note: 'n1',
        ),
        LanSyncPeerEntry(
          id: '',
          name: 'Invalid Empty Id',
          host: '192.168.1.11',
          port: 39527,
          createdAt: t1,
          updatedAt: t1,
        ),
        LanSyncPeerEntry(
          id: 'p2',
          name: 'Peer 2',
          host: '192.168.1.12',
          port: 39528,
          createdAt: t1,
          updatedAt: t2,
          lastUsedAt: t3,
        ),
      ]);

      final peers = await store.loadPeers();
      expect(peers.map((e) => e.id).toList(), ['p2', 'p1']);
      expect(peers[1].isPaired, isTrue);
      expect(peers[1].sharedSecret, 'sec-1');
      expect(peers[1].remoteDeviceName, 'Desk');
      expect(peers[1].note, 'n1');
      expect(peers[0].lastUsedAt, t3);
    });

    test('appendHistory 按时间倒序保留上限 120 条并支持清空', () async {
      final store = LanSyncLocalStore();
      for (var i = 0; i < 125; i++) {
        await store.appendHistory(
          LanSyncHistoryEntry(
            id: 'h_$i',
            category: 'send',
            title: 'T$i',
            detail: 'D$i',
            success: i.isEven,
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }

      final loaded = await store.loadHistory();
      expect(loaded, hasLength(120));
      expect(loaded.first.id, 'h_124');
      expect(loaded.last.id, 'h_5');

      await store.clearHistory();
      expect(await store.loadHistory(), isEmpty);
    });

    test('静默导入开关默认关闭并支持持久化切换', () async {
      final store = LanSyncLocalStore();
      expect(await store.loadReceiveSilentImportEnabled(), isFalse);
      await store.saveReceiveSilentImportEnabled(true);
      expect(await store.loadReceiveSilentImportEnabled(), isTrue);
    });
  });

  group('LanSyncLocalStore 墓碑与基线读写清理', () {
    test('upsertGrenadeTombstones 与 loadGrenadeTombstones 支持过滤与过期裁剪', () async {
      final store = LanSyncLocalStore();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final expiredMs = DateTime.now()
          .subtract(const Duration(days: 91))
          .millisecondsSinceEpoch;

      await store.upsertGrenadeTombstones([
        LanSyncGrenadeTombstoneEntry(
          uniqueId: 'g-mirage-1',
          mapName: 'mirage',
          deletedAt: nowMs,
        ),
        LanSyncGrenadeTombstoneEntry(
          uniqueId: 'g-inferno-1',
          mapName: 'inferno',
          deletedAt: nowMs - 1000,
        ),
        LanSyncGrenadeTombstoneEntry(
          uniqueId: '',
          mapName: 'mirage',
          deletedAt: nowMs,
        ),
      ]);

      // 手动写入过期墓碑以验证读取时自动淘汰并写回存储
      final prefs = await SharedPreferences.getInstance();
      final rawMap = jsonDecode(
        prefs.getString('lan_sync_grenade_tombstones_v1')!,
      ) as Map<String, dynamic>;
      rawMap['g-expired'] = {
        'uniqueId': 'g-expired',
        'mapName': 'mirage',
        'deletedAt': expiredMs,
      };
      await prefs.setString(
        'lan_sync_grenade_tombstones_v1',
        jsonEncode(rawMap),
      );

      final mirageOnly = await store.loadGrenadeTombstones(
        mapKeys: const ['mirage'],
      );
      expect(mirageOnly.keys, ['g-mirage-1']);

      final persistedAfterPrune = jsonDecode(
        prefs.getString('lan_sync_grenade_tombstones_v1')!,
      ) as Map<String, dynamic>;
      expect(persistedAfterPrune.containsKey('g-expired'), isFalse);

      final byId = await store.loadGrenadeTombstones(
        uniqueIds: const ['g-inferno-1'],
      );
      expect(byId.keys, ['g-inferno-1']);
    });

    test('upsertEntityTombstones 与 loadEntityTombstones 校验类型并支持过滤', () async {
      final store = LanSyncLocalStore();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      await store.upsertEntityTombstones([
        LanSyncEntityTombstoneEntry(
          entityType: LanSyncEntityTombstoneType.tag,
          entityKey: 'tag-uuid-1',
          mapName: 'mirage',
          deletedAt: nowMs,
          payload: const {'tagName': 'A区'},
        ),
        LanSyncEntityTombstoneEntry(
          entityType: LanSyncEntityTombstoneType.area,
          entityKey: 'area-key-1',
          mapName: 'dust2',
          deletedAt: nowMs,
        ),
        LanSyncEntityTombstoneEntry(
          entityType: 'unknown_type',
          entityKey: 'bad-1',
          mapName: 'mirage',
          deletedAt: nowMs,
        ),
      ]);

      final tags = await store.loadEntityTombstones(
        entityTypes: const [LanSyncEntityTombstoneType.tag],
      );
      expect(tags, hasLength(1));
      final tagEntry = tags.values.single;
      expect(tagEntry.entityKey, 'tag-uuid-1');
      expect(tagEntry.payload['tagName'], 'A区');

      final stats = await store.loadTombstoneStats();
      expect(stats.grenadeCount, 0);
      expect(stats.entityCount, 2);

      await store.cleanupSyncTombstones();
      final afterCleanup = await store.loadTombstoneStats();
      expect(afterCleanup.entityCount, 2);
    });

    test('基线读写、调试汇总与旧同步状态清理行为一致', () async {
      final store = LanSyncLocalStore();
      await store.upsertAckedMapBaselines(
        peerNodeId: 'peer-a',
        mapKeys: const ['mirage', 'dust2'],
        baselineId: 'bl_001',
      );
      expect(
        await store.hasAckedMapBaselines(
          peerNodeId: 'peer-a',
          mapKeys: const ['mirage', 'dust2'],
        ),
        isTrue,
      );
      expect(
        await store.loadAckedMapBaselineIds(
          peerNodeId: 'peer-a',
          mapKeys: const ['mirage'],
        ),
        {'mirage': 'bl_001'},
      );

      await store.upsertMapBaselineSnapshots(
        peerNodeId: 'peer-a',
        mapDigests: const {
          'mirage': {'g1': 'd1', 'g2': 'd2'},
        },
        baselineId: 'bl_001',
      );
      final matched = await store.loadMapBaselineSnapshots(
        peerNodeId: 'peer-a',
        mapKeys: const ['mirage'],
        expectedBaselineIds: const {'mirage': 'bl_001'},
      );
      expect(matched['mirage'], {'g1': 'd1', 'g2': 'd2'});

      final mismatched = await store.loadMapBaselineSnapshots(
        peerNodeId: 'peer-a',
        mapKeys: const ['mirage'],
        expectedBaselineIds: const {'mirage': 'bl_other'},
      );
      expect(mismatched, isEmpty);

      final debugPeers = await store.loadBaselineDebugPeers();
      expect(debugPeers, hasLength(1));
      expect(debugPeers.first.peerNodeId, 'peer-a');
      expect(
        debugPeers.first.maps.map((e) => e.mapKey).toList(),
        ['dust2', 'mirage'],
      );
      expect(debugPeers.first.maps[0].snapshotCount, 0);
      expect(debugPeers.first.maps[1].snapshotCount, 2);

      await store.cleanupLegacySyncState();
      expect(await store.loadBaselineDebugPeers(), isEmpty);
    });
  });

  group('接收控制器、传输客户端与云包更新回归', () {
    test('LanSyncReceiveController 与 LanSyncTransferClient 门面协同闭环', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final tempDir =
            await Directory.systemTemp.createTemp('gh_lan_receive_test_');
        final isar = await _openTestIsar(tempDir, 'lan_receive_test');
        final controller = LanSyncReceiveController(
          isar: isar,
          stableNodeId: 'node_receiver_test',
        );
        addTearDown(() async {
          controller.dispose();
          await isar.close(deleteFromDisk: true);
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        await controller.start(preferredPort: 0);
        expect(controller.isRunning, isTrue);
        final port = controller.port!;

        final pairCode = controller.issuePairCode();
        final badPairResp = await LanSyncTransferClient.pairRequest(
          host: '127.0.0.1',
          port: port,
          pairCode: '000000' == pairCode ? '999999' : '000000',
          localPeerId: 'sender-peer-1',
          localDeviceName: 'SenderDevice',
        );
        expect(badPairResp.ok, isFalse);
        expect(badPairResp.statusCode, HttpStatus.unauthorized);

        final pairResp = await LanSyncTransferClient.pairRequest(
          host: '127.0.0.1',
          port: port,
          pairCode: pairCode,
          localPeerId: 'sender-peer-1',
          localDeviceName: 'SenderDevice',
        );
        expect(pairResp.ok, isTrue);
        expect(pairResp.peerId, 'sender-peer-1');
        expect(pairResp.sharedSecret, isNotEmpty);
        expect(pairResp.remoteDeviceId, 'node_receiver_test');
        expect(controller.trustedPeerCount, 1);

        final reqResp = await LanSyncTransferClient.requestTransfer(
          host: '127.0.0.1',
          port: port,
          fileName: 'mirage.cs2pkg',
          sizeBytes: 2048,
          senderName: 'SenderDevice',
          syncMode: 'delta',
          scopeType: 'maps',
          scopeMapKeys: const [' mirage ', ''],
        );
        expect(reqResp.ok, isTrue);
        expect(reqResp.status, LanIncomingTransferRequestStatus.pending.name);
        expect(reqResp.scopeMapKeys, ['mirage']);

        await controller.approveIncomingRequest(reqResp.requestId);
        final statusResp = await LanSyncTransferClient.getTransferRequestStatus(
          host: '127.0.0.1',
          port: port,
          requestId: reqResp.requestId,
        );
        expect(statusResp.ok, isTrue);
        expect(
          statusResp.status,
          LanIncomingTransferRequestStatus.approved.name,
        );
      }, _DirectHttpOverrides());
    });

    test('CloudPackageService、UpdateService、Discovery 与 MapManagement 纯逻辑稳定',
        () async {
      CloudPackageService.switchSource(true);
      expect(CloudPackageService.isUsingCDN, isTrue);
      expect(
          CloudPackageService.kIndexBaseUrl, CloudPackageService.kCDNIndexUrl);
      CloudPackageService.switchSource(false);
      expect(CloudPackageService.isUsingCDN, isFalse);

      expect(CloudPackageService.compareVersion('1.2.0', '1.1.9'), 1);
      expect(CloudPackageService.compareVersion('1.2', '1.2.0'), 0);
      expect(CloudPackageService.compareVersion('1.0.9', '1.1.0'), -1);

      await CloudPackageService.markPackageImported('pkg-1', '1.2.0');
      expect(await CloudPackageService.isPackageUpToDate('pkg-1', '1.2.0'),
          isTrue);
      expect(
        await CloudPackageService.isPackageUpToDate('pkg-1', '1.3.0'),
        isFalse,
      );

      const packages = [
        CloudPackage(
          id: '1',
          name: 'All',
          description: '',
          author: 'A',
          version: '1.0.0',
          updated: '',
          url: 'https://example.com/1',
        ),
        CloudPackage(
          id: '2',
          name: 'Mirage',
          description: '',
          author: 'A',
          map: 'mirage',
          version: '1.0.0',
          updated: '',
          url: 'https://example.com/2',
        ),
        CloudPackage(
          id: '3',
          name: 'Dust2',
          description: '',
          author: 'A',
          map: 'dust2',
          version: '1.0.0',
          updated: '',
          url: 'https://example.com/3',
        ),
      ];
      expect(
        CloudPackageService.getAvailableMaps(packages),
        ['dust2', 'mirage'],
      );
      expect(
        CloudPackageService.filterByMap(packages, 'mirage').map((e) => e.id),
        ['1', '2'],
      );

      final updateInfo = UpdateInfo.fromJson({
        'versionCode': 24,
        'versionName': '2.1.0',
        'content': 'Fix',
        'downloadUrl': 'https://example.com/app.exe',
        'forceUpdate': true,
      });
      expect(updateInfo.versionCode, 24);
      expect(updateInfo.forceUpdate, isTrue);
      expect(
        DownloadLinks.getOfficialUrl('windows'),
        'https://cdn.grenade-helper.top:8443/download/windows',
      );
      expect(DownloadLinks.panLinks.length, 3);

      const device = LanDiscoveryDevice(
        host: '192.168.1.5',
        port: 39527,
        nodeId: 'node_1',
        displayName: 'PC',
        requireAuthForUpload: true,
        trustedPeerCount: 2,
      );
      expect(device.deviceId, 'node_1');
      expect(device.deviceName, 'PC');
      expect(
        MapManagementService.isCustomMap(
          GameMap(name: 'Mirage', backgroundPath: 'assets/maps/mirage.svg'),
        ),
        isFalse,
      );
      expect(
        MapManagementService.isCustomMap(
          GameMap(name: 'Custom', backgroundPath: 'C:/custom/bg.png'),
        ),
        isTrue,
      );
    });
  });
}
