import 'dart:async';
import 'dart:convert';
import 'dart:io';

const localQqBridgeProtocolVersion = '1';
const localQqBridgeDefaultPort = 17891;
const _maximumBodyBytes = 64 * 1024;

class LocalQqBridgeMessage {
  const LocalQqBridgeMessage({
    required this.messageId,
    required this.userId,
    required this.nickname,
    required this.text,
    required this.timestamp,
  });

  final String messageId;
  final String userId;
  final String nickname;
  final String text;
  final int timestamp;

  factory LocalQqBridgeMessage.fromJson(Map<String, dynamic> json) {
    if (json['source'] != 'onebot' ||
        json['messageId'] is! String ||
        json['userId'] is! String ||
        json['nickname'] is! String ||
        json['text'] is! String ||
        json['timestamp'] is! num) {
      throw const FormatException('Invalid QQ bridge message');
    }
    final messageId = (json['messageId'] as String).trim();
    final userId = (json['userId'] as String).trim();
    final text = (json['text'] as String).trim();
    if (messageId.isEmpty || userId.isEmpty || text.isEmpty) {
      throw const FormatException('QQ bridge message fields are empty');
    }
    return LocalQqBridgeMessage(
      messageId: messageId,
      userId: userId,
      nickname: (json['nickname'] as String).trim(),
      text: text,
      timestamp: (json['timestamp'] as num).toInt(),
    );
  }
}

class LocalQqBridgeStatus {
  const LocalQqBridgeStatus({
    required this.connected,
    required this.selfId,
    required this.nickname,
    required this.lastMessageAt,
    required this.lastError,
  });

  final bool connected;
  final String selfId;
  final String nickname;
  final DateTime? lastMessageAt;
  final String? lastError;

  factory LocalQqBridgeStatus.fromJson(Map<String, dynamic> json) {
    if (json['connected'] is! bool ||
        json['selfId'] is! String ||
        json['nickname'] is! String ||
        (json['lastMessageAt'] != null && json['lastMessageAt'] is! String) ||
        (json['lastError'] != null && json['lastError'] is! String)) {
      throw const FormatException('Invalid QQ bridge status');
    }
    final rawLastMessage = json['lastMessageAt'] as String?;
    final parsedLastMessage = rawLastMessage == null || rawLastMessage.isEmpty
        ? null
        : DateTime.tryParse(rawLastMessage);
    if (rawLastMessage != null &&
        rawLastMessage.isNotEmpty &&
        parsedLastMessage == null) {
      throw const FormatException('Invalid QQ bridge message time');
    }
    return LocalQqBridgeStatus(
      connected: json['connected'] as bool,
      selfId: (json['selfId'] as String).trim(),
      nickname: (json['nickname'] as String).trim(),
      lastMessageAt: parsedLastMessage,
      lastError: (json['lastError'] as String?)?.trim(),
    );
  }
}

class LocalQqBridgeConfig {
  const LocalQqBridgeConfig({required this.enabled, required this.allowUsers});

  final bool enabled;
  final List<String> allowUsers;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'allowUsers': allowUsers,
  };
}

enum LocalQqBridgeMessageDisposition { noContent, reply, failure }

class LocalQqBridgeMessageResult {
  const LocalQqBridgeMessageResult.noContent()
    : disposition = LocalQqBridgeMessageDisposition.noContent,
      reply = '',
      replies = const [],
      sessionId = '',
      bindingId = '',
      error = '';

  const LocalQqBridgeMessageResult.reply({
    required this.reply,
    required this.replies,
    required this.sessionId,
    required this.bindingId,
  }) : disposition = LocalQqBridgeMessageDisposition.reply,
       error = '';

  const LocalQqBridgeMessageResult.failure(this.error)
    : disposition = LocalQqBridgeMessageDisposition.failure,
      reply = '',
      replies = const [],
      sessionId = '',
      bindingId = '';

  final LocalQqBridgeMessageDisposition disposition;
  final String reply;
  final List<String> replies;
  final String sessionId;
  final String bindingId;
  final String error;
}

typedef LocalQqBridgeMessageHandler =
    Future<LocalQqBridgeMessageResult> Function(LocalQqBridgeMessage message);
typedef LocalQqBridgeConfigLoader = Future<LocalQqBridgeConfig> Function();
typedef LocalQqBridgeStatusHandler = void Function(LocalQqBridgeStatus? status);

class LocalQqBridgeServer {
  LocalQqBridgeServer({
    required this.onMessage,
    required this.loadConfig,
    this.onStatusChanged,
  });

  final LocalQqBridgeMessageHandler onMessage;
  final LocalQqBridgeConfigLoader loadConfig;
  final LocalQqBridgeStatusHandler? onStatusChanged;

  HttpServer? _server;
  String _token = '';
  Timer? _heartbeatExpiry;
  LocalQqBridgeStatus? _lastStatus;
  DateTime? _lastHeartbeatAt;

  bool get isRunning => _server != null;
  bool get bridgeOnline =>
      isRunning &&
      _lastHeartbeatAt != null &&
      DateTime.now().difference(_lastHeartbeatAt!) <
          const Duration(seconds: 90);
  InternetAddress? get address => _server?.address;
  int get port => _server?.port ?? 0;
  LocalQqBridgeStatus? get lastStatus => _lastStatus;
  DateTime? get lastHeartbeatAt => _lastHeartbeatAt;

  Future<void> start({required int port, required String token}) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw ArgumentError.value(token, 'token', 'must not be empty');
    }
    if (isRunning) await stop();
    _token = normalizedToken;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> stop() async {
    _heartbeatExpiry?.cancel();
    _heartbeatExpiry = null;
    _lastHeartbeatAt = null;
    _lastStatus = null;
    _token = '';
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
    onStatusChanged?.call(null);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _json(request.response, HttpStatus.ok, const {
          'service': 'whisnya',
          'qqBridgeApi': 1,
        });
        return;
      }
      if (request.headers.value('X-Whisnya-Bridge-Version') !=
          localQqBridgeProtocolVersion) {
        await _json(request.response, HttpStatus.upgradeRequired, const {
          'error': 'unsupported_protocol',
        });
        return;
      }
      if (!_authorized(request)) {
        await _json(request.response, HttpStatus.unauthorized, const {
          'error': 'unauthorized',
        });
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/v1/qq/config') {
        await _json(
          request.response,
          HttpStatus.ok,
          (await loadConfig()).toJson(),
        );
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/v1/qq/message') {
        await _handleMessage(request);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/v1/qq/status') {
        await _handleStatus(request);
        return;
      }
      await _json(request.response, HttpStatus.notFound, const {
        'error': 'not_found',
      });
    } on _BodyTooLarge {
      await _json(request.response, HttpStatus.requestEntityTooLarge, const {
        'error': 'body_too_large',
      });
    } on FormatException {
      await _json(request.response, HttpStatus.badRequest, const {
        'error': 'invalid_json',
      });
    } on Object {
      try {
        await _json(request.response, HttpStatus.internalServerError, const {
          'error': 'internal_error',
        });
      } on Object {
        await request.response.close();
      }
    }
  }

  Future<void> _handleMessage(HttpRequest request) async {
    final message = LocalQqBridgeMessage.fromJson(await _readJson(request));
    final result = await onMessage(message);
    switch (result.disposition) {
      case LocalQqBridgeMessageDisposition.noContent:
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      case LocalQqBridgeMessageDisposition.reply:
        await _json(request.response, HttpStatus.ok, {
          'reply': result.reply,
          'replies': result.replies,
          'sessionId': result.sessionId,
          'bindingId': result.bindingId,
        });
        return;
      case LocalQqBridgeMessageDisposition.failure:
        await _json(request.response, HttpStatus.internalServerError, {
          'error': result.error.isEmpty ? 'qq_processing_failed' : result.error,
        });
        return;
    }
  }

  Future<void> _handleStatus(HttpRequest request) async {
    final status = LocalQqBridgeStatus.fromJson(await _readJson(request));
    _lastStatus = status;
    _lastHeartbeatAt = DateTime.now();
    _heartbeatExpiry?.cancel();
    _heartbeatExpiry = Timer(const Duration(seconds: 90), () {
      _lastHeartbeatAt = null;
      _lastStatus = null;
      onStatusChanged?.call(null);
    });
    onStatusChanged?.call(status);
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType?.mimeType != ContentType.json.mimeType) {
      throw const FormatException('Expected application/json');
    }
    final declaredLength = request.contentLength;
    var tooLarge = declaredLength > _maximumBodyBytes;
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > _maximumBodyBytes) {
        tooLarge = true;
        continue;
      }
      if (!tooLarge) bytes.addAll(chunk);
    }
    if (tooLarge) throw const _BodyTooLarge();
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return value;
  }

  bool _authorized(HttpRequest request) {
    final value = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    return _constantTimeEquals(value, 'Bearer $_token');
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, dynamic> value,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
    await response.close();
  }
}

bool _constantTimeEquals(String first, String second) {
  final a = utf8.encode(first);
  final b = utf8.encode(second);
  var difference = a.length ^ b.length;
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    difference |=
        (index < a.length ? a[index] : 0) ^ (index < b.length ? b[index] : 0);
  }
  return difference == 0;
}

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}
