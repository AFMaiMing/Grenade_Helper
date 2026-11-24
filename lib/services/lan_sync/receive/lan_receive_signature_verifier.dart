import 'dart:io';

import '../lan_sync_auth.dart';

/// 局域网上传请求的 HMAC 签名与防重放校验器
class LanReceiveSignatureVerifier {
  static const Duration _maxClockSkew = Duration(minutes: 5);
  static const Duration _nonceTtl = Duration(minutes: 10);

  final Map<String, int> _nonceSeenAt = <String, int>{};

  void _cleanupNonceCache(int nowMs) {
    final expiryBefore = nowMs - _nonceTtl.inMilliseconds;
    _nonceSeenAt.removeWhere((_, ts) => ts < expiryBefore);
  }

  String? verifyUploadSignature({
    required String method,
    required String path,
    required List<int> bodyBytes,
    required HttpHeaders headers,
    required Map<String, String> trustedPeerSecrets,
  }) {
    final peerId = headers.value('x-lan-peer-id')?.trim() ?? '';
    final tsRaw = headers.value('x-lan-ts')?.trim() ?? '';
    final nonce = headers.value('x-lan-nonce')?.trim() ?? '';
    final bodyShaHeader = headers.value('x-lan-body-sha256')?.trim() ?? '';
    final sign = headers.value('x-lan-sign')?.trim() ?? '';

    if (peerId.isEmpty ||
        tsRaw.isEmpty ||
        nonce.isEmpty ||
        bodyShaHeader.isEmpty ||
        sign.isEmpty) {
      return 'missing_signature_headers';
    }

    final ts = int.tryParse(tsRaw);
    if (ts == null) return 'invalid_timestamp';
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - ts).abs() > _maxClockSkew.inMilliseconds) {
      return 'timestamp_out_of_range';
    }

    _cleanupNonceCache(now);
    final nonceKey = '$peerId|$nonce';
    if (_nonceSeenAt.containsKey(nonceKey)) {
      return 'replayed_nonce';
    }

    final secret = trustedPeerSecrets[peerId];
    if (secret == null || secret.trim().isEmpty) {
      return 'unknown_peer';
    }

    final actualBodySha = LanSyncAuth.sha256Hex(bodyBytes);
    if (!LanSyncAuth.constantTimeEquals(bodyShaHeader, actualBodySha)) {
      return 'body_hash_mismatch';
    }

    final payload = LanSyncAuth.buildSigningPayload(
      method: method,
      path: path,
      timestampMs: tsRaw,
      nonce: nonce,
      bodySha256: bodyShaHeader,
      peerId: peerId,
    );
    final expectedSign =
        LanSyncAuth.hmacSha256Hex(secret: secret, payload: payload);
    if (!LanSyncAuth.constantTimeEquals(sign, expectedSign)) {
      return 'bad_signature';
    }

    _nonceSeenAt[nonceKey] = now;
    return null;
  }
}
