import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/theater_participant_reply_sanitizer.dart';

void main() {
  const names = ['梓涵', '糖璃'];

  group('sanitizeParticipantReply', () {
    test('keeps plain reply text', () {
      expect(
        sanitizeParticipantReply(
          rawReply: '嗯，我们听着呢。',
          targetName: '梓涵',
          allParticipantNames: names,
        ),
        '嗯，我们听着呢。',
      );
    });

    test('removes supported target labels', () {
      for (final raw in [
        '[梓涵] 嗯，我们听着呢。',
        '[梓涵][梓涵] 嗯，我们听着呢。',
        '梓涵：嗯，我们听着呢。',
        '梓涵: 嗯，我们听着呢。',
        '【梓涵】嗯，我们听着呢。',
        '<<<WhisnyaSpeaker:梓涵>>>\n嗯，我们听着呢。',
      ]) {
        expect(
          sanitizeParticipantReply(
            rawReply: raw,
            targetName: '梓涵',
            allParticipantNames: names,
          ),
          '嗯，我们听着呢。',
          reason: raw,
        );
      }
    });

    test('keeps only target blocks and merges repeated target blocks', () {
      expect(
        sanitizeParticipantReply(
          rawReply: '[梓涵] 第一段\n[糖璃] 其他角色\n[梓涵] 第二段',
          targetName: '梓涵',
          allParticipantNames: names,
        ),
        '第一段\n第二段',
      );
    });

    test('returns null when only another role speaks', () {
      expect(
        sanitizeParticipantReply(
          rawReply: '[糖璃] 主人快说呀。',
          targetName: '梓涵',
          allParticipantNames: names,
        ),
        isNull,
      );
    });

    test('returns null for ambiguous unbounded multi-role output', () {
      expect(
        sanitizeParticipantReply(
          rawReply: '梓涵说她听着，随后糖璃回答她也在。',
          targetName: '梓涵',
          allParticipantNames: names,
        ),
        isNull,
      );
    });

    test('matches longer participant names first', () {
      expect(
        sanitizeParticipantReply(
          rawReply: '[小梓涵] 长名字回复\n[梓涵] 短名字回复',
          targetName: '小梓涵',
          allParticipantNames: const ['梓涵', '小梓涵'],
        ),
        '长名字回复',
      );
    });

    test('returns null when cleaned reply is empty', () {
      expect(
        sanitizeParticipantReply(
          rawReply: '[梓涵][梓涵]\n[糖璃] 其他角色',
          targetName: '梓涵',
          allParticipantNames: names,
        ),
        isNull,
      );
    });
  });

  test(
    'requestSanitizedParticipantReply retries once and returns one reply',
    () async {
      var attempts = 0;
      final reply = await requestSanitizedParticipantReply(
        request: (isRetry) async {
          attempts++;
          expect(isRetry, attempts == 2);
          return attempts == 1 ? '[糖璃] 错误角色' : '[梓涵] 正确回复';
        },
        targetName: '梓涵',
        allParticipantNames: names,
      );

      expect(attempts, 2);
      expect(reply, '正确回复');
    },
  );

  test('requestSanitizedParticipantReply stops after the retry', () async {
    var attempts = 0;
    final reply = await requestSanitizedParticipantReply(
      request: (_) async {
        attempts++;
        return '[糖璃] 仍然错误';
      },
      targetName: '梓涵',
      allParticipantNames: names,
    );

    expect(attempts, 2);
    expect(reply, isNull);
  });
}
