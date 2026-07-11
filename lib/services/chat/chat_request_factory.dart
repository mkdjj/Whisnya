import '../../models/app_character.dart';
import '../../models/chat_message.dart';
import '../../prompts.dart';

final class ChatRequestFactory {
  const ChatRequestFactory();

  List<Map<String, String>> build({
    required AppCharacter character,
    required String historySummary,
    required int summarizedMessageCount,
    required List<ChatMessage> messages,
  }) {
    return PromptBuilder.buildChatRequestMessages(
      character: character,
      historySummary: historySummary,
      summarizedMessageCount: summarizedMessageCount,
      messages: messages,
      useFullContext: character.useFullChatContext,
    );
  }
}
