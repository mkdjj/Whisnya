import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    _validateConfig(apiKey: apiKey, baseUrl: baseUrl, model: model);

    final uri = buildChatCompletionsUri(baseUrl);
    final response = await _client
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
          }),
        )
        .timeout(const Duration(seconds: 90));

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
}
