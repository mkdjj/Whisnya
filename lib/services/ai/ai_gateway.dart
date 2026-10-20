import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/ai_response.dart';
import 'ai_conversation_runner.dart';

/// One response API; text-only callers use the shared convenience methods.
abstract class AiGateway {
  Future<AiResponse> sendResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  });

  Stream<AiResponseDelta> streamResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  });

  Future<String> sendMessage({
    required AiEndpointConfig endpoint,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) async {
    final result = await sendResponse(
      AiRequest(
        endpoint: endpoint,
        messages: messages,
        temperature: temperature,
      ),
      cancelToken: cancelToken,
    );
    onUsage?.call(result.usage);
    return result.content;
  }

  Stream<String> streamMessage({
    required AiEndpointConfig endpoint,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) async* {
    await for (final event in streamResponse(
      AiRequest(
        endpoint: endpoint,
        messages: messages,
        temperature: temperature,
        stream: true,
        includeReasoning: includeReasoning,
      ),
      cancelToken: cancelToken,
    )) {
      final usage = event.usage;
      if (usage != null) {
        onUsage?.call(usage);
      }
      if (event.contentDelta.isNotEmpty) yield event.contentDelta;
    }
  }
}
