import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/qq/local_bridge_server.dart';

void main() {
  late LocalQqBridgeServer server;

  tearDown(() async {
    await server.stop();
  });

  test('binds only IPv4 loopback and health reveals no private data', () async {
    server = _server();
    await server.start(port: 0, token: 'secret');

    expect(server.address, InternetAddress.loopbackIPv4);
    final response = await _request(server, 'GET', '/health');
    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(response.body), {'service': 'whisnya', 'qqBridgeApi': 1});
    expect(response.body, isNot(contains('secret')));
    expect(response.body, isNot(contains('allowUsers')));
  });

  test('requires protocol version and bearer auth outside health', () async {
    server = _server();
    await server.start(port: 0, token: 'secret');

    final missingVersion = await _request(
      server,
      'GET',
      '/v1/qq/config',
      headers: {HttpHeaders.authorizationHeader: 'Bearer secret'},
    );
    expect(missingVersion.statusCode, HttpStatus.upgradeRequired);

    final badAuth = await _request(
      server,
      'GET',
      '/v1/qq/config',
      headers: _headers(token: 'wrong'),
    );
    expect(badAuth.statusCode, HttpStatus.unauthorized);
  });

  test('serves the Whisnya-owned allowlist', () async {
    server = _server(
      config: () async =>
          const LocalQqBridgeConfig(enabled: true, allowUsers: ['123456789']),
    );
    await server.start(port: 0, token: 'secret');

    final response = await _request(
      server,
      'GET',
      '/v1/qq/config',
      headers: _headers(),
    );
    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(response.body), {
      'enabled': true,
      'allowUsers': ['123456789'],
    });
  });

  test('rejects oversized and invalid JSON bodies', () async {
    server = _server();
    await server.start(port: 0, token: 'secret');

    final oversized = await _request(
      server,
      'POST',
      '/v1/qq/message',
      headers: _headers(),
      body: jsonEncode({'text': 'x' * (64 * 1024)}),
    );
    expect(oversized.statusCode, HttpStatus.requestEntityTooLarge);

    final invalid = await _request(
      server,
      'POST',
      '/v1/qq/message',
      headers: _headers(),
      body: '{broken',
    );
    expect(invalid.statusCode, HttpStatus.badRequest);
  });

  test('returns 204 for unknown or disabled contacts', () async {
    server = _server(
      message: (_) async => const LocalQqBridgeMessageResult.noContent(),
    );
    await server.start(port: 0, token: 'secret');

    final response = await _messageRequest(server);
    expect(response.statusCode, HttpStatus.noContent);
  });

  test('returns reply metadata on success and 500 on AI failure', () async {
    var fail = false;
    server = _server(
      message: (_) async => fail
          ? const LocalQqBridgeMessageResult.failure('ai_failed')
          : const LocalQqBridgeMessageResult.reply(
              reply: 'hello',
              sessionId: 'session',
              bindingId: 'binding',
            ),
    );
    await server.start(port: 0, token: 'secret');

    final success = await _messageRequest(server);
    expect(success.statusCode, HttpStatus.ok);
    expect(jsonDecode(success.body), {
      'reply': 'hello',
      'sessionId': 'session',
      'bindingId': 'binding',
    });

    fail = true;
    final failure = await _messageRequest(server);
    expect(failure.statusCode, HttpStatus.internalServerError);
    expect(jsonDecode(failure.body), {'error': 'ai_failed'});
  });

  test('accepts bridge status without persisting heartbeat data', () async {
    LocalQqBridgeStatus? received;
    server = _server(status: (value) => received = value);
    await server.start(port: 0, token: 'secret');

    final response = await _request(
      server,
      'POST',
      '/v1/qq/status',
      headers: _headers(),
      body: jsonEncode({
        'connected': true,
        'selfId': '123',
        'nickname': 'Bot',
        'lastMessageAt': '2026-08-08T00:00:00Z',
        'lastError': null,
      }),
    );

    expect(response.statusCode, HttpStatus.noContent);
    expect(received?.connected, isTrue);
    expect(received?.selfId, '123');
    expect(server.bridgeOnline, isTrue);
    expect(server.lastHeartbeatAt, isNotNull);
  });
}

LocalQqBridgeServer _server({
  Future<LocalQqBridgeMessageResult> Function(LocalQqBridgeMessage)? message,
  Future<LocalQqBridgeConfig> Function()? config,
  void Function(LocalQqBridgeStatus? status)? status,
}) => LocalQqBridgeServer(
  onMessage:
      message ?? (_) async => const LocalQqBridgeMessageResult.noContent(),
  loadConfig:
      config ??
      () async => const LocalQqBridgeConfig(enabled: false, allowUsers: []),
  onStatusChanged: status,
);

Map<String, String> _headers({String token = 'secret'}) => {
  HttpHeaders.authorizationHeader: 'Bearer $token',
  HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
  'X-Whisnya-Bridge-Version': '1',
};

Future<_Response> _messageRequest(LocalQqBridgeServer server) => _request(
  server,
  'POST',
  '/v1/qq/message',
  headers: _headers(),
  body: jsonEncode({
    'source': 'onebot',
    'messageId': 'message',
    'userId': '123',
    'nickname': 'Alice',
    'text': 'hello',
    'timestamp': 1786110000,
  }),
);

Future<_Response> _request(
  LocalQqBridgeServer server,
  String method,
  String path, {
  Map<String, String> headers = const {},
  String? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    return _Response(
      response.statusCode,
      await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
