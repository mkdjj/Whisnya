import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/prompts/prompt_builder.dart';
import 'package:whisnya/services/theater/theater_reply_engine.dart';

void main() {
  const ai1 = TheaterParticipant(
    id: 'a1',
    source: TheaterRoleSource.appCharacter,
    name: '甲',
    avatar: '',
    description: '甲简介',
    personality: '冷静',
    background: '甲背景',
    speakingStyle: '短句',
  );
  const ai2 = TheaterParticipant(
    id: 'a2',
    source: TheaterRoleSource.appCharacter,
    name: '乙',
    avatar: '',
    description: '乙简介',
    personality: '活泼',
    background: '乙背景',
    speakingStyle: '长句',
  );
  const muted = TheaterParticipant(
    id: 'muted',
    source: TheaterRoleSource.appCharacter,
    name: '禁言',
    avatar: '',
    description: '',
    personality: '',
    background: '',
    speakingStyle: '',
    isMuted: true,
  );
  const user = TheaterParticipant(
    id: 'user',
    source: TheaterRoleSource.appCharacter,
    name: '用户角色',
    avatar: '',
    description: '',
    personality: '',
    background: '',
    speakingStyle: '',
  );

  TheaterMessage message(
    String id,
    int round,
    TheaterSpeakerType type,
    String content, {
    bool isError = false,
  }) => TheaterMessage(
    id: id,
    sessionId: 's',
    round: round,
    speakerType: type,
    speakerId: type == TheaterSpeakerType.role ? ai1.id : '',
    speakerName: type == TheaterSpeakerType.user ? '我' : ai1.name,
    content: content,
    time: DateTime(2026),
    isError: isError,
    errorMessage: isError ? content : '',
  );

  TheaterSession session({
    int mainReplyCount = 0,
    int extraReplyMode = 0,
    List<TheaterParticipant> participants = const [ai1, ai2, muted, user],
  }) => TheaterSession(
    id: 's',
    title: '测试群聊',
    userParticipantId: user.id,
    mainReplyCount: mainReplyCount,
    extraReplyMode: extraReplyMode,
    participants: participants,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  group('participant selection', () {
    test('selects one, two, or all distinct active AI roles', () {
      final participants = const [ai1, ai2, muted, user];

      expect(
        selectParticipants(
          participants: participants,
          userParticipantId: user.id,
          count: 1,
          random: Random(1),
        ),
        hasLength(1),
      );
      final two = selectParticipants(
        participants: participants,
        userParticipantId: user.id,
        count: 2,
        random: Random(1),
      );
      expect(two.map((item) => item.id).toSet(), hasLength(2));
      expect(two, isNot(contains(muted)));
      expect(two, isNot(contains(user)));
      expect(
        selectParticipants(
          participants: participants,
          userParticipantId: user.id,
          count: 0,
          random: Random(1),
        ),
        hasLength(2),
      );
    });

    test('extra counts stay inside their configured bounds', () {
      expect(resolveExtraReplyCount(mode: 0, availableCount: 3), 0);
      for (var seed = 0; seed < 20; seed++) {
        expect(
          resolveExtraReplyCount(
            mode: 1,
            availableCount: 3,
            random: Random(seed),
          ),
          inInclusiveRange(0, 1),
        );
        expect(
          resolveExtraReplyCount(
            mode: 2,
            availableCount: 1,
            random: Random(seed),
          ),
          inInclusiveRange(0, 1),
        );
      }
    });
  });

  group('session compatibility', () {
    test('round trips reply settings and defaults legacy JSON', () {
      final configured = session(mainReplyCount: 2, extraReplyMode: 1);
      final restored = TheaterSession.fromJson(configured.toJson());
      final legacy = configured.toJson()
        ..remove('mainReplyCount')
        ..remove('extraReplyMode');

      expect(restored.mainReplyCount, 2);
      expect(restored.extraReplyMode, 1);
      expect(TheaterSession.fromJson(legacy).mainReplyCount, 0);
      expect(TheaterSession.fromJson(legacy).extraReplyMode, 0);
    });
  });

  group('generation prompts', () {
    test('adds only the selected generation intent instructions', () {
      final base = session(participants: const [ai1, ai2]);
      List<Map<String, String>> request(TheaterGenerationIntent intent) =>
          PromptBuilder.buildTheaterSingleApiRequest(
            session: base,
            novelSummary: '',
            messages: const [],
            allowedParticipants: const [ai1],
            generationIntent: intent,
          );

      expect(
        request(TheaterGenerationIntent.continueConversation).last['content'],
        contains('本轮没有新的用户消息'),
      );
      expect(
        request(TheaterGenerationIntent.continueConversation).last['content'],
        contains('最后一条非空角色消息'),
      );
      expect(
        request(TheaterGenerationIntent.userReply).last['content'],
        isNot(contains('本轮没有新的用户消息')),
      );
    });

    test('orders participant request as fixed memory history then turn', () {
      final request = PromptBuilder.buildTheaterParticipantRequest(
        session: session(
          participants: const [ai1, ai2],
        ).copyWith(theaterSummary: '群聊总结'),
        participant: ai1,
        novelSummary: '小说总结',
        messages: [
          message('u', 1, TheaterSpeakerType.user, 'A'),
          message('a', 1, TheaterSpeakerType.role, 'B'),
        ],
      );

      expect(request, hasLength(5));
      expect(request.first['content'], contains('【全部参与角色（固定顺序）】'));
      expect(request[1]['content'], contains('【小说总结】\n小说总结'));
      expect(request[1]['content'], contains('【群聊总结】\n群聊总结'));
      expect(request[1]['content'], isNot(contains('当前发言角色')));
      expect(request[2], {'role': 'user', 'content': '[我] A'});
      expect(request[3], {'role': 'assistant', 'content': '[甲] B'});
      expect(request.last['content'], contains('当前发言角色：甲'));
      expect(request.last['content'], contains('【本轮生成意图】'));
    });

    test('orders single api request as fixed memory history then turn', () {
      final request = PromptBuilder.buildTheaterSingleApiRequest(
        session: session(
          participants: const [ai1, ai2],
        ).copyWith(theaterSummary: '群聊总结'),
        novelSummary: '小说总结',
        allowedParticipants: const [ai1],
        messages: [
          message('u', 1, TheaterSpeakerType.user, 'A'),
          message('a', 1, TheaterSpeakerType.role, 'B'),
        ],
      );

      expect(request, hasLength(5));
      expect(request.first['content'], contains('<<<WhisnyaSpeaker:角色名>>>'));
      expect(request[1]['content'], contains('【小说总结】\n小说总结'));
      expect(request[1]['content'], contains('【群聊总结】\n群聊总结'));
      expect(request[1]['content'], isNot(contains('【本轮允许发言】')));
      expect(request[2], {'role': 'user', 'content': '[我] A'});
      expect(request[3], {'role': 'assistant', 'content': '[甲] B'});
      expect(request.last['content'], contains('【本轮允许发言】\n甲'));
      expect(request.last['content'], contains('【本轮生成意图】'));
    });

    test('keeps cached theater prefix stable when history is appended', () {
      final base = session(
        participants: const [ai1, ai2],
      ).copyWith(theaterSummary: '群聊总结');
      final history = [
        message('u', 1, TheaterSpeakerType.user, 'A'),
        message('a', 1, TheaterSpeakerType.role, 'B'),
      ];
      List<Map<String, String>> request(List<TheaterMessage> messages) =>
          PromptBuilder.buildTheaterSingleApiRequest(
            session: base,
            novelSummary: '小说总结',
            messages: messages,
            allowedParticipants: const [ai1],
          );

      final before = request(history);
      final appended = message('c', 2, TheaterSpeakerType.user, 'C');
      final after = request([...history, appended]);

      expect(after.take(before.length - 1), before.take(before.length - 1));
      expect(after[before.length - 1], {'role': 'user', 'content': '[我] C'});
      expect(after.last, before.last);
      expect(before.last['content'], contains('【本轮生成意图】'));
    });

    test('changes theater summary without rewriting fixed or history maps', () {
      final base = session(participants: const [ai1, ai2]);
      final history = [
        message('u', 1, TheaterSpeakerType.user, 'A'),
        message('a', 1, TheaterSpeakerType.role, 'B'),
      ];
      List<Map<String, String>> request(String summary) =>
          PromptBuilder.buildTheaterSingleApiRequest(
            session: base.copyWith(theaterSummary: summary),
            novelSummary: '小说总结',
            messages: history,
            allowedParticipants: const [ai1],
          );

      final before = request('旧总结');
      final after = request('新总结');

      expect(after.first, before.first);
      expect(after[1], isNot(before[1]));
      expect(
        after.skip(2).take(history.length),
        before.skip(2).take(history.length),
      );
      expect(after.last, before.last);
    });

    test(
      'keeps participant fixed system identical and current role dynamic',
      () {
        final base = session(participants: const [ai1, ai2]);
        final first = PromptBuilder.buildTheaterParticipantRequest(
          session: base,
          participant: ai1,
          novelSummary: '',
          messages: const [],
        );
        final second = PromptBuilder.buildTheaterParticipantRequest(
          session: base,
          participant: ai2,
          novelSummary: '',
          messages: const [],
        );

        expect(first.first, second.first);
        expect(first.last['content'], contains('当前发言角色：甲'));
        expect(first.last['content'], contains('【本轮唯一发言者】\n甲'));
        expect(first.last['content'], contains('严禁输出其他角色'));
        expect(second.last['content'], contains('当前发言角色：乙'));
        expect(first.first['content'], isNot(contains('当前发言角色：甲')));
      },
    );

    test('adds a stricter participant-only hint on retry', () {
      final request = PromptBuilder.buildTheaterParticipantRequest(
        session: session(participants: const [ai1, ai2]),
        participant: ai1,
        novelSummary: '',
        messages: const [],
        previousOutputInvalid: true,
      );

      expect(request.last['content'], contains('【上次输出错误】'));
      expect(request.last['content'], contains('本次只能输出“甲”的回复正文'));
    });

    test('filters placeholders and uses user and assistant history roles', () {
      final request = PromptBuilder.buildTheaterParticipantRequest(
        session: session(participants: const [ai1, ai2]),
        participant: ai1,
        novelSummary: '',
        messages: [
          message('u', 1, TheaterSpeakerType.user, '你好'),
          message('empty', 1, TheaterSpeakerType.role, '  '),
          message('a', 1, TheaterSpeakerType.role, '你好呀'),
        ],
      );

      expect(request.where((item) => item['role'] == 'user'), hasLength(1));
      expect(
        request.where((item) => item['role'] == 'assistant'),
        hasLength(1),
      );
      expect(request[2]['content'], '[我] 你好');
      expect(request[3]['content'], '[甲] 你好呀');
      expect(request.last['content'], contains('【本轮生成意图】'));
      expect(request.toString(), isNot(contains('empty')));
    });
  });

  group('single API fallback and retry', () {
    test('assigns plain text only when exactly one role is allowed', () {
      expect(
        resolveSingleApiFallback('普通回复', const [ai1]).single.speaker,
        ai1.name,
      );
      expect(resolveSingleApiFallback('普通回复', const [ai1, ai2]), isEmpty);
      expect(
        resolveSingleApiFallback('<<<WhisnyaSpeaker:未知角色>>>\n回复', const [ai1]),
        isEmpty,
      );
    });

    test(
      'prepares a system format retry without adding messages or rounds',
      () {
        final userMessage = message('u', 5, TheaterSpeakerType.user, '你好');
        final error = message(
          'e',
          5,
          TheaterSpeakerType.system,
          '模型没有按群聊格式输出，可重试',
          isError: true,
        );
        final retry = prepareSingleApiRetry([userMessage, error], error);

        expect(retry, isNotNull);
        expect(retry!.round, 5);
        expect(retry.messages, [userMessage]);
      },
    );
  });

  group('summary context protection', () {
    test('preserves two recent rounds and at least six valid messages', () {
      final messages = <TheaterMessage>[
        for (var round = 1; round <= 5; round++) ...[
          message('u$round', round, TheaterSpeakerType.user, '用户$round'),
          message('a$round', round, TheaterSpeakerType.role, '角色$round'),
        ],
      ];

      expect(theaterPreserveStartIndex(messages), 4);
      expect(
        theaterSummaryEndIndex(
          messages: messages,
          summarizedMessageCount: 0,
          messageBatchSize: 1,
          roundBatchSize: 1,
        ),
        4,
      );
    });

    test(
      'filters system errors and empty placeholders from recent context',
      () {
        final lastRole = message('last', 2, TheaterSpeakerType.role, '最后原文');
        final recent = recentTheaterMessages([
          message('old', 1, TheaterSpeakerType.user, '旧消息'),
          message('empty', 2, TheaterSpeakerType.role, ''),
          message(
            'error',
            2,
            TheaterSpeakerType.system,
            '生成失败，点击重试',
            isError: true,
          ),
          lastRole,
        ], summarizedMessageCount: 1);

        expect(recent.map((message) => message.id), ['old', 'last']);
        final legacyRecent = recentTheaterMessages([
          message('u', 1, TheaterSpeakerType.user, '用户原文'),
          lastRole,
        ], summarizedMessageCount: 2);
        expect(legacyRecent, contains(lastRole));
      },
    );
  });
}
