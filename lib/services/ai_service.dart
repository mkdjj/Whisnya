import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_usage.dart';

export '../models/ai_usage.dart' show AiUsage;

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

  void _detach(http.Client client) {
    _clients.remove(client);
  }
}

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async {
    _validateConfig(apiKey: apiKey, baseUrl: baseUrl, model: model);
    _validateMaxTokens(maxTokens);

    final uri = buildChatCompletionsUri(baseUrl);
    final client = cancelToken == null ? _client : http.Client();
    cancelToken?._attach(client);
    final http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model.trim(),
              'messages': messages,
              'temperature': 0.8,
              'max_tokens': ?maxTokens,
            }),
          )
          .timeout(const Duration(seconds: 90));
    } finally {
      cancelToken?._detach(client);
      if (cancelToken != null) client.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiException(
        'API 返回错误 ${response.statusCode}：${_extractError(response.body)}',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw AiException('API 返回格式异常。');
      }
      onUsage?.call(AiUsage.fromJson(decoded['usage']));

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final message = first['message'];
          if (message is Map<String, dynamic>) {
            final content = message['content'];
            if (content is String && content.trim().isNotEmpty) {
              return content.trim();
            }
          }

          final text = first['text'];
          if (text is String && text.trim().isNotEmpty) {
            return text.trim();
          }
        }
      }
    } on FormatException catch (_) {
      throw AiException('API 返回内容不是有效 JSON。');
    }

    throw AiException('API 没有返回可用回复。');
  }

  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async* {
    _validateConfig(apiKey: apiKey, baseUrl: baseUrl, model: model);
    _validateMaxTokens(maxTokens);

    final uri = buildChatCompletionsUri(baseUrl);
    final client = cancelToken == null ? _client : http.Client();
    cancelToken?._attach(client);
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({
          'model': model.trim(),
          'messages': messages,
          'temperature': 0.8,
          'stream': true,
          'max_tokens': ?maxTokens,
        });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw AiException(
          'API 返回错误 ${response.statusCode}：${_extractError(body)}',
        );
      }

      var usageReported = false;
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final text = _extractStreamText(
          line.trim(),
          includeReasoning: includeReasoning,
          onUsage: onUsage == null
              ? null
              : (usage) {
                  usageReported = true;
                  onUsage(usage);
                },
        );
        if (text != null) yield text;
      }
      if (!usageReported) onUsage?.call(const AiUsage());
    } finally {
      cancelToken?._detach(client);
      if (cancelToken != null) client.close();
    }
  }

  Uri buildChatCompletionsUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw AiException('Base URL 为空，请先配置。');
    }

    final normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
    final lower = normalized.toLowerCase();
    final url = lower.endsWith('/chat/completions')
        ? normalized
        : '$normalized/chat/completions';

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AiException('Base URL 格式不正确。');
    }
    return uri;
  }

  void _validateConfig({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) {
    if (apiKey.trim().isEmpty) {
      throw AiException('API Key 为空，请先配置。');
    }
    if (baseUrl.trim().isEmpty) {
      throw AiException('Base URL 为空，请先配置。');
    }
    if (model.trim().isEmpty) {
      throw AiException('Model 为空，请先配置。');
    }
  }

  void _validateMaxTokens(int? maxTokens) {
    if (maxTokens != null && maxTokens <= 0) {
      throw AiException('maxTokens 必须大于 0。');
    }
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String) {
            return message;
          }
        }
        final message = decoded['message'];
        if (message is String) {
          return message;
        }
      }
    } on FormatException {
      // Fall through and show a clipped raw response body.
    }
    return body.length > 300 ? '${body.substring(0, 300)}...' : body;
  }

  String? _extractStreamText(
    String line, {
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) {
    if (line.isEmpty) return null;
    final payload = line.startsWith('data:') ? line.substring(5).trim() : line;
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded.containsKey('usage')) {
        onUsage?.call(AiUsage.fromJson(decoded['usage']));
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map<String, dynamic>) return null;
      final delta = first['delta'];
      if (delta is Map<String, dynamic>) {
        final content = delta['content'];
        if (content is String && content.isNotEmpty) return content;
        if (includeReasoning) {
          final reasoning = delta['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) return reasoning;
        }
      }
      final message = first['message'];
      if (message is Map<String, dynamic>) {
        final content = message['content'];
        if (content is String && content.isNotEmpty) return content;
      }
      final text = first['text'];
      if (text is String && text.isNotEmpty) return text;
    } on FormatException {
      return null;
    }
    return null;
  }
}
