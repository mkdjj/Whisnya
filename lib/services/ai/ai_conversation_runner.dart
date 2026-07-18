import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/ai_usage.dart';

class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiCancelToken {
  final _clients = <http.Client>{};
  var _cancelled = false;

  void cancel() {
    _cancelled = true;
    for (final client in [..._clients]) {
      client.close();
    }
    _clients.clear();
  }

  void _attach(http.Client client) {
    if (_cancelled) {
      client.close();
      throw AiException('请求已取消。');
    }
    _clients.add(client);
  }

  void _detach(http.Client client) => _clients.remove(client);
}

class AiRequest {
  const AiRequest({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.messages,
    this.stream = false,
    this.includeReasoning = false,
    this.temperature = 0.8,
  });

  final String apiKey;
  final String baseUrl;
  final String model;
  final List<Map<String, String>> messages;
  final bool stream;
  final bool includeReasoning;
  final double temperature;
}

class AiStreamEvent {
  const AiStreamEvent({this.text, this.usage});

  final String? text;
  final AiUsage? usage;
}

class AiRunResult {
  const AiRunResult({required this.text, required this.usage});

  final String text;
  final AiUsage usage;
}

class OpenAiCompatibleAdapter {
  const OpenAiCompatibleAdapter();

  Uri buildUri(AiRequest request) {
    final normalized = request.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = normalized.toLowerCase().endsWith('/chat/completions')
        ? normalized
        : '$normalized/chat/completions';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AiException('Base URL 格式不正确。');
    }
    return uri;
  }

  Map<String, String> buildHeaders(AiRequest request) => {
    'Authorization': 'Bearer ${request.apiKey.trim()}',
    'Content-Type': 'application/json',
  };

  Map<String, dynamic> buildBody(AiRequest request) => {
    'model': request.model.trim(),
    'messages': request.messages,
    'temperature': request.temperature,
    if (request.stream) 'stream': true,
  };

  AiStreamEvent? parseStream(String line, {required bool includeReasoning}) {
    if (line.isEmpty) return null;
    final payload = line.startsWith('data:') ? line.substring(5).trim() : line;
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final usage = decoded.containsKey('usage')
          ? AiUsage.fromJson(decoded['usage'])
          : null;
      String? text;
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final delta = first['delta'];
          if (delta is Map<String, dynamic>) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty) {
              text = content;
            } else if (includeReasoning) {
              final reasoning = delta['reasoning_content'];
              if (reasoning is String && reasoning.isNotEmpty) text = reasoning;
            }
          }
          final message = first['message'];
          if (text == null && message is Map<String, dynamic>) {
            final content = message['content'];
            if (content is String && content.isNotEmpty) text = content;
          }
          final plainText = first['text'];
          if (text == null && plainText is String && plainText.isNotEmpty) {
            text = plainText;
          }
        }
      }
      return text == null && usage == null
          ? null
          : AiStreamEvent(text: text, usage: usage);
    } on FormatException {
      return null;
    }
  }

  AiRunResult parseResponse(dynamic json) {
    if (json is! Map<String, dynamic>) {
      throw AiException('API 返回格式异常。');
    }
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        var content = message is Map<String, dynamic>
            ? message['content']
            : null;
        if (content is! String || content.trim().isEmpty) {
          content = first['text'];
        }
        if (content is String && content.trim().isNotEmpty) {
          return AiRunResult(
            text: content.trim(),
            usage: AiUsage.fromJson(json['usage']),
          );
        }
      }
    }
    throw AiException('API 没有返回可用回复。');
  }
}

class AiConversationRunner {
  AiConversationRunner({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static const _adapter = OpenAiCompatibleAdapter();

  Future<AiRunResult> send(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    _validate(request);
    final client = cancelToken == null ? _client : http.Client();
    cancelToken?._attach(client);
    try {
      final response = await client
          .post(
            _adapter.buildUri(request),
            headers: _adapter.buildHeaders(request),
            body: jsonEncode(_adapter.buildBody(request)),
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiException(
          'API 返回错误 ${response.statusCode}：${_extractError(response.body)}',
        );
      }
      try {
        return _adapter.parseResponse(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
      } on FormatException {
        throw AiException('API 返回内容不是有效 JSON。');
      }
    } finally {
      cancelToken?._detach(client);
      if (cancelToken != null) client.close();
    }
  }

  Stream<AiStreamEvent> run(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) async* {
    _validate(request);
    final client = cancelToken == null ? _client : http.Client();
    cancelToken?._attach(client);
    try {
      final httpRequest = http.Request('POST', _adapter.buildUri(request))
        ..headers.addAll(_adapter.buildHeaders(request))
        ..body = jsonEncode(_adapter.buildBody(request));
      final response = await client
          .send(httpRequest)
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw AiException(
          'API 返回错误 ${response.statusCode}：${_extractError(body)}',
        );
      }
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final event = _adapter.parseStream(
          line.trim(),
          includeReasoning: request.includeReasoning,
        );
        if (event != null) yield event;
      }
    } finally {
      cancelToken?._detach(client);
      if (cancelToken != null) client.close();
    }
  }

  void _validate(AiRequest request) {
    if (request.apiKey.trim().isEmpty) {
      throw AiException('API Key 为空，请先配置。');
    }
    if (request.baseUrl.trim().isEmpty) {
      throw AiException('Base URL 为空，请先配置。');
    }
    if (request.model.trim().isEmpty) {
      throw AiException('Model 为空，请先配置。');
    }
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['message'] is String) {
          return error['message'] as String;
        }
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } on FormatException {
      // Return a clipped raw response below.
    }
    return body.length > 300 ? '${body.substring(0, 300)}...' : body;
  }
}
