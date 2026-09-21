import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/services/chat/reply_inspiration_service.dart';

void main() {
  const service = ReplyInspirationService();
  test('parses exactly three distinct suggestions including fenced JSON', () {
    final items = service.parse('''```json
[{"label":"温柔","text":"我在这里"},{"label":"调侃","text":"舍不得？"},{"label":"推进","text":"出去走走"}]
```''');
    expect(items.map((e) => e.text), ['我在这里', '舍不得？', '出去走走']);
  });
  test('rejects empty, malformed, incomplete and duplicate suggestions', () {
    for (final raw in [
      '',
      'not json',
      '[]',
      '[{"label":"a","text":"same"},{"label":"b","text":"same"},{"label":"c","text":"last"}]',
      '[{"label":"a","text":123},{"label":"b","text":"b"},{"label":"c","text":"c"}]',
    ]) {
      expect(() => service.parse(raw), throwsFormatException);
    }
  });
  test('bounds recent visible bodies and separates action-only mode', () {
    final messages = List.generate(
      20,
      (i) => ChatMessage(
        role: 'assistant',
        content: 'body-$i',
        reasoningContent: 'secret',
        time: DateTime(2026),
      ),
    );
    final result = service.buildMessages(
      characterName: '角色',
      recentMessages: messages,
      draft: '我的草稿',
      mode: ReplyInspirationMode.actions,
    );
    expect(result.first['content'], contains('不代写台词'));
    expect(result.last['content'], contains('body-19'));
    expect(result.last['content'], isNot(contains('body-0')));
    expect(result.last['content'], isNot(contains('secret')));
    expect(result.last['content'], contains('我的草稿'));
  });
}
