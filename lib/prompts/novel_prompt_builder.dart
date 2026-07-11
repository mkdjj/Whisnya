import '../models/chat_message.dart';
import '../models/novel_book.dart';
import 'prompt_builder.dart';

final class NovelPromptBuilder {
  const NovelPromptBuilder._();

  static String chunk(String text, int index, int total) =>
      PromptBuilder.buildNovelChunkPrompt(text, index, total);

  static String merge(List<String> summaries) =>
      PromptBuilder.buildNovelMergePrompt(summaries);

  static List<Map<String, String>> chat({
    required NovelBook book,
    required NovelRoleCandidate aiRole,
    required NovelRoleCandidate? userRole,
    required String historySummary,
    required int summarizedMessageCount,
    required List<ChatMessage> messages,
  }) => PromptBuilder.buildNovelChatRequestMessages(
    book: book,
    aiRole: aiRole,
    userRole: userRole,
    historySummary: historySummary,
    summarizedMessageCount: summarizedMessageCount,
    messages: messages,
  );
}
