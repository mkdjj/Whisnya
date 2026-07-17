import 'dart:math';

const defaultChatContinuityMessageCount = 12;

int chatContextStartIndex({
  required int summarizedMessageCount,
  required int messageCount,
  int continuityMessageCount = defaultChatContinuityMessageCount,
}) {
  final safeSummaryCount = summarizedMessageCount
      .clamp(0, messageCount)
      .toInt();
  final continuityStart = max(0, messageCount - continuityMessageCount);
  return min(safeSummaryCount, continuityStart);
}

int manualSummaryBoundary({
  required int messageCount,
  int continuityMessageCount = defaultChatContinuityMessageCount,
}) => max(0, messageCount - continuityMessageCount);
