// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../models/qq_bridge_status.dart';
import '../../../models/unified_qq_message.dart';
import '../qq_exceptions.dart';
import 'onebot_action_client.dart';
import 'onebot_event_parser.dart';
import 'onebot_reconnect_policy.dart';

class OneBotLoginInfo {
  const OneBotLoginInfo({required this.accountId, required this.nickname});
  final String accountId;
  final String nickname;
}

class OneBotClient {
  OneBotClient({
    this.actionTimeout = const Duration(seconds: 15),
    OneBotReconnectPolicy? reconnectPolicy,
  }) : _reconnectPolicy = reconnectPolicy ?? OneBotReconnectPolicy();

  final Duration actionTimeout;
  final OneBotReconnectPolicy _reconnectPolicy;
  // Both controllers are closed by dispose().
  final _messages = StreamController<UnifiedQqMessage>.broadcast();
  final _states = StreamController<QqConnectionState>.broadcast();
  WebSocket? _socket;
  OneBotActionClient? _actions;
  Completer<void>? _closed;
  var _stopRequested = false;
  QqConnectionState _state = QqConnectionState.stopped;

  Stream<UnifiedQqMessage> get messages => _messages.stream;
  Stream<QqConnectionState> get states => _states.stream;
  QqConnectionState get state => _state;
  bool get isConnected => _state == QqConnectionState.connected;

  Future<OneBotLoginInfo> connect(Uri uri, {String accessToken = ''}) async {
    _stopRequested = false;
    return _connectOnce(uri, accessToken: accessToken);
  }

  Future<void> start({
    required Uri uri,
    String accessToken = '',
    bool autoReconnect = true,
    void Function(OneBotLoginInfo info)? onConnected,
  }) async {
    _stopRequested = false;
    while (!_stopRequested) {
      final connectedAt = DateTime.now();
      try {
        final info = await _connectOnce(uri, accessToken: accessToken);
        onConnected?.call(info);
        await (_closed?.future ?? Future<void>.value());
        if (_stopRequested || !autoReconnect) break;
        if (DateTime.now().difference(connectedAt) >=
            const Duration(seconds: 60)) {
          _reconnectPolicy.reset();
        }
      } on OneBotAuthenticationException {
        _setState(QqConnectionState.authenticationFailed);
        break;
      } on FormatException {
        _setState(QqConnectionState.error);
        break;
      } on Object {
        if (_stopRequested || !autoReconnect) break;
      }
      _setState(QqConnectionState.reconnecting);
      await Future<void>.delayed(_reconnectPolicy.nextDelay());
    }
    if (_stopRequested) _setState(QqConnectionState.stopped);
  }

  Future<OneBotLoginInfo> _connectOnce(
    Uri uri, {
    required String accessToken,
  }) async {
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      throw const FormatException('OneBot URL 必须使用 ws 或 wss。');
    }
    await _closeSocket();
    _setState(QqConnectionState.connecting);
    try {
      _socket = await WebSocket.connect(
        uri.toString(),
        headers: accessToken.trim().isEmpty
            ? null
            : {HttpHeaders.authorizationHeader: 'Bearer ${accessToken.trim()}'},
      );
    } on WebSocketException catch (error) {
      final message = error.message;
      if (error.httpStatusCode == HttpStatus.unauthorized ||
          error.httpStatusCode == HttpStatus.forbidden ||
          message.contains('401') ||
          message.contains('403')) {
        throw const OneBotAuthenticationException('OneBot token 鉴权失败。');
      }
      throw const OneBotConnectionException('无法连接 OneBot WebSocket。');
    } on SocketException {
      throw const OneBotConnectionException('无法连接 OneBot WebSocket。');
    }
    _closed = Completer<void>();
    _actions = OneBotActionClient(
      timeout: actionTimeout,
      sendJson: (value) {
        final socket = _socket;
        if (socket == null) {
          throw const OneBotConnectionException('OneBot 连接已关闭。');
        }
        socket.add(jsonEncode(value));
      },
    );
    _socket!.listen(
      _handleRawMessage,
      onDone: _handleClosed,
      onError: (_) => _handleClosed(),
      cancelOnError: true,
    );
    try {
      final data = await _actions!.call('get_login_info');
      final accountId = data['user_id']?.toString().trim() ?? '';
      if (accountId.isEmpty) {
        throw const OneBotActionException('get_login_info 未返回 QQ 账号。');
      }
      final info = OneBotLoginInfo(
        accountId: accountId,
        nickname: data['nickname']?.toString().trim() ?? '',
      );
      _setState(QqConnectionState.connected);
      return info;
    } on Object {
      await _closeSocket();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> callAction(
    String action, {
    Map<String, dynamic> params = const {},
  }) {
    final actions = _actions;
    if (actions == null || !isConnected) {
      throw const OneBotConnectionException('OneBot 尚未连接。');
    }
    return actions.call(action, params: params);
  }

  Future<void> sendPrivateMessage(String userId, String text) async {
    await callAction(
      'send_private_msg',
      params: {'user_id': userId, 'message': text},
    );
  }

  Future<void> disconnect() async {
    _stopRequested = true;
    await _closeSocket();
    _setState(QqConnectionState.stopped);
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _states.close();
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    _socket = null;
    _actions?.cancelAll();
    _actions = null;
    if (socket != null) {
      try {
        await socket.close();
      } on Object {
        // The peer may already be gone.
      }
    }
    _completeClosed();
  }

  void _handleRawMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      if (_actions?.handleResponse(decoded) == true) return;
      final message = OneBotEventParser.parse(decoded);
      if (message != null) _messages.add(message);
    } on FormatException {
      // Invalid remote JSON is ignored and never written to diagnostics raw.
    }
  }

  void _handleClosed() {
    _socket = null;
    _actions?.cancelAll();
    _actions = null;
    _completeClosed();
    if (!_stopRequested) _setState(QqConnectionState.error);
  }

  void _completeClosed() {
    final closed = _closed;
    if (closed != null && !closed.isCompleted) closed.complete();
  }

  void _setState(QqConnectionState value) {
    if (_state == value) return;
    _state = value;
    _states.add(value);
  }
}
