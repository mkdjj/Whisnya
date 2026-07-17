import 'package:http/http.dart' as http;

import '../models/ai_usage.dart';
import 'ai/ai_gateway.dart';
import 'ai/ai_conversation_runner.dart';

export '../models/ai_usage.dart' show AiUsage;
export 'ai/ai_conversation_runner.dart'
    show AiCancelToken, AiException, AiRequest, AiStreamEvent;

class AiService implements AiGateway {
  AiService({http.Client? client})
    : _runner = AiConversationRunner(client: client);

  final AiConversationRunner _runner;

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async {
    final result = await _runner.send(
      AiRequest(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
      cancelToken: cancelToken,
    );
    onUsage?.call(result.usage);
    return result.text;
  }

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async* {
    var usageReported = false;
    await for (final event in _runner.run(
      AiRequest(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        temperature: temperature,
        stream: true,
        includeReasoning: includeReasoning,
        maxTokens: maxTokens,
      ),
      cancelToken: cancelToken,
    )) {
      final usage = event.usage;
      if (usage != null) {
        usageReported = true;
        onUsage?.call(usage);
      }
      final text = event.text;
      if (text != null) yield text;
    }
    if (!usageReported) onUsage?.call(const AiUsage());
  }

  Uri buildChatCompletionsUri(String baseUrl) {
    return const OpenAiCompatibleAdapter().buildUri(
      AiRequest(
        apiKey: 'unused',
        baseUrl: baseUrl,
        model: 'unused',
        messages: const [],
      ),
    );
  }
}
