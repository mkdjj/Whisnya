import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/theater.dart';
import '../../prompts/prompt_builder.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';
import 'theater_reply_engine.dart';

({String summary, int summarizedMessageCount})
theaterSummaryAfterMessageDeletion({
  required String summary,
  required int summarizedMessageCount,
  required List<TheaterMessage> messages,
  required int index,
}) {
  if (index < 0 ||
      index >= messages.length ||
      summary.trim().isEmpty ||
      summarizedMessageCount <= 0 ||
      index >= summarizedMessageCount) {
    return (summary: summary, summarizedMessageCount: summarizedMessageCount);
  }
  if (isValidTheaterContextMessage(messages[index])) {
    return (summary: '', summarizedMessageCount: 0);
  }
  return (summary: summary, summarizedMessageCount: summarizedMessageCount - 1);
}

Future<({String summary, int summarizedMessageCount, AiUsage usage})?>
summarizeTheater(
  AiGateway gateway, {
  required TheaterSession session,
  required List<TheaterMessage> messages,
  required AiEndpointConfig endpoint,
  bool useCustomItems = false,
  List<String> customItems = const [],
  AiCancelToken? cancelToken,
  void Function(AiUsage usage, List<Map<String, String>> request)? onUsage,
}) async {
  final end = theaterSummaryEndIndex(
    messages: messages,
    summarizedMessageCount: session.summarizedMessageCount,
    messageBatchSize: session.recentMessageLimit,
    roundBatchSize: session.keepRoundCount,
  );
  final start = session.summarizedMessageCount.clamp(0, end).toInt();
  if (start >= end) return null;
  final chunk = messages
      .sublist(start, end)
      .where(isValidTheaterContextMessage)
      .toList();
  if (chunk.isEmpty) return null;

  final request = [
    {'role': 'system', 'content': '你负责总结群聊记录，并只输出总结内容。'},
    {
      'role': 'user',
      'content': PromptBuilder.buildTheaterSummaryPrompt(
        previousSummary: session.theaterSummary,
        messages: chunk,
        useCustomItems: useCustomItems,
        customItems: customItems,
      ),
    },
  ];
  var usage = const AiUsage();
  final summary = await gateway.sendMessage(
    apiKey: endpoint.apiKey,
    baseUrl: endpoint.baseUrl,
    model: endpoint.model,
    messages: request,
    temperature: 0.2,
    cancelToken: cancelToken,
    onUsage: (value) {
      usage = value;
      onUsage?.call(value, request);
    },
  );
  return (
    summary: PromptBuilder.limitSummary(summary, 1500),
    summarizedMessageCount: end,
    usage: usage,
  );
}
