import 'ai_usage.dart';

class AiResponseDelta {
  const AiResponseDelta({
    this.contentDelta = '',
    this.reasoningDelta = '',
    this.usage,
  });

  final String contentDelta;
  final String reasoningDelta;
  final AiUsage? usage;
}

class AiResponse {
  const AiResponse({
    required this.content,
    this.reasoningContent = '',
    required this.usage,
  });

  final String content;
  final String reasoningContent;
  final AiUsage usage;
}
