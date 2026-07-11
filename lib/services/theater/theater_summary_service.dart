import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/theater.dart';
import '../../prompts.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';
import 'theater_reply_engine.dart';

class TheaterSummaryResult {
  const TheaterSummaryResult({
    required this.summary,
    required this.summarizedMessageCount,
    required this.usage,
  });

  final String summary;
  final int summarizedMessageCount;
  final AiUsage usage;
}

class TheaterSummaryService {
  const TheaterSummaryService(this._gateway);

  final AiGateway _gateway;

  Future<TheaterSummaryResult?> summarize({
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
    final summary = await _gateway.sendMessage(
      apiKey: endpoint.apiKey,
      baseUrl: endpoint.baseUrl,
      model: endpoint.model,
      messages: request,
      cancelToken: cancelToken,
      maxTokens: 800,
      onUsage: (value) {
        usage = value;
        onUsage?.call(value, request);
      },
    );
    return TheaterSummaryResult(
      summary: PromptBuilder.limitSummary(summary, 1500),
      summarizedMessageCount: end,
      usage: usage,
    );
  }
}
