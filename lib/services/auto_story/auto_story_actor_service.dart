import 'dart:async';
import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';
import '../../utils/stream_text_buffer.dart';
import 'auto_story_validator.dart';

class AutoStoryActorResult {
  const AutoStoryActorResult({
    required this.content,
    this.reasoningContent = '',
    this.usage,
  });
  final String content;
  final String reasoningContent;
  final AiUsage? usage;
}

/// One request only. Reservation, usage deduplication and repair belong to runner.
class AutoStoryActorService {
  const AutoStoryActorService(
    this.gateway, {
    this.timeout = const Duration(seconds: 90),
  });
  final AiGateway gateway;
  final Duration timeout;

  Future<AutoStoryActorResult> generate({
    required AiEndpointConfig endpoint,
    required List<Map<String, String>> messages,
    required String actorName,
    required Iterable<String> otherActorNames,
    String actorId = 'A',
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(String content, String reasoning)? onDraft,
    void Function(AiUsage)? onUsage,
  }) async {
    if (endpoint.validationError case final String error) {
      throw AiException(error);
    }
    final token = cancelToken ?? AiCancelToken();
    if (token.isCancelled) throw AiException('请求已取消。');
    final content = StringBuffer();
    final reasoning = StringBuffer();
    final draftUpdates = StreamTextBuffer(
      onFlush: (_) {
        if (!token.isCancelled) {
          onDraft?.call(content.toString(), reasoning.toString());
        }
      },
    );
    AiUsage? usage;
    void record(AiUsage value) {
      usage = value;
      onUsage?.call(value);
    }

    final stream = gateway.streamResponse(
      AiRequest(
        endpoint: endpoint,
        messages: messages,
        stream: true,
        includeReasoning: includeReasoning,
      ),
      cancelToken: token,
    );
    final subscription = stream
        .map<void>((event) {
          if (event.usage != null) record(event.usage!);
          if (token.isCancelled) return;
          content.write(event.contentDelta);
          if (includeReasoning) reasoning.write(event.reasoningDelta);
          if (content.length > 20000 || reasoning.length > 64000) {
            token.cancel();
            throw const FormatException('演员输出超出安全长度。');
          }
          if (onDraft != null &&
              (event.contentDelta.isNotEmpty ||
                  (includeReasoning && event.reasoningDelta.isNotEmpty))) {
            draftUpdates.add(' ');
          }
        })
        .listen(null);
    try {
      await subscription.asFuture<void>().timeout(
        timeout,
        onTimeout: () {
          token.cancel();
          throw TimeoutException('故事请求超时。', timeout);
        },
      );
      if (token.isCancelled) throw AiException('请求已取消。');
      draftUpdates.flush();
      return AutoStoryActorResult(
        content: AutoStoryValidator.actorContent(
          content.toString(),
          actorName: actorName,
          otherActorNames: otherActorNames,
          actorId: actorId,
        ),
        reasoningContent: reasoning.toString(),
        usage: usage,
      );
    } finally {
      draftUpdates.dispose();
      // Some providers do not complete cancellation. Never await their cleanup.
      unawaited(subscription.cancel());
    }
  }
}
