import '../../models/ai_usage.dart';
import '../../models/chat_message.dart';
import '../../models/novel_book.dart';
import '../../prompts.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';

class NovelChatService {
  const NovelChatService(this._gateway);

  final AiGateway _gateway;

  Stream<String> streamReply({
    required NovelBook book,
    required NovelRoleCandidate aiRole,
    NovelRoleCandidate? userRole,
    required String historySummary,
    required int summarizedMessageCount,
    required List<ChatMessage> messages,
    required String apiKey,
    required String baseUrl,
    required String model,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) {
    return _gateway.streamMessage(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      messages: PromptBuilder.buildNovelChatRequestMessages(
        book: book,
        aiRole: aiRole,
        userRole: userRole,
        historySummary: historySummary,
        summarizedMessageCount: summarizedMessageCount,
        messages: messages,
      ),
      cancelToken: cancelToken,
      includeReasoning: includeReasoning,
      onUsage: onUsage,
    );
  }
}
