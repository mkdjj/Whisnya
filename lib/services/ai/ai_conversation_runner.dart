import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/ai_usage.dart';
import '../../models/ai_response.dart';

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

class OpenAiCompatibleAdapter {
  const OpenAiCompatibleAdapter();

  Uri buildModelsUri(String baseUrl) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    const suffix = '/chat/completions';
    final root = normalized.toLowerCase().endsWith(suffix)
        ? normalized.substring(0, normalized.length - suffix.length)
        : normalized;
    final uri = Uri.tryParse('$root/models');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AiException('Base URL 格式不正确。');
    }
    return uri;
  }

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

  List<String> parseModels(dynamic json) {
    if (json is! Map<String, dynamic> || json['data'] is! List) return const [];
    final seen = <String>{};
    return [
      for (final item in json['data'] as List)
        if (item is Map<String, dynamic> &&
            item['id'] is String &&
            (item['id'] as String).trim().isNotEmpty &&
            seen.add((item['id'] as String).trim()))
          (item['id'] as String).trim(),
    ];
  }

  ({String? text, AiUsage? usage})? parseStream(
    String line, {
    required bool includeReasoning,
  }) {
    final event = parseResponseDelta(line);
    if (event == null || (event.contentDelta.isEmpty && event.usage == null)) {
      return null;
    }
    return (
      text: event.contentDelta.isEmpty ? null : event.contentDelta,
      usage: event.usage,
    );
  }

  AiResponseDelta? parseResponseDelta(String line) {
    if (line.isEmpty) return null;
    final payload = line.startsWith('data:') ? line.substring(5).trim() : line;
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final usage = decoded['usage'] is Map<String, dynamic>
          ? AiUsage.fromJson(decoded['usage'])
          : null;
      String? text;
      var reasoning = '';
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final delta = first['delta'];
          if (delta is Map<String, dynamic>) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty) {
              text = content;
            }
            final rawReasoning = delta['reasoning_content'];
            if (rawReasoning is String) reasoning = rawReasoning;
          }
          final message = first['message'];
          if (text == null && message is Map<String, dynamic>) {
            final content = message['content'];
            if (content is String && content.isNotEmpty) text = content;
          }
          if (reasoning.isEmpty &&
              message is Map<String, dynamic> &&
              message['reasoning_content'] is String) {
            reasoning = message['reasoning_content'] as String;
          }
          final plainText = first['text'];
          if (text == null && plainText is String && plainText.isNotEmpty) {
            text = plainText;
          }
        }
      }
      return text == null && reasoning.isEmpty && usage == null
          ? null
          : AiResponseDelta(
              contentDelta: text ?? '',
              reasoningDelta: reasoning,
              usage: usage,
            );
    } on FormatException {
      return null;
    }
  }

  ({String text, AiUsage usage}) parseResponse(dynamic json) {
    final response = parseStructuredResponse(json);
    return (text: response.content, usage: response.usage);
  }

  AiResponse parseStructuredResponse(dynamic json) {
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
          return AiResponse(
            content: content.trim(),
            reasoningContent:
                message is Map<String, dynamic> &&
                    message['reasoning_content'] is String
                ? message['reasoning_content'] as String
                : '',
            usage: AiUsage.fromJson(json['usage']),
          );
        }
      }
    }
    throw AiException('API 没有返回可用回复。');
  }
}

String? selectAutomaticModel(List<String> models) {
  const excluded = [
    'embedding',
    'rerank',
    'tts',
    'whisper',
    'audio',
    'image',
    'moderation',
  ];
  final usable = models.where(
    (model) => !excluded.any(model.toLowerCase().contains),
  );
  if (usable.isEmpty) return models.firstOrNull;
  return usable.firstWhere((model) {
    final name = model.toLowerCase();
    return name.contains('chat') || name.contains('instruct');
  }, orElse: () => usable.first);
}

class AiConversationRunner {
  AiConversationRunner({
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  static const _adapter = OpenAiCompatibleAdapter();

  Future<List<String>> listModels({
    required String apiKey,
    required String baseUrl,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw AiException('API Key 为空，请先配置。');
    }
    if (baseUrl.trim().isEmpty) {
      throw AiException('Base URL 为空，请先配置。');
    }
    final response = await _client
        .get(
          _adapter.buildModelsUri(baseUrl),
          headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiException(
        'API 返回错误 ${response.statusCode}：${_extractError(response.body)}',
      );
    }
    try {
      final models = _adapter.parseModels(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      if (models.isEmpty) throw AiException('API 没有返回可用模型。');
      return models;
    } on FormatException {
      throw AiException('API 返回内容不是有效 JSON。');
    }
  }

  Future<({String text, AiUsage usage})> send(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    final response = await sendResponse(request, cancelToken: cancelToken);
    return (text: response.content, usage: response.usage);
  }

  Future<AiResponse> sendResponse(
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
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiException(
          'API 返回错误 ${response.statusCode}：${_extractError(response.body)}',
        );
      }
      try {
        return _adapter.parseStructuredResponse(
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

  Stream<({String? text, AiUsage? usage})> run(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) async* {
    await for (final event in streamResponse(
      request,
      cancelToken: cancelToken,
    )) {
      if (event.contentDelta.isNotEmpty || event.usage != null) {
        yield (
          text: event.contentDelta.isEmpty ? null : event.contentDelta,
          usage: event.usage,
        );
      }
    }
  }

  Stream<AiResponseDelta> streamResponse(
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
      final response = await client.send(httpRequest).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder
            .bind(response.stream.timeout(timeout))
            .join();
        throw AiException(
          'API 返回错误 ${response.statusCode}：${_extractError(body)}',
        );
      }
      await for (final line
          in response.stream
              .timeout(timeout)
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim() == 'data: [DONE]') break;
        final event = _adapter.parseResponseDelta(line.trim());
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
