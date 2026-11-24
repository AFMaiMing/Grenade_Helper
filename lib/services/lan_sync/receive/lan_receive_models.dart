/// 局域网接收任务状态
enum LanReceiveTaskStatus { receiving, pending, importing, imported, failed }

/// 局域网传入传输请求状态
enum LanIncomingTransferRequestStatus {
  pending,
  approved,
  rejected,
  uploading,
  uploadedWaitImport,
  importing,
  imported,
  importFailed,
  importCancelled,
  expired
}

/// 局域网传入传输请求
class LanIncomingTransferRequest {
  final String id;
  final String fileName;
  final int sizeBytes;
  final DateTime requestedAt;
  final String? remoteAddress;
  final String senderName;
  final String scopeSummary;
  final String syncMode;
  final String scopeType;
  final List<String> scopeMapKeys;
  final String syncEnvelopeId;
  final String senderNodeId;
  final String receiverNodeId;
  final int packageSchemaVersion;
  final Map<String, String> baseMapBaselineIds;
  final LanIncomingTransferRequestStatus status;
  final String? message;
  final Map<String, dynamic>? importSummary;

  const LanIncomingTransferRequest({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.requestedAt,
    required this.status,
    this.remoteAddress,
    this.senderName = '',
    this.scopeSummary = '',
    this.syncMode = 'full',
    this.scopeType = 'all',
    this.scopeMapKeys = const [],
    this.syncEnvelopeId = '',
    this.senderNodeId = '',
    this.receiverNodeId = '',
    this.packageSchemaVersion = 3,
    this.baseMapBaselineIds = const {},
    this.message,
    this.importSummary,
  });

  LanIncomingTransferRequest copyWith({
    LanIncomingTransferRequestStatus? status,
    String? message,
    bool clearMessage = false,
    Map<String, dynamic>? importSummary,
    bool clearImportSummary = false,
  }) {
    return LanIncomingTransferRequest(
      id: id,
      fileName: fileName,
      sizeBytes: sizeBytes,
      requestedAt: requestedAt,
      remoteAddress: remoteAddress,
      senderName: senderName,
      scopeSummary: scopeSummary,
      syncMode: syncMode,
      scopeType: scopeType,
      scopeMapKeys: scopeMapKeys,
      syncEnvelopeId: syncEnvelopeId,
      senderNodeId: senderNodeId,
      receiverNodeId: receiverNodeId,
      packageSchemaVersion: packageSchemaVersion,
      baseMapBaselineIds: baseMapBaselineIds,
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
      importSummary:
          clearImportSummary ? null : (importSummary ?? this.importSummary),
    );
  }
}

/// 已接收同步包任务状态条目
class LanReceivedPackageTask {
  final String id;
  final String filePath;
  final String fileName;
  final int sizeBytes;
  final int bytesReceived;
  final int? expectedBytes;
  final String? transferRequestId;
  final String? syncEnvelopeId;
  final DateTime receivedAt;
  final String? remoteAddress;
  final LanReceiveTaskStatus status;
  final String? message;

  const LanReceivedPackageTask({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    this.bytesReceived = 0,
    this.expectedBytes,
    this.transferRequestId,
    this.syncEnvelopeId,
    required this.receivedAt,
    required this.status,
    this.remoteAddress,
    this.message,
  });

  LanReceivedPackageTask copyWith({
    LanReceiveTaskStatus? status,
    String? message,
    bool clearMessage = false,
    int? sizeBytes,
    int? bytesReceived,
    int? expectedBytes,
    bool clearExpectedBytes = false,
    String? transferRequestId,
    String? syncEnvelopeId,
  }) {
    return LanReceivedPackageTask(
      id: id,
      filePath: filePath,
      fileName: fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      expectedBytes:
          clearExpectedBytes ? null : (expectedBytes ?? this.expectedBytes),
      transferRequestId: transferRequestId ?? this.transferRequestId,
      syncEnvelopeId: syncEnvelopeId ?? this.syncEnvelopeId,
      receivedAt: receivedAt,
      remoteAddress: remoteAddress,
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  double? get progress {
    final total = expectedBytes;
    if (total == null || total <= 0) return null;
    final ratio = bytesReceived / total;
    if (ratio.isNaN) return null;
    return ratio.clamp(0.0, 1.0);
  }
}
