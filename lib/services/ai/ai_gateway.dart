import '../../models/ai_usage.dart';
import 'ai_conversation_runner.dart';

abstract interface class AiGateway {
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  });

  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  });
}
