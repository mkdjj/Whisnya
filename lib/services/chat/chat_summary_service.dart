import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/app_settings.dart';
import '../../models/chat_message.dart';
import '../../models/chat_summary.dart';
import '../../prompts.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';

typedef ChatSummaryUsageCallback =
    void Function(AiUsage usage, List<Map<String, String>> messages);

ChatSummary chatSummaryAfterMessageDeletion({
  required ChatSummary summary,
  required List<ChatMessage> messages,
  required int index,
}) {
  if (index < 0 ||
      index >= messages.length ||
      summary.summary.trim().isEmpty ||
      summary.summarizedMessageCount <= 0) {
    return summary;
  }
  final removed = messages[index];
  if (!removed.isUser && !removed.isAssistant) return summary;
  final chatIndex = messages
      .take(index)
      .where((message) => message.isUser || message.isAssistant)
      .length;
  return chatIndex < summary.summarizedMessageCount
      ? ChatSummary.empty(summary.characterId)
      : summary;
}

final class ChatSummaryService {
  const ChatSummaryService(this.gateway);

  final AiGateway gateway;

  Future<ChatSummary?> update({
    required String characterId,
    required ChatSummary current,
    required List<ChatMessage> messages,
    required int summaryLimit,
    required AppSettings settings,
    required AiEndpointConfig endpoint,
    required AiCancelToken cancelToken,
    ChatSummaryUsageCallback? onUsage,
  }) async {
    final chatMessages = messages
        .where((message) => message.isUser || message.isAssistant)
        .toList();
    if (chatMessages.length <= summaryLimit) return null;

    final end = PromptBuilder.rollingSummaryEndIndex(
      messageCount: chatMessages.length,
      summaryLimit: summaryLimit,
    );
    final start = current.summarizedMessageCount.clamp(0, end).toInt();
    if (start >= end) return null;

    final request = <Map<String, String>>[
      {'role': 'system', 'content': '你负责总结聊天记录，并只输出总结内容。'},
      {
        'role': 'user',
        'content': PromptBuilder.buildRollingSummaryPrompt(
          previousSummary: current.summary,
          newMessages: chatMessages.sublist(start, end),
          useCustomItems: settings.useCustomChatSummaryItems,
          customItems: settings.customChatSummaryItems,
        ),
      },
    ];
    final text = await gateway.sendMessage(
      apiKey: endpoint.apiKey,
      baseUrl: endpoint.baseUrl,
      model: endpoint.model,
      messages: request,
      temperature: 0.2,
      cancelToken: cancelToken,
      maxTokens: 800,
      onUsage: onUsage == null ? null : (usage) => onUsage(usage, request),
    );
    return ChatSummary(
      characterId: characterId,
      summary: PromptBuilder.limitSummary(text, 1500),
      updatedAt: DateTime.now(),
      summarizedMessageCount: end,
    );
  }
}
