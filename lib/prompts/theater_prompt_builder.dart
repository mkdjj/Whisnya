import '../models/app_settings.dart';
import '../models/theater.dart';
import 'prompt_builder.dart';

final class TheaterPromptBuilder {
  const TheaterPromptBuilder._();

  static String summary({
    required String previousSummary,
    required List<TheaterMessage> messages,
    bool useCustomItems = false,
    List<String> customItems = AppSettings.defaultTheaterSummaryItems,
  }) => PromptBuilder.buildTheaterSummaryPrompt(
    previousSummary: previousSummary,
    messages: messages,
    useCustomItems: useCustomItems,
    customItems: customItems,
  );

  static List<TheaterReplyDraft> parseReplies(String raw) =>
      PromptBuilder.parseTheaterReplies(raw);
}
