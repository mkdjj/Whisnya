import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
import 'package:whisnya/services/chat/character_inner_voice_service.dart';

void main() {
  const service = CharacterInnerVoiceService();

  test('builds a dedicated prompt from bounded visible conversation data', () {
    final messages = <ChatMessage>[
      ChatMessage(
        role: 'system',
        content: 'must not leak',
        time: DateTime(2026),
      ),
      for (var index = 0; index < 14; index++)
        ChatMessage(
          role: index.isEven ? 'user' : 'assistant',
          content: index == 0 ? '${'字' * 1300}tail' : 'message-$index',
          innerVoice: 'secret-inner-$index',
          time: DateTime(2026, 1, index + 1),
        ),
    ];

    final prompt = service.buildMessages(
      characterName: '小白',
      characterDefinition: '角色定义',
      assistantReply: '刚刚显示的回复',
      recentMessages: messages,
      memoryContext: '长期记忆',
      worldBookContext: '世界书设定',
      chatSummary: '对话摘要',
    );

    expect(prompt, hasLength(2));
    expect(prompt.first['role'], 'system');
    expect(prompt.first['content'], contains('虚构角色'));
    expect(prompt.first['content'], contains('不是 AI 的推理过程'));
    final input = prompt.last['content']!;
    expect(input, contains('角色定义'));
    expect(input, contains('刚刚显示的回复'));
    expect(input, contains('长期记忆'));
    expect(input, contains('世界书设定'));
    expect(input, contains('对话摘要'));
    expect(input, isNot(contains('must not leak')));
    expect(input, isNot(contains('小白：message-1\n')));
    expect(input, contains('message-2'));
    expect(input, contains('message-13'));
    expect(input, isNot(contains('secret-inner')));
  });

  test(
    'uses effective assistant content and caps each recent item by runes',
    () {
      final longEmoji = List.filled(1205, '😀').join();
      final prompt = service.buildMessages(
        characterName: '角色',
        characterDefinition: '',
        assistantReply: 'reply',
        recentMessages: [
          ChatMessage(
            role: 'assistant',
            content: 'legacy',
            time: DateTime(2026),
            variants: [
              ChatReplyVariant(content: longEmoji, time: DateTime(2026)),
            ],
          ),
        ],
      );

      final input = prompt.last['content']!;
      expect(input, isNot(contains('legacy')));
      expect('😀'.allMatches(input).length, 1200);
    },
  );

  test('normalizes fences and common headings', () {
    expect(service.normalize('```text\n角色心声：其实我很在意。\n```'), '其实我很在意。');
    expect(service.normalize('## 内心独白\n不要让他发现。'), '不要让他发现。');
    expect(service.normalize('  '), isEmpty);
  });

  test('caps output at 500 Unicode runes without splitting emoji', () {
    final normalized = service.normalize(List.filled(600, '😀').join());
    expect(normalized.runes.length, CharacterInnerVoiceService.maxCharacters);
    expect(normalized.endsWith('……'), isTrue);
    expect(normalized.contains('\uFFFD'), isFalse);
  });
}
