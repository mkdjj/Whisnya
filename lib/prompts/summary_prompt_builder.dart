import '../models/app_settings.dart';
import '../models/chat_message.dart';
import 'prompt_builder.dart';

final class SummaryPromptBuilder {
  const SummaryPromptBuilder._();

  static String character(
    List<ChatMessage> messages, {
    bool useCustomItems = false,
    List<String> customItems = AppSettings.defaultChatSummaryItems,
  }) => PromptBuilder.buildSummaryPrompt(
    messages,
    useCustomItems: useCustomItems,
    customItems: customItems,
  );

  static String rolling({
    required String previousSummary,
    required List<ChatMessage> newMessages,
    bool useCustomItems = false,
    List<String> customItems = AppSettings.defaultChatSummaryItems,
  }) => PromptBuilder.buildRollingSummaryPrompt(
    previousSummary: previousSummary,
    newMessages: newMessages,
    useCustomItems: useCustomItems,
    customItems: customItems,
  );
}
