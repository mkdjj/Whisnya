import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';

final class CharacterChatService {
  const CharacterChatService(this.gateway);

  final AiGateway gateway;

  Stream<String> stream({
    required AiEndpointConfig endpoint,
    required List<Map<String, String>> messages,
    required AiCancelToken cancelToken,
    required bool includeReasoning,
    void Function(AiUsage usage)? onUsage,
  }) {
    return gateway.streamMessage(
      apiKey: endpoint.apiKey,
      baseUrl: endpoint.baseUrl,
      model: endpoint.model,
      messages: messages,
      cancelToken: cancelToken,
      includeReasoning: includeReasoning,
      maxTokens: 800,
      onUsage: onUsage,
    );
  }
}
