import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../prompts/prompt_builder.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';

/// Shared transport and length limit; each caller chooses its own summary range.
Future<({String summary, AiUsage usage})> requestSummary(
  AiGateway gateway, {
  required AiEndpointConfig endpoint,
  required String prompt,
  bool theater = false,
  AiCancelToken? cancelToken,
  void Function(AiUsage usage, List<Map<String, String>> request)? onUsage,
}) async {
  final request = [
    {'role': 'system', 'content': '你负责总结${theater ? '群聊' : '聊天'}记录，并只输出总结内容。'},
    {'role': 'user', 'content': prompt},
  ];
  final response = await gateway.sendResponse(
    AiRequest(endpoint: endpoint, messages: request, temperature: 0.2),
    cancelToken: cancelToken,
  );
  onUsage?.call(response.usage, request);
  return (
    summary: PromptBuilder.limitSummary(response.content, 1500),
    usage: response.usage,
  );
}
