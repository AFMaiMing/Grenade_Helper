import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import '../services/lan_sync/lan_sync_discovery_service.dart';
import '../services/lan_sync/lan_sync_local_store.dart';
import '../services/lan_sync/lan_sync_receive_controller.dart';
import '../services/lan_sync/lan_sync_transfer_client.dart';
import 'import_preview_screen.dart';
import 'lan_sync/lan_sync_conflict_dialogs.dart';
import 'lan_sync/lan_sync_grenade_picker_screen.dart';
import 'lan_sync/lan_sync_receive_sections.dart';
import 'lan_sync/lan_sync_send_sections.dart';
import 'lan_sync/lan_sync_shared.dart';

typedef _IncrementalSyncPayload = ({
  List<Map<String, dynamic>> grenadePayloads,
  List<Map<String, dynamic>> tagPayloads,
  List<Map<String, dynamic>> areaPayloads,
  List<Map<String, dynamic>> mapPayloads,
  List<Map<String, dynamic>> favoriteFolderPayloads,
  List<Map<String, dynamic>> impactGroupPayloads,
  Set<String> filesToZip,
  List<PackageGrenadeTombstoneData> grenadeTombstones,
  List<PackageEntityTombstoneData> entityTombstones,
});

/// 局域网点位同步与设备互传主页面
class LanSyncScreen extends ConsumerStatefulWidget {
  const LanSyncScreen({super.key});

  @override
  ConsumerState<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends ConsumerState<LanSyncScreen> {
  late final LanSyncReceiveController _receiveController;
  late final LanSyncDiscoveryService _discoveryService;
  late final LanSyncLocalStore _localStore;
  late final TextEditingController _targetHostController;
  late final TextEditingController _targetPortController;
  bool _isLoadingLocal = true;
  bool _isScanningDevices = false;
  bool _isSendingAll = false;
  bool _isWaitingForApproval = false;
  double? _sendProgress;
  String _sendProgressLabel = '';
  LanSyncMode _sendMode = LanSyncMode.full;
  LanSendScope _sendScope = LanSendScope.all;
  GameMap? _selectedMapForSend;
  List<Grenade> _selectedGrenadesForSend = const [];
  List<LanDiscoveryDevice> _discoveredDevices = const [];
  final Set<String> _seenReceivedTaskIds = <String>{};
  final Set<String> _handledIncomingRequestDialogs = <String>{};
  final Set<String> _handledImportTaskIds = <String>{};
  bool _isAutoOpeningImportPreview = false;
  bool _isLoadingSyncDebug = false;
  bool _silentImportEnabled = false;

  @override
  void initState() {
    super.initState();
    _receiveController = LanSyncReceiveController(isar: ref.read(isarProvider));
    _receiveController.setLocalDeviceName(_buildEphemeralDeviceName());
    _receiveController.addListener(_onReceiveControllerChanged);
    _discoveryService = LanSyncDiscoveryService();
    _localStore = LanSyncLocalStore();
    _targetHostController = TextEditingController();
    _targetPortController = TextEditingController(text: '39527');
    unawaited(_receiveController.refreshLocalIps());
    unawaited(_loadLocalState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scanDevices());
    });
  }

  @override
  void dispose() {
    _receiveController.removeListener(_onReceiveControllerChanged);
    _targetHostController.dispose();
    _targetPortController.dispose();
    _receiveController.dispose();
    super.dispose();
  }

  void _onReceiveControllerChanged() {
    for (final task in _receiveController.tasks) {
      if (_seenReceivedTaskIds.add(task.id)) {
        unawaited(
          _appendHistory(
            category: 'receive',
            title: '收到同步包',
            detail:
                '${task.fileName} · ${formatLanBytes(task.sizeBytes)}${task.remoteAddress == null ? '' : ' · ${task.remoteAddress}'}',
            success: true,
          ),
        );
      }
    }
    for (final req in _receiveController.incomingRequests) {
      if (req.status == LanIncomingTransferRequestStatus.pending &&
          _handledIncomingRequestDialogs.add(req.id)) {
        unawaited(_showIncomingTransferApprovalDialog(req.id));
      }
    }
    if (!mounted) return;
    setState(() {});
    _maybeOpenImportPreviewDirectly();
  }

  void _maybeOpenImportPreviewDirectly() {
    if (!mounted || _isAutoOpeningImportPreview) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    LanReceivedPackageTask? task;
    for (final item in _receiveController.tasks) {
      if (item.status != LanReceiveTaskStatus.pending) continue;
      if (_handledImportTaskIds.contains(item.id)) continue;
      task = item;
      break;
    }
    if (task == null) return;

    _handledImportTaskIds.add(task.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isAutoOpeningImportPreview) return;
      final currentRoute = ModalRoute.of(context);
      if (currentRoute != null && !currentRoute.isCurrent) return;

      _isAutoOpeningImportPreview = true;
      unawaited(() async {
        try {
          if (_silentImportEnabled) {
            await _importTaskSilently(task!);
          } else {
            await _openImportPreview(task!);
          }
        } finally {
          _isAutoOpeningImportPreview = false;
          if (mounted) {
            _maybeOpenImportPreviewDirectly();
          }
        }
      }());
    });
  }

  Future<void> _showIncomingTransferApprovalDialog(String requestId) async {
    if (!mounted) return;
    final req = _receiveController.incomingRequests
        .where((e) => e.id == requestId)
        .cast<LanIncomingTransferRequest?>()
        .firstWhere((e) => e != null, orElse: () => null);
    if (req == null || req.status != LanIncomingTransferRequestStatus.pending) {
      return;
    }

    final accepted = await showLanIncomingTransferApprovalDialog(context, req);
    if (accepted == true) {
      await _receiveController.approveIncomingRequest(requestId);
      await _appendHistory(
        category: 'system',
        title: '同意传输请求',
        detail: '${req.fileName} · ${formatLanBytes(req.sizeBytes)}',
        success: true,
      );
    } else {
      await _receiveController.rejectIncomingRequest(
        requestId,
        message: '接收方拒绝',
      );
      await _appendHistory(
        category: 'system',
        title: '拒绝传输请求',
        detail: req.fileName,
        success: true,
      );
    }
  }

  Future<void> _loadLocalState() async {
    await _localStore.cleanupLegacySyncState();
    final nodeId = await _localStore.loadOrCreateStableNodeId();
    final silentImportEnabled =
        await _localStore.loadReceiveSilentImportEnabled();
    _receiveController.setLocalNodeId(nodeId);
    await _refreshSyncDebugInfo();
    if (!mounted) return;
    setState(() {
      _silentImportEnabled = silentImportEnabled;
      _isLoadingLocal = false;
    });
  }

  Future<void> _refreshSyncDebugInfo() async {
    if (_isLoadingSyncDebug) return;
    _isLoadingSyncDebug = true;
    try {
      await _localStore.cleanupSyncTombstones();
      await _localStore.loadTombstoneStats();
      if (!mounted) return;
      setState(() {});
    } finally {
      _isLoadingSyncDebug = false;
    }
  }

  Future<void> _appendHistory({
    required String category,
    required String title,
    required String detail,
    required bool success,
  }) async {
    final entry = LanSyncHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      category: category,
      title: title,
      detail: detail,
      success: success,
      createdAt: DateTime.now(),
    );
    await _localStore.appendHistory(entry);
  }

  Future<void> _setSilentImportEnabled(bool enabled) async {
    if (_silentImportEnabled == enabled) return;
    setState(() {
      _silentImportEnabled = enabled;
    });
    await _localStore.saveReceiveSilentImportEnabled(enabled);
    await _appendHistory(
      category: 'system',
      title: enabled ? '已开启静默导入' : '已关闭静默导入',
      detail: enabled ? '接收后自动后台导入' : '接收后打开导入预览',
      success: true,
    );
    if (enabled) {
      _maybeOpenImportPreviewDirectly();
    }
  }

  Future<void> _scanDevices() async {
    await _scanDevicesBySubnet();
  }

  Future<void> _scanDevicesBySubnet() async {
    if (_isScanningDevices) return;
    setState(() => _isScanningDevices = true);
    try {
      if (_receiveController.localIps.isEmpty) {
        await _receiveController.refreshLocalIps();
      }
      final localIps = _receiveController.localIps;
      if (localIps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未获取到本机局域网 IP，无法进行网段探测'),
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }

      final results =
          (await _discoveryService.scan(localIps: localIps, port: 39527))
              .where(
                (d) => !_isSelfDiscoveredDevice(
                  host: d.host,
                  deviceId: d.deviceId,
                  localIps: localIps,
                ),
              )
              .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _discoveredDevices = results;
      });
      await _appendHistory(
        category: 'system',
        title: '网段探测完成',
        detail: '发现 ${results.length} 台设备（默认端口 39527）',
        success: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发现 ${results.length} 台设备'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      await _appendHistory(
        category: 'system',
        title: '网段探测失败',
        detail: '$e',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('网段探测失败: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 1),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isScanningDevices = false);
      }
    }
  }

  bool _isSelfDiscoveredDevice({
    required String host,
    required String deviceId,
    required List<String> localIps,
  }) {
    final localId = _receiveController.localDeviceId.trim();
    if (localId.isNotEmpty && deviceId.trim() == localId) {
      return true;
    }
    final trimmedHost = host.trim();
    return trimmedHost.isNotEmpty && localIps.contains(trimmedHost);
  }

  String _buildEphemeralDeviceName() {
    const adjectives = <String>[
      '敏捷',
      '冷静',
      '清晨',
      '明亮',
      '安静',
      '迅捷',
      '稳健',
      '轻盈',
      '灵巧',
      '坚实',
    ];
    const nouns = <String>[
      '海豚',
      '狐狸',
      '猎鹰',
      '熊猫',
      '北极星',
      '山猫',
      '燕子',
      '鲸鱼',
      '松鼠',
      '猫头鹰',
    ];
    final rnd = math.Random();
    final suffix = 100 + rnd.nextInt(900);
    return '${adjectives[rnd.nextInt(adjectives.length)]}'
        '${nouns[rnd.nextInt(nouns.length)]}-$suffix';
  }

  int? get _parsedTargetPort => int.tryParse(_targetPortController.text.trim());

  Future<void> _sendToHostPort(String host, int port) async {
    _targetHostController.text = host;
    _targetPortController.text = port.toString();
    if (mounted) setState(() {});
    await _sendAllToTarget();
  }

  Future<void> _showManualSendDialog() async {
    final result = await showLanManualSendDialog(
      context,
      initialHost: _targetHostController.text,
      initialPort: _targetPortController.text,
    );
    if (result == null) return;
    await _sendToHostPort(result.$1, result.$2);
  }

  Future<void> _pickMapForSend() async {
    final isar = ref.read(isarProvider);
    final maps = isar.gameMaps.where().findAllSync();
    if (maps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有地图数据')));
      return;
    }
    final selected = await showLanMapPickerDialog(context, maps);
    if (selected == null || !mounted) return;
    setState(() {
      _selectedMapForSend = selected;
      _sendScope = LanSendScope.map;
    });
  }

  Future<void> _pickGrenadesForSend() async {
    final isar = ref.read(isarProvider);
    final allGrenades = isar.grenades.where().findAllSync()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (allGrenades.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有道具数据')));
      return;
    }

    final result = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => LanSyncGrenadePickerScreen(
          grenades: allGrenades,
          initialSelectedIds: _selectedGrenadesForSend.map((e) => e.id).toSet(),
        ),
      ),
    );

    if (result == null || !mounted) return;
    final idSet = result.toSet();
    setState(() {
      _selectedGrenadesForSend = allGrenades
          .where((e) => idSet.contains(e.id))
          .toList(growable: false);
      _sendScope = LanSendScope.grenades;
    });
  }

  String _currentScopeSummary() {
    switch (_sendScope) {
      case LanSendScope.all:
        return '全部数据';
      case LanSendScope.map:
        return _selectedMapForSend == null
            ? '按地图（未选择）'
            : '地图：${_selectedMapForSend!.name}';
      case LanSendScope.grenades:
        return '按道具（${_selectedGrenadesForSend.length} 个）';
    }
  }

  Set<String> _resolveScopeMapKeys(Isar isar) {
    switch (_sendScope) {
      case LanSendScope.all:
        return isar.gameMaps
            .where()
            .findAllSync()
            .map((e) => e.name.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
      case LanSendScope.map:
        final name = _selectedMapForSend?.name.trim() ?? '';
        return name.isEmpty ? <String>{} : {name};
      case LanSendScope.grenades:
        final mapKeys = <String>{};
        for (final grenade in _selectedGrenadesForSend) {
          grenade.layer.loadSync();
          final layer = grenade.layer.value;
          if (layer == null) continue;
          layer.map.loadSync();
          final map = layer.map.value;
          if (map == null) continue;
          final mapName = map.name.trim();
          if (mapName.isNotEmpty) {
            mapKeys.add(mapName);
          }
        }
        return mapKeys;
    }
  }

  String _resolvePeerNodeId(String host, int port) {
    for (final d in _discoveredDevices) {
      if (d.host.trim() == host.trim() && d.port == port) {
        final nodeId = d.nodeId.trim();
        if (nodeId.isNotEmpty) return nodeId;
      }
    }
    return '$host:$port';
  }

  Future<String> _resolveConnectableHost(String host, int port) async {
    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty) {
      throw const SocketException('目标地址为空');
    }
    if (InternetAddress.tryParse(trimmedHost) != null) {
      return trimmedHost;
    }

    try {
      final resolved = await InternetAddress.lookup(trimmedHost);
      for (final address in resolved) {
        if (address.type == InternetAddressType.IPv4) {
          return address.address;
        }
      }
      if (resolved.isNotEmpty) {
        return resolved.first.address;
      }
    } catch (_) {}

    if (_receiveController.localIps.isEmpty) {
      await _receiveController.refreshLocalIps();
    }
    throw SocketException('无法解析设备地址：$trimmedHost');
  }

  bool _shouldSendIncrementalItem(
    LanSyncManifestItem local,
    LanSyncRemoteManifestItem? remote,
  ) {
    if (remote == null) return true;
    if (local.digest == remote.digest) return false;
    return local.updatedAtMs >= remote.updatedAtMs;
  }

  Future<_IncrementalSyncPayload> _prepareIncrementalSyncPayload({
    required DataService dataService,
    required String host,
    required int port,
    required Set<String> scopeMapKeys,
    required List<String> scopeMapList,
    required String peerNodeId,
  }) async {
    final manifestResp = await LanSyncTransferClient.fetchRemoteManifest(
      host: host,
      port: port,
      scopeType: switch (_sendScope) {
        LanSendScope.map => 'map',
        LanSendScope.grenades => 'grenades',
        LanSendScope.all => 'all',
      },
      scopeMapKeys: scopeMapList,
      senderNodeId: _receiveController.localNodeId,
      receiverNodeId: peerNodeId.contains(':') ? '' : peerNodeId,
      manifestSchemaVersion: 1,
    );
    if (!manifestResp.ok || manifestResp.manifestSchemaVersion != 1) {
      throw StateError(
        '对方版本不支持新的增量协议，请改用全量同步（HTTP ${manifestResp.statusCode}）',
      );
    }

    final localManifest = await dataService.buildLanSyncManifest(
      mapKeys: scopeMapKeys,
    );

    final grenadePayloads = <Map<String, dynamic>>[];
    final tagPayloads = <Map<String, dynamic>>[];
    final areaPayloads = <Map<String, dynamic>>[];
    final mapPayloads = <Map<String, dynamic>>[];
    final favoriteFolderPayloads = <Map<String, dynamic>>[];
    final impactGroupPayloads = <Map<String, dynamic>>[];
    final filesToZip = <String>{};

    for (final entry in localManifest.grenades.entries) {
      if (!_shouldSendIncrementalItem(
        entry.value,
        manifestResp.grenades[entry.key],
      )) {
        continue;
      }
      grenadePayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      filesToZip.addAll(entry.value.filesToZip);
    }
    for (final entry in localManifest.tags.entries) {
      if (_shouldSendIncrementalItem(
        entry.value,
        manifestResp.tags[entry.key],
      )) {
        tagPayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      }
    }
    for (final entry in localManifest.areas.entries) {
      if (_shouldSendIncrementalItem(
        entry.value,
        manifestResp.areas[entry.key],
      )) {
        areaPayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      }
    }
    for (final entry in localManifest.maps.entries) {
      if (!_shouldSendIncrementalItem(
        entry.value,
        manifestResp.maps[entry.key],
      )) {
        continue;
      }
      mapPayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      filesToZip.addAll(entry.value.filesToZip);
    }
    for (final entry in localManifest.favoriteFolders.entries) {
      if (_shouldSendIncrementalItem(
        entry.value,
        manifestResp.favoriteFolders[entry.key],
      )) {
        favoriteFolderPayloads.add(
          Map<String, dynamic>.from(entry.value.rawData),
        );
      }
    }
    for (final entry in localManifest.impactGroups.entries) {
      if (_shouldSendIncrementalItem(
        entry.value,
        manifestResp.impactGroups[entry.key],
      )) {
        impactGroupPayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      }
    }

    final remoteOnlyGrenadeIds = manifestResp.grenades.keys
        .where((key) => !localManifest.grenades.containsKey(key))
        .toSet();
    final grenadeTombstonesById = await _localStore.loadGrenadeTombstones(
      uniqueIds: remoteOnlyGrenadeIds,
      mapKeys: scopeMapList,
    );
    final grenadeTombstones = remoteOnlyGrenadeIds
        .map((uniqueId) {
          final tombstone = grenadeTombstonesById[uniqueId];
          final remote = manifestResp.grenades[uniqueId];
          if (tombstone == null || remote == null) return null;
          if (tombstone.deletedAt <= remote.updatedAtMs) return null;
          return PackageGrenadeTombstoneData(
            uniqueId: tombstone.uniqueId,
            mapName: tombstone.mapName,
            deletedAt: tombstone.deletedAt,
          );
        })
        .whereType<PackageGrenadeTombstoneData>()
        .toList(growable: false);

    final localEntityCompositeKeys = <String>{
      ...localManifest.tags.keys.map(
        (e) => dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.tag,
          entityKey: e,
        ),
      ),
      ...localManifest.areas.keys.map(
        (e) => dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.area,
          entityKey: e,
        ),
      ),
      ...localManifest.favoriteFolders.keys.map(
        (e) => dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.favoriteFolder,
          entityKey: e,
        ),
      ),
      ...localManifest.impactGroups.keys.map(
        (e) => dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.impactGroup,
          entityKey: e,
        ),
      ),
    };
    final remoteEntityItems = <String, LanSyncRemoteManifestItem>{
      for (final entry in manifestResp.tags.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.tag,
          entityKey: entry.key,
        ): entry.value,
      for (final entry in manifestResp.areas.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.area,
          entityKey: entry.key,
        ): entry.value,
      for (final entry in manifestResp.favoriteFolders.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.favoriteFolder,
          entityKey: entry.key,
        ): entry.value,
      for (final entry in manifestResp.impactGroups.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.impactGroup,
          entityKey: entry.key,
        ): entry.value,
    };
    final remoteOnlyEntityKeys = remoteEntityItems.keys
        .where((key) => !localEntityCompositeKeys.contains(key))
        .toSet();
    final entityTombstoneEntries = await _localStore.loadEntityTombstones(
      mapKeys: scopeMapList,
    );
    final entityTombstones = remoteOnlyEntityKeys
        .map((compositeKey) {
          final tombstone = entityTombstoneEntries[compositeKey];
          final remote = remoteEntityItems[compositeKey];
          if (tombstone == null || remote == null) return null;
          if (tombstone.deletedAt <= remote.updatedAtMs) return null;
          return PackageEntityTombstoneData(
            entityType: tombstone.entityType,
            entityKey: tombstone.entityKey,
            mapName: tombstone.mapName,
            deletedAt: tombstone.deletedAt,
            payload: tombstone.payload,
          );
        })
        .whereType<PackageEntityTombstoneData>()
        .toList(growable: false);

    return (
      grenadePayloads: grenadePayloads,
      tagPayloads: tagPayloads,
      areaPayloads: areaPayloads,
      mapPayloads: mapPayloads,
      favoriteFolderPayloads: favoriteFolderPayloads,
      impactGroupPayloads: impactGroupPayloads,
      filesToZip: filesToZip,
      grenadeTombstones: grenadeTombstones,
      entityTombstones: entityTombstones,
    );
  }

  Future<String> _buildSyncPackageForSend({
    required DataService dataService,
    required Set<String> scopeMapKeys,
    required _IncrementalSyncPayload? incremental,
  }) async {
    if (_sendScope == LanSendScope.grenades) {
      return dataService.buildLanSyncPackageToTemp(
        scopeType: 2,
        explicitGrenades: _selectedGrenadesForSend,
        grenadeTombstones: const [],
        entityTombstones: const [],
      );
    }

    final isIncremental = _sendMode == LanSyncMode.incremental;
    final fullManifest = isIncremental
        ? null
        : await dataService.buildLanSyncManifest(mapKeys: scopeMapKeys);
    final isSingleMapFull = _sendScope == LanSendScope.map && !isIncremental;
    return dataService.buildLanSyncPackageToTemp(
      scopeType: isSingleMapFull ? 1 : 2,
      singleMap: isSingleMapFull ? _selectedMapForSend! : null,
      explicitGrenadePayloads: isIncremental
          ? incremental!.grenadePayloads
          : fullManifest?.grenades.values
                  .map((item) => Map<String, dynamic>.from(item.rawData))
                  .toList(growable: false) ??
              const [],
      explicitTagPayloads: isIncremental
          ? incremental!.tagPayloads
          : fullManifest?.tags.values
                  .map((item) => Map<String, dynamic>.from(item.rawData))
                  .toList(growable: false) ??
              const [],
      explicitAreaPayloads: isIncremental
          ? incremental!.areaPayloads
          : fullManifest?.areas.values
                  .map((item) => Map<String, dynamic>.from(item.rawData))
                  .toList(growable: false) ??
              const [],
      explicitMapPayloads: isIncremental
          ? incremental!.mapPayloads
          : fullManifest?.maps.values
                  .map((item) => Map<String, dynamic>.from(item.rawData))
                  .toList(growable: false) ??
              const [],
      explicitFavoriteFolderPayloads: isIncremental
          ? incremental!.favoriteFolderPayloads
          : fullManifest?.favoriteFolders.values
                  .map((item) => Map<String, dynamic>.from(item.rawData))
                  .toList(growable: false) ??
              const [],
      explicitImpactGroupPayloads: isIncremental
          ? incremental!.impactGroupPayloads
          : fullManifest?.impactGroups.values
                  .map((item) => Map<String, dynamic>.from(item.rawData))
                  .toList(growable: false) ??
              const [],
      explicitFilesToZip: isIncremental
          ? incremental!.filesToZip
          : {
              ...(fullManifest?.grenades.values
                      .expand((item) => item.filesToZip)
                      .toSet() ??
                  const <String>{}),
              ...(fullManifest?.maps.values
                      .expand((item) => item.filesToZip)
                      .toSet() ??
                  const <String>{}),
            },
      grenadeTombstones: incremental?.grenadeTombstones ?? const [],
      entityTombstones: incremental?.entityTombstones ?? const [],
    );
  }

  Future<void> _sendAllToTarget() async {
    final originalHost = _targetHostController.text.trim();
    final port = _parsedTargetPort;
    if (originalHost.isEmpty || port == null || port <= 0 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效的目标 IP/主机和端口'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_sendScope == LanSendScope.map && _selectedMapForSend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先选择地图'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    if (_sendScope == LanSendScope.grenades &&
        _selectedGrenadesForSend.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先选择道具'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final isar = ref.read(isarProvider);
    final dataService = DataService(isar);
    final scopeMapKeys = _resolveScopeMapKeys(isar);
    final scopeMapList = scopeMapKeys.toList(growable: false);
    final peerNodeId = _resolvePeerNodeId(originalHost, port);
    _IncrementalSyncPayload? incremental;
    if (_sendMode == LanSyncMode.incremental) {
      if (_sendScope == LanSendScope.grenades) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('增量模式第一版暂不支持按道具发送'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (scopeMapList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法识别当前范围对应的地图，请先检查范围选择'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final host = await _resolveConnectableHost(originalHost, port);
      incremental = await _prepareIncrementalSyncPayload(
        dataService: dataService,
        host: host,
        port: port,
        scopeMapKeys: scopeMapKeys,
        scopeMapList: scopeMapList,
        peerNodeId: peerNodeId,
      );
      if (incremental.grenadePayloads.isEmpty &&
          incremental.tagPayloads.isEmpty &&
          incremental.areaPayloads.isEmpty &&
          incremental.mapPayloads.isEmpty &&
          incremental.favoriteFolderPayloads.isEmpty &&
          incremental.impactGroupPayloads.isEmpty &&
          incremental.grenadeTombstones.isEmpty &&
          incremental.entityTombstones.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前范围没有可同步的增量变更')));
        return;
      }
    }

    setState(() {
      _isSendingAll = true;
      _isWaitingForApproval = false;
      _sendProgress = null;
      _sendProgressLabel = '';
    });
    String? packagePath;
    try {
      final host = await _resolveConnectableHost(originalHost, port);
      packagePath = await _buildSyncPackageForSend(
        dataService: dataService,
        scopeMapKeys: scopeMapKeys,
        incremental: incremental,
      );

      final pkgFile = File(packagePath);
      final fileName = pkgFile.uri.pathSegments.isEmpty
          ? 'lan_sync_data.cs2pkg'
          : pkgFile.uri.pathSegments.last;
      final fileSize = await pkgFile.length();
      final syncEnvelopeId = 'env_${DateTime.now().microsecondsSinceEpoch}';
      if (mounted) {
        setState(() {
          _isWaitingForApproval = true;
          _sendProgress = 0;
          _sendProgressLabel = '等待接收方确认...';
        });
      }

      final reqResp = await LanSyncTransferClient.requestTransfer(
        host: host,
        port: port,
        fileName: fileName,
        sizeBytes: fileSize,
        senderName: _receiveController.localDeviceName,
        scopeSummary: _currentScopeSummary(),
        syncMode: _sendMode == LanSyncMode.incremental ? 'delta' : 'full',
        scopeType: switch (_sendScope) {
          LanSendScope.map => 'map',
          LanSendScope.grenades => 'grenades',
          LanSendScope.all => 'all',
        },
        scopeMapKeys: scopeMapList,
        syncEnvelopeId: syncEnvelopeId,
        senderNodeId: _receiveController.localNodeId,
        receiverNodeId: peerNodeId.contains(':') ? '' : peerNodeId,
        packageSchemaVersion: 7,
      );
      if (!reqResp.ok || reqResp.requestId.trim().isEmpty) {
        throw StateError(
          '发送请求失败（HTTP ${reqResp.statusCode}）: ${_friendlySendErrorBody(reqResp.body)}',
        );
      }

      final requestId = reqResp.requestId.trim();
      var approved = false;
      var rejectedMessage = '';
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final statusResp = await LanSyncTransferClient.getTransferRequestStatus(
          host: host,
          port: port,
          requestId: requestId,
        );
        if (!statusResp.ok) {
          continue;
        }
        if (statusResp.status ==
            LanIncomingTransferRequestStatus.approved.name) {
          approved = true;
          break;
        }
        if (statusResp.status ==
            LanIncomingTransferRequestStatus.rejected.name) {
          rejectedMessage = (statusResp.message ?? '').trim();
          break;
        }
      }
      if (!approved) {
        throw StateError(
          rejectedMessage.isNotEmpty ? rejectedMessage : '接收方未同意传输',
        );
      }

      if (mounted) {
        setState(() {
          _isWaitingForApproval = false;
          _sendProgress = 0;
          _sendProgressLabel = '开始传输...';
        });
      }

      final response = await LanSyncTransferClient.sendPackage(
        host: host,
        port: port,
        filePath: packagePath,
        transferRequestId: requestId,
        onSendProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _sendProgress = total <= 0 ? null : (sent / total).clamp(0.0, 1.0);
            _sendProgressLabel =
                '传输中 ${formatLanBytes(sent)} / ${formatLanBytes(total)}';
          });
        },
      );

      if (!response.isSuccess) {
        throw StateError(
          '发送失败（HTTP ${response.statusCode}）: ${_friendlySendErrorBody(response.body)}',
        );
      }

      if (mounted) {
        setState(() {
          _sendProgress = 1;
          _sendProgressLabel = '上传完成，等待对方导入...';
        });
      }

      final importDeadline = DateTime.now().add(const Duration(minutes: 5));
      var importSucceeded = false;
      String? importFailedMessage;
      while (DateTime.now().isBefore(importDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final statusResp = await LanSyncTransferClient.getTransferRequestStatus(
          host: host,
          port: port,
          requestId: requestId,
        );
        if (!statusResp.ok) continue;
        if (statusResp.status ==
            LanIncomingTransferRequestStatus.imported.name) {
          importSucceeded = true;
          break;
        }
        if (statusResp.status ==
                LanIncomingTransferRequestStatus.importFailed.name ||
            statusResp.status ==
                LanIncomingTransferRequestStatus.importCancelled.name ||
            statusResp.status ==
                LanIncomingTransferRequestStatus.rejected.name ||
            statusResp.status ==
                LanIncomingTransferRequestStatus.expired.name) {
          importFailedMessage = (statusResp.message ?? '').trim();
          break;
        }
      }
      if (!importSucceeded) {
        throw StateError(
          importFailedMessage?.isNotEmpty == true
              ? importFailedMessage!
              : '对方尚未完成导入确认，请稍后重试',
        );
      }

      await _refreshSyncDebugInfo();

      await _appendHistory(
        category: 'send',
        title: '发送成功',
        detail:
            '$originalHost -> $host:$port · ${_currentScopeSummary()} · ${_sendMode == LanSyncMode.incremental ? "增量" : "全量"}',
        success: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sendMode == LanSyncMode.incremental
                ? '增量同步完成（已收到导入确认）'
                : '全量同步完成（已收到导入确认）',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      await _appendHistory(
        category: 'send',
        title: '发送失败',
        detail: '$originalHost:$port · ${_currentScopeSummary()} · $e',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送失败: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 1),
        ),
      );
    } finally {
      if (packagePath != null) {
        final file = File(packagePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (mounted) {
        setState(() {
          _isSendingAll = false;
          _isWaitingForApproval = false;
          _sendProgress = null;
          _sendProgressLabel = '';
        });
      }
    }
  }

  Future<void> _toggleReceiveMode(bool enabled) async {
    if (enabled) {
      await _receiveController.start();
      if (!mounted) return;
      final error = _receiveController.lastError;
      if (error != null && !_receiveController.isRunning) {
        await _appendHistory(
          category: 'system',
          title: '接收模式启动失败',
          detail: error,
          success: false,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1),
          ),
        );
      } else if (_receiveController.isRunning) {
        await _appendHistory(
          category: 'system',
          title: '接收模式已开启',
          detail: '端口 ${_receiveController.port}',
          success: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('接收模式已开启（端口 ${_receiveController.port}）'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    await _receiveController.stop();
    await _appendHistory(
      category: 'system',
      title: '接收模式已关闭',
      detail: '用户手动关闭',
      success: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('接收模式已关闭'), duration: Duration(seconds: 1)),
    );
  }

  Set<String> _buildSilentImportSelectedIds(PackagePreviewResult preview) {
    final selected = <String>{};
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final item in mapGrenades) {
        if (item.status != ImportStatus.skip) {
          selected.add(item.uniqueId);
        }
      }
    }
    return selected;
  }

  Future<void> _beginImportTask(
    LanReceivedPackageTask task,
    String transferRequestId,
  ) async {
    await _receiveController.markTaskStatus(
      task.id,
      LanReceiveTaskStatus.importing,
      clearMessage: true,
    );
    if (transferRequestId.isNotEmpty) {
      await _receiveController.markIncomingRequestStatus(
        transferRequestId,
        LanIncomingTransferRequestStatus.importing,
        clearMessage: true,
      );
    }
  }

  Future<bool> _ensureImportFileExists(
    LanReceivedPackageTask task,
    String transferRequestId, {
    required String missingHistoryTitle,
    Duration? snackBarDuration,
  }) async {
    final file = File(task.filePath);
    if (await file.exists()) return true;

    await _receiveController.markTaskStatus(
      task.id,
      LanReceiveTaskStatus.failed,
      message: '文件不存在，可能已被系统清理',
    );
    if (transferRequestId.isNotEmpty) {
      await _receiveController.markIncomingRequestStatus(
        transferRequestId,
        LanIncomingTransferRequestStatus.importFailed,
        message: '导入失败：接收文件不存在',
      );
    }
    await _appendHistory(
      category: 'import',
      title: missingHistoryTitle,
      detail: '${task.fileName} · 文件不存在',
      success: false,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('文件不存在，无法导入'),
          backgroundColor: Colors.red,
          duration: snackBarDuration ?? const Duration(milliseconds: 4000),
        ),
      );
    }
    return false;
  }

  Future<void> _cancelImportTask(
    LanReceivedPackageTask task,
    String transferRequestId,
    String historyDetail,
  ) async {
    if (transferRequestId.isNotEmpty) {
      await _receiveController.markIncomingRequestStatus(
        transferRequestId,
        LanIncomingTransferRequestStatus.importCancelled,
        message: '接收方取消导入',
      );
    }
    await _appendHistory(
      category: 'import',
      title: '取消导入',
      detail: historyDetail,
      success: true,
    );
    await _receiveController.removeTask(task.id);
  }

  Future<void> _completeImportTask(
    LanReceivedPackageTask task,
    String transferRequestId,
    String importResult, {
    required bool silent,
  }) async {
    await _receiveController.markTaskStatus(
      task.id,
      LanReceiveTaskStatus.imported,
      message: importResult,
    );
    if (transferRequestId.isNotEmpty) {
      await _receiveController.markIncomingRequestStatus(
        transferRequestId,
        LanIncomingTransferRequestStatus.imported,
        message: importResult,
        importSummary: {
          'result': importResult,
          'taskId': task.id,
          'importedAtMs': DateTime.now().millisecondsSinceEpoch,
          if (silent) 'silentImport': true,
        },
      );
    }
    await _appendHistory(
      category: 'import',
      title: silent ? '静默导入完成' : '导入完成',
      detail: '${task.fileName} · $importResult',
      success: importResult.contains('成功'),
    );
    await _receiveController.removeTask(task.id, deleteFile: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(silent ? '静默导入完成：$importResult' : importResult),
        backgroundColor:
            importResult.contains('成功') ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _failImportTask(
    LanReceivedPackageTask task,
    String transferRequestId, {
    required String statusMessage,
    required String historyTitle,
    required String detail,
    required String snackBarText,
  }) async {
    await _receiveController.markTaskStatus(
      task.id,
      LanReceiveTaskStatus.failed,
      message: statusMessage,
    );
    if (transferRequestId.isNotEmpty) {
      await _receiveController.markIncomingRequestStatus(
        transferRequestId,
        LanIncomingTransferRequestStatus.importFailed,
        message: statusMessage,
      );
    }
    await _appendHistory(
      category: 'import',
      title: historyTitle,
      detail: detail,
      success: false,
    );
    await _receiveController.removeTask(task.id, deleteFile: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackBarText), backgroundColor: Colors.red),
    );
  }

  Future<Map<String, TResolution>?>
      _resolveSilentImportConflicts<TConflict, TResolution>({
    required List<TConflict> conflicts,
    required String Function(TConflict conflict) keyOf,
    required Future<LanImportConflictDialogResult<TResolution>?> Function(
      TConflict conflict,
      int index,
      int total,
    ) showDialogFn,
    required LanReceivedPackageTask task,
    required String transferRequestId,
    required String cancelDetail,
  }) async {
    final resolutions = <String, TResolution>{};
    TResolution? resolutionForRemaining;
    for (var i = 0; i < conflicts.length; i++) {
      if (!mounted) return null;
      final conflict = conflicts[i];
      final dialogResult = resolutionForRemaining != null
          ? LanImportConflictDialogResult<TResolution>(
              resolution: resolutionForRemaining,
              applyToRemaining: true,
            )
          : await showDialogFn(conflict, i + 1, conflicts.length);
      if (dialogResult == null) {
        await _cancelImportTask(task, transferRequestId, cancelDetail);
        return null;
      }
      resolutions[keyOf(conflict)] = dialogResult.resolution;
      if (dialogResult.applyToRemaining) {
        resolutionForRemaining = dialogResult.resolution;
      }
    }
    return resolutions;
  }

  Future<void> _importTaskSilently(LanReceivedPackageTask task) async {
    final transferRequestId = (task.transferRequestId ?? '').trim();
    if (!await _ensureImportFileExists(
      task,
      transferRequestId,
      missingHistoryTitle: '静默导入失败',
      snackBarDuration: const Duration(seconds: 1),
    )) {
      return;
    }

    await _beginImportTask(task, transferRequestId);

    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final preview = await dataService.previewPackage(
        task.filePath,
        mode: ImportPackageMode.lanSync,
      );
      if (preview == null) {
        throw StateError('文件格式错误或无数据');
      }

      final selectedIds = _buildSilentImportSelectedIds(preview);
      final conflictNotice = await dataService.collectImportConflictNotice(
        preview,
        selectedIds,
        mode: ImportPackageMode.lanSync,
      );
      if (conflictNotice.hasConflicts) {
        if (!mounted) return;
        final continueImport = await showLanImportConflictNoticeDialog(
          context,
          conflictNotice,
        );
        if (continueImport != true) {
          await _cancelImportTask(
            task,
            transferRequestId,
            '${task.fileName} · 冲突处理已取消',
          );
          return;
        }
      }

      final tagConflictBundle = await dataService.collectTagConflicts(
        preview,
        selectedIds,
      );
      final tagResolutions = await _resolveSilentImportConflicts<
          TagConflictItem, ImportTagConflictResolution>(
        conflicts: tagConflictBundle.tagConflicts,
        keyOf: (conflict) => conflict.sharedTag.tagUuid,
        showDialogFn: (conflict, index, total) => showLanTagConflictDialog(
          context,
          conflict,
          index: index,
          total: total,
        ),
        task: task,
        transferRequestId: transferRequestId,
        cancelDetail: '${task.fileName} · 标签冲突处理已取消',
      );
      if (tagResolutions == null) return;

      final areaConflicts = await dataService.collectAreaConflicts(
        preview,
        selectedIds,
        tagResolutions: tagResolutions,
      );
      final areaResolutions = await _resolveSilentImportConflicts<
          AreaConflictGroup, ImportAreaConflictResolution>(
        conflicts: areaConflicts,
        keyOf: (conflict) => conflict.tagUuid,
        showDialogFn: (conflict, index, total) => showLanAreaConflictDialog(
          context,
          conflict,
          index: index,
          total: total,
        ),
        task: task,
        transferRequestId: transferRequestId,
        cancelDetail: '${task.fileName} · 区域冲突处理已取消',
      );
      if (areaResolutions == null) return;

      final importResult = await dataService.importFromPreview(
        preview,
        selectedIds,
        tagResolutions: tagResolutions,
        areaResolutions: areaResolutions,
        mode: ImportPackageMode.lanSync,
      );

      await _completeImportTask(
        task,
        transferRequestId,
        importResult,
        silent: true,
      );
    } catch (e) {
      await _failImportTask(
        task,
        transferRequestId,
        statusMessage: '静默导入失败: $e',
        historyTitle: '静默导入失败',
        detail: '${task.fileName} · $e',
        snackBarText: '静默导入失败: $e',
      );
    }
  }

  Future<void> _openImportPreview(LanReceivedPackageTask task) async {
    final transferRequestId = (task.transferRequestId ?? '').trim();
    if (!await _ensureImportFileExists(
      task,
      transferRequestId,
      missingHistoryTitle: '导入失败',
    )) {
      return;
    }

    await _beginImportTask(task, transferRequestId);

    try {
      if (!mounted) return;
      final importResult = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => ImportPreviewScreen(
            filePath: task.filePath,
            importMode: ImportPackageMode.lanSync,
          ),
        ),
      );

      if (importResult == null) {
        await _cancelImportTask(task, transferRequestId, task.fileName);
        return;
      }

      await _completeImportTask(
        task,
        transferRequestId,
        importResult,
        silent: false,
      );
    } catch (e) {
      await _failImportTask(
        task,
        transferRequestId,
        statusMessage: '导入预览失败: $e',
        historyTitle: '导入失败',
        detail: '${task.fileName} · $e',
        snackBarText: '打开导入预览失败: $e',
      );
    }
  }

  String _friendlySendErrorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = (decoded['error'] as String? ?? '').trim();
        if (error == 'unknown_peer') {
          return '请重新配对设备';
        }
      }
    } catch (_) {}
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('局域网同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LanNoticeBanner(
            backgroundColor: colorScheme.primaryContainer.withValues(
              alpha: 0.6,
            ),
            foregroundColor: colorScheme.onPrimaryContainer,
            icon: Icons.wifi,
            text:
                '该功能仅支持同一网络环境（同一 Wi-Fi / 同一局域网）下的设备互传。请确保双方设备已连接到同一网络，并且网络环境允许设备间通信（部分公共 Wi-Fi 可能有限制）。',
          ),
          const SizedBox(height: 8),
          LanNoticeBanner(
            backgroundColor: colorScheme.secondaryContainer.withValues(
              alpha: 0.45,
            ),
            foregroundColor: colorScheme.onSecondaryContainer,
            icon: Icons.sync_problem_outlined,
            text: '若你是从旧版本升级到当前版本，建议先在设备间执行一次全量同步，统一旧版本遗留的数据状态；完成后再使用增量同步会更稳定。',
          ),
          const SizedBox(height: 12),
          LanSyncSendSection(
            isLoadingLocal: _isLoadingLocal,
            isScanningDevices: _isScanningDevices,
            isSendingAll: _isSendingAll,
            isWaitingForApproval: _isWaitingForApproval,
            sendProgress: _sendProgress,
            sendProgressLabel: _sendProgressLabel,
            sendMode: _sendMode,
            sendScope: _sendScope,
            selectedGrenadesCount: _selectedGrenadesForSend.length,
            scopeSummary: _currentScopeSummary(),
            discoveredDevices: _discoveredDevices,
            onScanDevices: _scanDevices,
            onShowManualSendDialog: _showManualSendDialog,
            onSendModeChanged: (mode) => setState(() {
              _sendMode = mode;
              if (mode == LanSyncMode.incremental &&
                  _sendScope == LanSendScope.grenades) {
                _sendScope = LanSendScope.all;
              }
            }),
            onShowSendModeHelp: () => showLanSendModeHelpDialog(context),
            onSendScopeChanged: (scope) => setState(() => _sendScope = scope),
            onPickMapForSend: _pickMapForSend,
            onPickGrenadesForSend: _pickGrenadesForSend,
            onSendToHostPort: _sendToHostPort,
          ),
          const SizedBox(height: 12),
          LanSyncReceiveSection(
            receiveController: _receiveController,
            silentImportEnabled: _silentImportEnabled,
            onRefreshLocalIps: () => _receiveController.refreshLocalIps(),
            onToggleReceiveMode: _toggleReceiveMode,
            onSetSilentImportEnabled: _setSilentImportEnabled,
            onRejectIncomingRequest: (requestId) => _receiveController
                .rejectIncomingRequest(requestId, message: '接收方拒绝'),
            onApproveIncomingRequest: (requestId) =>
                _receiveController.approveIncomingRequest(requestId),
          ),
        ],
      ),
    );
  }
}
