import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';

import 'lan_sync_auth.dart';
import 'receive/lan_receive_models.dart';
import 'receive/lan_receive_request_router.dart';

export 'receive/lan_receive_models.dart'
    show
        LanIncomingTransferRequest,
        LanIncomingTransferRequestStatus,
        LanReceiveTaskStatus,
        LanReceivedPackageTask;

/// 局域网同步接收服务门面控制器
class LanSyncReceiveController extends ChangeNotifier {
  final Isar isar;
  String _localNodeId;
  HttpServer? _server;
  bool _disposed = false;
  bool _isStarting = false;
  String? _lastError;
  final List<String> _localIps = [];
  final List<LanReceivedPackageTask> _tasks = [];
  final List<LanIncomingTransferRequest> _incomingRequests = [];
  final Map<String, String> _trustedPeerSecrets = <String, String>{};
  String _localDeviceName = Platform.localHostname;
  bool _requireAuthForUpload = false;
  String? _activePairCode;
  int? _activePairCodeExpireAtMs;
  late final LanReceiveRequestRouter _router =
      LanReceiveRequestRouter(_ControllerRouterDelegate(this));

  LanSyncReceiveController({
    required this.isar,
    String? stableNodeId,
  }) : _localNodeId = (stableNodeId ?? '').trim().isEmpty
            ? 'node_${LanSyncAuth.generateSecret(bytes: 9)}'
            : stableNodeId!.trim();

  bool get isStarting => _isStarting;
  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String? get lastError => _lastError;
  String get localNodeId => _localNodeId;
  String get localDeviceId => _localNodeId;
  String get localDeviceName => _localDeviceName;
  bool get requireAuthForUpload => _requireAuthForUpload;
  String? get activePairCode => _activePairCode;
  DateTime? get activePairCodeExpireAt => _activePairCodeExpireAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_activePairCodeExpireAtMs!);
  List<String> get localIps => List.unmodifiable(_localIps);
  List<LanReceivedPackageTask> get tasks => List.unmodifiable(_tasks);
  List<LanIncomingTransferRequest> get incomingRequests =>
      List.unmodifiable(_incomingRequests);
  int get trustedPeerCount => _trustedPeerSecrets.length;

  String get healthPath => LanReceiveRequestRouter.healthPath;
  String get pairPath => LanReceiveRequestRouter.pairPath;
  String get transferRequestPath => LanReceiveRequestRouter.transferRequestPath;
  String get transferRequestStatusPath =>
      LanReceiveRequestRouter.transferRequestStatusPath;
  String get transferManifestPath =>
      LanReceiveRequestRouter.transferManifestPath;
  String get uploadPath => LanReceiveRequestRouter.uploadPath;

  void setLocalNodeId(String nodeId) {
    final next = nodeId.trim();
    if (next.isEmpty || next == _localNodeId) return;
    _localNodeId = next;
    notifyListeners();
  }

  void setLocalDeviceName(String name) {
    final next = name.trim();
    if (next.isEmpty || next == _localDeviceName) return;
    _localDeviceName = next;
    notifyListeners();
  }

  void setRequireAuthForUpload(bool value) {
    if (_requireAuthForUpload == value) return;
    _requireAuthForUpload = value;
    notifyListeners();
  }

  void setTrustedPeerSecrets(Map<String, String> peerSecretByPeerId) {
    _trustedPeerSecrets
      ..clear()
      ..addEntries(peerSecretByPeerId.entries.where(
        (e) => e.key.trim().isNotEmpty && e.value.trim().isNotEmpty,
      ));
    notifyListeners();
  }

  String issuePairCode({Duration ttl = const Duration(minutes: 5)}) {
    _activePairCode = LanSyncAuth.generatePairCode();
    _activePairCodeExpireAtMs = DateTime.now().add(ttl).millisecondsSinceEpoch;
    notifyListeners();
    return _activePairCode!;
  }

  void clearPairCode() {
    _activePairCode = null;
    _activePairCodeExpireAtMs = null;
    notifyListeners();
  }

  Future<void> refreshLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final next = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.type != InternetAddressType.IPv4) {
            continue;
          }
          next.add(addr.address);
        }
      }
      _localIps
        ..clear()
        ..addAll(next.toList()..sort());
      notifyListeners();
    } catch (e) {
      _lastError = '读取本机地址失败: $e';
      notifyListeners();
    }
  }

  Future<void> start({int preferredPort = 39527}) async {
    if (isRunning || _isStarting) return;

    _isStarting = true;
    _lastError = null;
    notifyListeners();

    try {
      HttpServer server;
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          preferredPort,
          shared: true,
        );
      } on SocketException {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          0,
          shared: true,
        );
      }

      _server = server;
      server.listen(
        (request) => unawaited(_router.handleRequest(request)),
        onError: (Object e, StackTrace st) {
          _lastError = '接收服务异常: $e';
          notifyListeners();
        },
      );

      await refreshLocalIps();
    } catch (e) {
      _lastError = '启动接收服务失败: $e';
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    notifyListeners();
  }

  bool _hasValidPairCode(String code) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_activePairCode == null || _activePairCodeExpireAtMs == null) {
      return false;
    }
    if (now > _activePairCodeExpireAtMs!) {
      clearPairCode();
      return false;
    }
    return _activePairCode == code.trim();
  }

  LanIncomingTransferRequest? _findIncomingRequest(String id) {
    for (final request in _incomingRequests) {
      if (request.id == id) return request;
    }
    return null;
  }

  void _updateTask(
    String taskId, {
    LanReceiveTaskStatus? status,
    String? message,
    bool clearMessage = false,
    int? sizeBytes,
    int? bytesReceived,
  }) {
    final index = _tasks.indexWhere((e) => e.id == taskId);
    if (index < 0) return;
    _tasks[index] = _tasks[index].copyWith(
      status: status,
      message: message,
      clearMessage: clearMessage,
      sizeBytes: sizeBytes,
      bytesReceived: bytesReceived,
    );
    notifyListeners();
  }

  Future<void> approveIncomingRequest(String requestId) async {
    await markIncomingRequestStatus(
      requestId,
      LanIncomingTransferRequestStatus.approved,
      clearMessage: true,
    );
  }

  Future<void> rejectIncomingRequest(
    String requestId, {
    String? message,
  }) async {
    await markIncomingRequestStatus(
      requestId,
      LanIncomingTransferRequestStatus.rejected,
      message: message ?? '接收方已拒绝',
    );
  }

  Future<void> markTaskStatus(
    String taskId,
    LanReceiveTaskStatus status, {
    String? message,
    bool clearMessage = false,
  }) async {
    _updateTask(
      taskId,
      status: status,
      message: message,
      clearMessage: clearMessage,
    );
  }

  Future<void> markIncomingRequestStatus(
    String requestId,
    LanIncomingTransferRequestStatus status, {
    String? message,
    Map<String, dynamic>? importSummary,
    bool clearMessage = false,
    bool clearImportSummary = false,
  }) async {
    final index = _incomingRequests.indexWhere((e) => e.id == requestId);
    if (index < 0) return;
    _incomingRequests[index] = _incomingRequests[index].copyWith(
      status: status,
      message: message,
      clearMessage: clearMessage,
      importSummary: importSummary,
      clearImportSummary: clearImportSummary,
    );
    notifyListeners();
  }

  Future<void> removeTask(String taskId, {bool deleteFile = true}) async {
    final index = _tasks.indexWhere((e) => e.id == taskId);
    if (index < 0) return;
    final task = _tasks.removeAt(index);
    if (deleteFile) {
      final file = File(task.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    notifyListeners();
  }

  Future<void> clearImportedTasks() async {
    final imported = _tasks
        .where((e) => e.status == LanReceiveTaskStatus.imported)
        .map((e) => e.id)
        .toList(growable: false);
    for (final id in imported) {
      await removeTask(id);
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final server = _server;
    _server = null;
    if (server != null) {
      unawaited(server.close(force: true));
    }
    super.dispose();
  }
}

class _ControllerRouterDelegate implements LanReceiveRouterDelegate {
  final LanSyncReceiveController _controller;

  const _ControllerRouterDelegate(this._controller);

  @override
  Isar get isar => _controller.isar;

  @override
  int? get port => _controller.port;

  @override
  String get localNodeId => _controller.localNodeId;

  @override
  String get localDeviceName => _controller.localDeviceName;

  @override
  bool get requireAuthForUpload => _controller.requireAuthForUpload;

  @override
  Map<String, String> get trustedPeerSecrets => _controller._trustedPeerSecrets;

  @override
  bool verifyPairCode(String code) => _controller._hasValidPairCode(code);

  @override
  void saveTrustedPeerSecret(String peerId, String secret) {
    _controller._trustedPeerSecrets[peerId] = secret;
    _controller.notifyListeners();
  }

  @override
  LanIncomingTransferRequest? findIncomingRequest(String id) =>
      _controller._findIncomingRequest(id);

  @override
  void prependIncomingRequest(LanIncomingTransferRequest incoming) {
    _controller._incomingRequests.insert(0, incoming);
    if (_controller._incomingRequests.length > 100) {
      _controller._incomingRequests
          .removeRange(100, _controller._incomingRequests.length);
    }
    _controller.notifyListeners();
  }

  @override
  void updateIncomingRequest(
    String requestId,
    LanIncomingTransferRequestStatus status, {
    String? message,
    bool clearMessage = false,
    bool clearImportSummary = false,
  }) {
    unawaited(_controller.markIncomingRequestStatus(
      requestId,
      status,
      message: message,
      clearMessage: clearMessage,
      clearImportSummary: clearImportSummary,
    ));
  }

  @override
  void prependTask(LanReceivedPackageTask task) {
    _controller._tasks.insert(0, task);
    _controller.notifyListeners();
  }

  @override
  void updateTask(
    String taskId, {
    LanReceiveTaskStatus? status,
    String? message,
    bool clearMessage = false,
    int? sizeBytes,
    int? bytesReceived,
  }) {
    _controller._updateTask(
      taskId,
      status: status,
      message: message,
      clearMessage: clearMessage,
      sizeBytes: sizeBytes,
      bytesReceived: bytesReceived,
    );
  }

  @override
  void reportRequestError(String message) {
    _controller._lastError = message;
    _controller.notifyListeners();
  }
}
