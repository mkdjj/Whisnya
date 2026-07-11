import '../models/app_character.dart';
import '../models/chat_message.dart';
import 'prompt_builder.dart';

final class CharacterPromptBuilder {
  const CharacterPromptBuilder._();

  static String system(AppCharacter character) =>
      PromptBuilder.buildSystemPrompt(character);

  static List<Map<String, String>> request({
    required AppCharacter character,
    required String historySummary,
    required int summarizedMessageCount,
    required List<ChatMessage> messages,
    required bool useFullContext,
  }) => PromptBuilder.buildChatRequestMessages(
    character: character,
    historySummary: historySummary,
    summarizedMessageCount: summarizedMessageCount,
    messages: messages,
    useFullContext: useFullContext,
  );
}
