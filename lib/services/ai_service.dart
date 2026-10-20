import 'package:http/http.dart' as http;

import '../models/ai_usage.dart';
import '../models/ai_response.dart';
import 'ai/ai_gateway.dart';
import 'ai/ai_conversation_runner.dart';

export '../models/ai_usage.dart' show AiUsage;
export '../models/ai_response.dart' show AiResponse, AiResponseDelta;
export 'ai/ai_conversation_runner.dart'
    show AiCancelToken, AiException, AiRequest, selectAutomaticModel;

class AiService extends AiGateway {
  AiService({http.Client? client})
    : _runner = AiConversationRunner(client: client);

  final AiConversationRunner _runner;

  AiRequest _withStream(AiRequest request, bool stream) => AiRequest(
    endpoint: request.endpoint,
    messages: request.messages,
    temperature: request.temperature,
    stream: stream,
    includeReasoning: request.includeReasoning,
  );

  @override
  Future<AiResponse> sendResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) => _runner.sendResponse(
    _withStream(request, false),
    cancelToken: cancelToken,
  );

  @override
  Stream<AiResponseDelta> streamResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) async* {
    AiUsage? usage;
    await for (final event in _runner.streamResponse(
      _withStream(request, true),
      cancelToken: cancelToken,
    )) {
      usage = event.usage ?? usage;
      if (event.contentDelta.isNotEmpty || event.reasoningDelta.isNotEmpty) {
        yield AiResponseDelta(
          contentDelta: event.contentDelta,
          reasoningDelta: event.reasoningDelta,
        );
      }
    }
    // Providers can send cumulative usage more than once; expose the final total once.
    yield AiResponseDelta(usage: usage ?? const AiUsage());
  }

  Future<List<String>> listModels({
    required String apiKey,
    required String baseUrl,
  }) {
    return _runner.listModels(apiKey: apiKey, baseUrl: baseUrl);
  }
}
