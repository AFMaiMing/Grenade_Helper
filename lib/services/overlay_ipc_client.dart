import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/overlay_snapshot.dart';

typedef OverlayCommandHandler = FutureOr<void> Function(
  String command,
  Map<String, dynamic>? args,
);
typedef VoidCallback = void Function();

// 悬浮窗子进程侧 WebSocket IPC 客户端
class OverlayIpcClient {
  static const Duration _initTimeout = Duration(seconds: 10);

  final int port;
  final String token;

  WebSocket? _socket;
  OverlayCommandHandler? onCommand;
  VoidCallback? onDisconnected;

  OverlayIpcClient({
    required this.port,
    required this.token,
  });

  static ({int port, String token})? parseArgs(List<String> args) {
    int? port;
    String? token;
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i] == '--port') {
        port = int.tryParse(args[i + 1]);
      } else if (args[i] == '--token') {
        token = args[i + 1];
      }
    }
    if (port == null || token == null || token.isEmpty) return null;
    return (port: port, token: token);
  }

  Future<OverlayInitConfig> connectAndAwaitInit() async {
    final uri = Uri(
      scheme: 'ws',
      host: '127.0.0.1',
      port: port,
      queryParameters: {'token': token},
    );

    final socket = await WebSocket.connect(uri.toString());
    _socket = socket;
    final initCompleter = Completer<OverlayInitConfig>();

    socket.listen(
      (raw) => _handleServerMessage(raw, initCompleter),
      onDone: () => _failInitAndDisconnect(
        initCompleter,
        StateError('IPC closed before init'),
      ),
      onError: (Object error) => _failInitAndDisconnect(initCompleter, error),
      cancelOnError: true,
    );

    return initCompleter.future.timeout(_initTimeout);
  }

  void sendEvent(String event, [Map<String, dynamic>? args]) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode({
      'event': event,
      if (args != null) 'args': args,
    }));
  }

  Future<void> close() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void _handleServerMessage(
    dynamic raw,
    Completer<OverlayInitConfig> initCompleter,
  ) {
    if (raw is! String) return;
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final cmd = decoded['cmd'] as String?;
    if (cmd == null) return;

    final args = decoded['args'] is Map
        ? Map<String, dynamic>.from(decoded['args'] as Map)
        : null;
    if (cmd == 'init' && !initCompleter.isCompleted && args != null) {
      initCompleter.complete(OverlayInitConfig.fromJson(args));
      return;
    }
    onCommand?.call(cmd, args);
  }

  void _failInitAndDisconnect(
    Completer<OverlayInitConfig> initCompleter,
    Object error,
  ) {
    if (!initCompleter.isCompleted) {
      initCompleter.completeError(error);
    }
    onDisconnected?.call();
  }
}
