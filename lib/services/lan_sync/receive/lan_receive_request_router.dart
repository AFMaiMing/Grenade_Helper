import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data_service.dart';
import '../lan_sync_auth.dart';
import 'lan_receive_models.dart';
import 'lan_receive_signature_verifier.dart';

/// 接收请求路由所需控制器状态访问接口
abstract interface class LanReceiveRouterDelegate {
  Isar get isar;
  int? get port;
  String get localNodeId;
  String get localDeviceName;
  bool get requireAuthForUpload;
  Map<String, String> get trustedPeerSecrets;
  bool verifyPairCode(String code);
  void saveTrustedPeerSecret(String peerId, String secret);
  LanIncomingTransferRequest? findIncomingRequest(String id);
  void prependIncomingRequest(LanIncomingTransferRequest incoming);
  void updateIncomingRequest(
    String requestId,
    LanIncomingTransferRequestStatus status, {
    String? message,
    bool clearMessage = false,
    bool clearImportSummary = false,
  });
  void prependTask(LanReceivedPackageTask task);
  void updateTask(
    String taskId, {
    LanReceiveTaskStatus? status,
    String? message,
    bool clearMessage = false,
    int? sizeBytes,
    int? bytesReceived,
  });
  void reportRequestError(String message);
}

/// 局域网接收服务 HTTP 请求路由处理器
class LanReceiveRequestRouter {
  static const String healthPath = '/v1/health';
  static const String pairPath = '/v1/pair/request';
  static const String transferRequestPath = '/v1/transfer/request';
  static const String transferRequestStatusPath = '/v1/transfer/request_status';
  static const String transferManifestPath = '/v1/transfer/manifest';
  static const String uploadPath = '/v1/transfer/package';

  final LanReceiveRouterDelegate _delegate;
  final LanReceiveSignatureVerifier _signatureVerifier =
      LanReceiveSignatureVerifier();

  LanReceiveRequestRouter(this._delegate);

  Future<void> handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == healthPath) {
        _handleHealth(request);
        return;
      }
      if (request.method == 'POST' && path == pairPath) {
        await _handlePairRequest(request);
        return;
      }
      if (request.method == 'POST' && path == transferRequestPath) {
        await _handleTransferRequest(request);
        return;
      }
      if (request.method == 'GET' && path == transferRequestStatusPath) {
        _handleTransferRequestStatus(request);
        return;
      }
      if (request.method == 'POST' && path == transferManifestPath) {
        await _handleTransferManifest(request);
        return;
      }
      if (request.method == 'POST' && path == uploadPath) {
        await _handlePackageUpload(request);
        return;
      }

      writeJson(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'not_found',
      });
    } catch (e) {
      _delegate.reportRequestError('处理请求失败: $e');
      try {
        writeJson(request.response, HttpStatus.internalServerError, {
          'ok': false,
          'error': 'internal_error',
          'message': '$e',
        });
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  void _handleHealth(HttpRequest request) {
    // deviceId/deviceName 保留用于兼容旧版客户端健康检查解析
    writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'service': 'grenade_helper_lan_sync_receiver',
      'port': _delegate.port,
      'nodeId': _delegate.localNodeId,
      'displayName': _delegate.localDeviceName,
      'deviceId': _delegate.localNodeId,
      'deviceName': _delegate.localDeviceName,
      'requireAuthForUpload': _delegate.requireAuthForUpload,
      'trustedPeerCount': _delegate.trustedPeerSecrets.length,
      'capabilities': {
        'fullSyncV3': true,
        'deltaSyncV6Manifest': true,
        'requestStatusImportAck': true,
      },
      'time': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _handlePairRequest(HttpRequest request) async {
    final body = await _decodeJsonBody(request);
    if (body == null) return;

    final pairCode = (body['pairCode'] as String? ?? '').trim();
    final peerId = (body['peerId'] as String? ?? '').trim();
    final deviceName = (body['deviceName'] as String? ?? '').trim();

    if (pairCode.isEmpty || peerId.isEmpty) {
      writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'missing_fields',
      });
      return;
    }
    if (!_delegate.verifyPairCode(pairCode)) {
      writeJson(request.response, HttpStatus.unauthorized, {
        'ok': false,
        'error': 'invalid_pair_code',
      });
      return;
    }

    final secret = LanSyncAuth.generateSecret(bytes: 24);
    _delegate.saveTrustedPeerSecret(peerId, secret);

    writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'peerId': peerId,
      'sharedSecret': secret,
      'remoteDeviceId': _delegate.localNodeId,
      'remoteDeviceName': _delegate.localDeviceName,
      'acceptedAt': DateTime.now().toIso8601String(),
      'clientDeviceName': deviceName,
    });
  }

  Future<void> _handleTransferRequest(HttpRequest request) async {
    final body = await _decodeJsonBody(request);
    if (body == null) return;

    final fileName = _normalizePackageFileName(body['fileName'] as String?);
    final sizeBytes = body['sizeBytes'] as int? ?? 0;
    if (sizeBytes <= 0) {
      writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'invalid_size',
      });
      return;
    }

    final syncMode = (body['syncMode'] as String? ?? 'full').trim();
    final scopeMapKeys = _parseNormalizedStringList(body['scopeMapKeys']);
    final syncEnvelopeId = (body['syncEnvelopeId'] as String? ?? '').trim();
    final baseMapBaselineIds = _parseStringMap(body['baseMapBaselineIds']);
    final id = 'req_${DateTime.now().microsecondsSinceEpoch}';

    final incoming = LanIncomingTransferRequest(
      id: id,
      fileName: fileName,
      sizeBytes: sizeBytes,
      requestedAt: DateTime.now(),
      remoteAddress: request.connectionInfo?.remoteAddress.address,
      senderName: (body['senderName'] as String? ?? '').trim(),
      scopeSummary: (body['scopeSummary'] as String? ?? '').trim(),
      syncMode: syncMode,
      scopeType: (body['scopeType'] as String? ?? 'all').trim(),
      scopeMapKeys: scopeMapKeys,
      syncEnvelopeId: syncEnvelopeId.isEmpty
          ? 'env_${DateTime.now().microsecondsSinceEpoch}'
          : syncEnvelopeId,
      senderNodeId: (body['senderNodeId'] as String? ?? '').trim(),
      receiverNodeId: (body['receiverNodeId'] as String? ?? '').trim(),
      packageSchemaVersion:
          body['packageSchemaVersion'] as int? ?? (syncMode == 'delta' ? 6 : 3),
      baseMapBaselineIds: baseMapBaselineIds,
      status: LanIncomingTransferRequestStatus.pending,
    );
    _delegate.prependIncomingRequest(incoming);

    writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'requestId': id,
      'status': 'pending',
      'syncMode': incoming.syncMode,
      'scopeType': incoming.scopeType,
      'scopeMapKeys': incoming.scopeMapKeys,
      'syncEnvelopeId': incoming.syncEnvelopeId,
    });
  }

  Future<void> _handleTransferManifest(HttpRequest request) async {
    final body = await _decodeJsonBody(request);
    if (body == null) return;

    final manifestSchemaVersion = body['manifestSchemaVersion'] as int? ?? 0;
    if (manifestSchemaVersion != 1) {
      writeJson(request.response, HttpStatus.preconditionFailed, {
        'ok': false,
        'error': 'unsupported_manifest_schema',
      });
      return;
    }

    final scopeMapKeys =
        _parseNormalizedStringList(body['scopeMapKeys']).toSet();
    final manifest = await DataService(_delegate.isar).buildLanSyncManifest(
      mapKeys: scopeMapKeys,
    );
    writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      ...manifest.toManifestJson(),
    });
  }

  void _handleTransferRequestStatus(HttpRequest request) {
    final id = (request.uri.queryParameters['id'] ?? '').trim();
    if (id.isEmpty) {
      writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'missing_id',
      });
      return;
    }
    final incoming = _delegate.findIncomingRequest(id);
    if (incoming == null) {
      writeJson(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'request_not_found',
      });
      return;
    }
    writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'requestId': incoming.id,
      'status': incoming.status.name,
      'message': incoming.message,
      'syncMode': incoming.syncMode,
      'scopeType': incoming.scopeType,
      'scopeMapKeys': incoming.scopeMapKeys,
      'syncEnvelopeId': incoming.syncEnvelopeId,
      'importSummary': incoming.importSummary,
    });
  }

  Future<void> _handlePackageUpload(HttpRequest request) async {
    final incomingRequestId =
        (request.headers.value('x-transfer-request-id') ?? '').trim();
    if (incomingRequestId.isEmpty) {
      writeJson(request.response, HttpStatus.preconditionFailed, {
        'ok': false,
        'error': 'missing_transfer_request_id',
      });
      return;
    }
    final incoming = _delegate.findIncomingRequest(incomingRequestId);
    if (incoming == null) {
      writeJson(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'request_not_found',
      });
      return;
    }
    if (incoming.status == LanIncomingTransferRequestStatus.rejected) {
      writeJson(request.response, HttpStatus.forbidden, {
        'ok': false,
        'error': 'request_rejected',
        'message': incoming.message,
      });
      return;
    }
    if (incoming.status != LanIncomingTransferRequestStatus.approved) {
      writeJson(request.response, HttpStatus.preconditionFailed, {
        'ok': false,
        'error': 'request_not_approved',
      });
      return;
    }

    _delegate.updateIncomingRequest(
      incoming.id,
      LanIncomingTransferRequestStatus.uploading,
      clearMessage: true,
    );

    final fileName = _normalizePackageFileName(
      request.uri.queryParameters['filename'] ??
          request.headers.value('x-file-name'),
    );
    final inboxDir = await _getInboxDir();
    final taskId = DateTime.now().microsecondsSinceEpoch.toString();
    final file = File(p.join(inboxDir.path, '${taskId}_$fileName'));
    final expectedBytes = incoming.sizeBytes > 0
        ? incoming.sizeBytes
        : int.tryParse(
            request.headers.value(HttpHeaders.contentLengthHeader) ?? '',
          );
    final signedBodyMode = _delegate.requireAuthForUpload ||
        (request.headers.value('x-lan-sign')?.trim().isNotEmpty == true);

    _delegate.prependTask(
      LanReceivedPackageTask(
        id: taskId,
        filePath: file.path,
        fileName: fileName,
        sizeBytes: 0,
        bytesReceived: 0,
        expectedBytes: expectedBytes,
        transferRequestId: incomingRequestId,
        syncEnvelopeId: incoming.syncEnvelopeId,
        receivedAt: DateTime.now(),
        remoteAddress: request.connectionInfo?.remoteAddress.address,
        status: LanReceiveTaskStatus.receiving,
        message: '传输中...',
      ),
    );

    var receivedBytes = 0;
    final bufferedForSign = signedBodyMode ? <int>[] : null;
    final sink = file.openWrite();
    try {
      await for (final chunk in request) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        bufferedForSign?.addAll(chunk);
        _delegate.updateTask(
          taskId,
          bytesReceived: receivedBytes,
          sizeBytes: receivedBytes,
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (signedBodyMode) {
      final verifyError = _signatureVerifier.verifyUploadSignature(
        method: request.method,
        path: request.uri.path,
        bodyBytes: bufferedForSign ?? const <int>[],
        headers: request.headers,
        trustedPeerSecrets: _delegate.trustedPeerSecrets,
      );
      if (verifyError != null) {
        _failUpload(
          response: request.response,
          taskId: taskId,
          incomingId: incoming.id,
          statusCode: HttpStatus.unauthorized,
          errorCode: verifyError,
          taskMessage: verifyError,
          receivedBytes: receivedBytes,
        );
        return;
      }
    }

    final size = await file.length();
    if (size <= 0) {
      if (await file.exists()) {
        await file.delete();
      }
      _failUpload(
        response: request.response,
        taskId: taskId,
        incomingId: incoming.id,
        statusCode: HttpStatus.badRequest,
        errorCode: 'empty_file',
        taskMessage: '空文件',
      );
      return;
    }

    _delegate.updateTask(
      taskId,
      status: LanReceiveTaskStatus.pending,
      message: '等待导入',
      sizeBytes: size,
      bytesReceived: size,
    );
    _delegate.updateIncomingRequest(
      incoming.id,
      LanIncomingTransferRequestStatus.uploadedWaitImport,
      message: '等待导入',
      clearImportSummary: true,
    );

    writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'transferRequestId': incomingRequestId,
      'taskId': taskId,
      'syncEnvelopeId': incoming.syncEnvelopeId,
      'fileName': fileName,
      'sizeBytes': size,
      'signed': signedBodyMode,
    });
  }

  void _failUpload({
    required HttpResponse response,
    required String taskId,
    required String incomingId,
    required int statusCode,
    required String errorCode,
    required String taskMessage,
    int? receivedBytes,
  }) {
    _delegate.updateTask(
      taskId,
      status: LanReceiveTaskStatus.failed,
      message: taskMessage,
      sizeBytes: receivedBytes,
      bytesReceived: receivedBytes,
    );
    _delegate.updateIncomingRequest(
      incomingId,
      LanIncomingTransferRequestStatus.importFailed,
      message: taskMessage,
    );
    writeJson(response, statusCode, {
      'ok': false,
      'error': errorCode,
    });
  }

  Future<Map<String, dynamic>?> _decodeJsonBody(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        throw const FormatException('bad_body');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'bad_json',
      });
      return null;
    }
  }

  List<String> _parseNormalizedStringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, String> _parseStringMap(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    for (final entry in Map<String, dynamic>.from(raw).entries) {
      final key = entry.key.trim();
      final value = '${entry.value}'.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  Future<Directory> _getInboxDir() async {
    final tempDir = await getTemporaryDirectory();
    final inbox = Directory(p.join(tempDir.path, 'lan_sync_inbox'));
    if (!await inbox.exists()) {
      await inbox.create(recursive: true);
    }
    return inbox;
  }

  String _normalizePackageFileName(String? fileName) {
    final raw = (fileName ?? '').trim();
    final base = raw.isEmpty ? 'sync_package.cs2pkg' : p.basename(raw);
    final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return sanitized.toLowerCase().endsWith('.cs2pkg')
        ? sanitized
        : '$sanitized.cs2pkg';
  }

  void writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> body,
  ) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }
}
