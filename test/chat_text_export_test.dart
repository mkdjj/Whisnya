import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/chat_text_export.dart';

void main() {
  test('formats multiline chat entries as readable UTF-8 text', () {
    final text = formatChatText(
      title: 'Alice',
      entries: [
        (
          time: DateTime(2026, 7, 30, 9, 5, 7),
          speaker: '我',
          content: '你好\n第二行',
        ),
        (
          time: DateTime(2026, 7, 30, 9, 6, 8),
          speaker: 'Alice',
          content: '早上好',
        ),
      ],
    );

    expect(
      text,
      'Alice\n\n'
      '[2026-07-30 09:05:07] 我\n'
      '你好\n第二行\n\n'
      '[2026-07-30 09:06:08] Alice\n'
      '早上好\n',
    );
  });

  test('builds a safe dated txt filename', () {
    expect(
      chatTextFileName('A:/B*?', DateTime(2026, 7, 30, 9, 5, 7)),
      'A__B__-chat-20260730-090507.txt',
    );
  });
}
