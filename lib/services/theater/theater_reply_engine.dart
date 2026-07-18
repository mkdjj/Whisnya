import 'dart:convert';
import 'dart:math';

import '../../models/theater.dart';

const theaterFormatErrorText = '模型没有按群聊格式输出，可重试';
const theaterRoleErrorText = '生成失败，点击重试';

List<TheaterParticipant> selectParticipants({
  required List<TheaterParticipant> participants,
  required int count,
  String userParticipantId = '',
  Random? random,
}) {
  final available = participants
      .where(
        (participant) =>
            participant.enabled &&
            !participant.isMuted &&
            participant.id != userParticipantId,
      )
      .toList();
  available.shuffle(random ?? Random());
  return count <= 0
      ? available
      : available.take(min(count, available.length)).toList();
}

int resolveExtraReplyCount({
  required int mode,
  required int availableCount,
  Random? random,
}) {
  if (mode <= 0 || availableCount <= 0) return 0;
  final maximum = min(mode, availableCount);
  return (random ?? Random()).nextInt(maximum + 1);
}

bool isValidTheaterContextMessage(TheaterMessage message) {
  if (message.isError || message.content.trim().isEmpty) return false;
  if (message.speakerType != TheaterSpeakerType.user &&
      message.speakerType != TheaterSpeakerType.role) {
    return false;
  }
  final content = message.content.trim();
  return content != theaterRoleErrorText && content != theaterFormatErrorText;
}

List<TheaterMessage> recentTheaterMessages(
  List<TheaterMessage> messages, {
  required int summarizedMessageCount,
}) {
  final summarizedStart = summarizedMessageCount
      .clamp(0, messages.length)
      .toInt();
  final start = min(summarizedStart, theaterPreserveStartIndex(messages));
  return messages.skip(start).where(isValidTheaterContextMessage).toList();
}

int theaterPreserveStartIndex(
  List<TheaterMessage> messages, {
  int minimumRounds = 2,
  int minimumMessages = 6,
}) {
  final valid = <({int index, TheaterMessage message})>[
    for (var i = 0; i < messages.length; i++)
      if (isValidTheaterContextMessage(messages[i]))
        (index: i, message: messages[i]),
  ];
  if (valid.isEmpty) return messages.length;

  final rounds = <int>[];
  for (final item in valid) {
    if (!rounds.contains(item.message.round)) rounds.add(item.message.round);
  }
  final preservedRounds = rounds
      .skip(max(0, rounds.length - minimumRounds))
      .toSet();
  final roundStart = valid
      .firstWhere((item) => preservedRounds.contains(item.message.round))
      .index;
  final messageStart = valid[max(0, valid.length - minimumMessages)].index;
  return min(roundStart, messageStart);
}

int theaterSummaryEndIndex({
  required List<TheaterMessage> messages,
  required int summarizedMessageCount,
  int messageBatchSize = 20,
  int roundBatchSize = 5,
}) {
  if (messages.isEmpty) return 0;
  final start = summarizedMessageCount.clamp(0, messages.length).toInt();
  final end = theaterPreserveStartIndex(messages);
  if (end <= start) return start;
  final pending = messages
      .sublist(start, end)
      .where(isValidTheaterContextMessage)
      .toList();
  final completeRounds = pending.map((message) => message.round).toSet().length;
  return pending.length >= messageBatchSize || completeRounds >= roundBatchSize
      ? end
      : start;
}

List<TheaterReplyDraft> resolveSingleApiFallback(
  String raw,
  List<TheaterParticipant> allowed,
) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  try {
    final decoded = jsonDecode(text);
    final items = switch (decoded) {
      List<dynamic> value => value,
      {'replies': List<dynamic> value} => value,
      {'messages': List<dynamic> value} => value,
      _ => const <dynamic>[],
    };
    final allowedNames = allowed.map((item) => item.name.trim()).toSet();
    final replies = items
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => TheaterReplyDraft(
            speaker: (item['speaker'] ?? item['name'] ?? '').toString().trim(),
            content: (item['content'] ?? item['message'] ?? '')
                .toString()
                .trim(),
          ),
        )
        .where(
          (reply) =>
              allowedNames.contains(reply.speaker) && reply.content.isNotEmpty,
        )
        .toList();
    if (replies.isNotEmpty) return replies;
  } on FormatException {
    // A single allowed role may safely own non-JSON plain text below.
  }
  if (text.contains('<<<WhisnyaSpeaker:')) return const [];
  return allowed.length == 1
      ? [TheaterReplyDraft(speaker: allowed.single.name, content: text)]
      : const [];
}

({List<TheaterMessage> messages, int round})? prepareSingleApiRetry(
  List<TheaterMessage> messages,
  TheaterMessage error,
) {
  if (error.speakerType != TheaterSpeakerType.system ||
      !error.isError ||
      !error.errorMessage.contains('模型没有按群聊格式输出')) {
    return null;
  }
  return (
    messages: messages.where((message) => message.id != error.id).toList(),
    round: error.round,
  );
}
