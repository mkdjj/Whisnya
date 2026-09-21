import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/speech/speech_text_formatter.dart';

void main() {
  test('removes code and URLs while retaining narrative and link labels', () {
    const formatter = SpeechTextFormatter();
    expect(
      formatter.format(
        '# **你好**（微笑） [朋友](https://example.com)\n```dart\nsecret();\n```',
      ),
      '你好（微笑） 朋友',
    );
    expect(formatter.format('```\nonly code\n```'), '');
  });
  test('chunks respect UTF16 limit without splitting grapheme clusters', () {
    final chunks = const SpeechTextFormatter().chunks(
      '${'你' * 999}👩‍👩‍👧‍👦é后',
    );
    expect(chunks.every((chunk) => chunk.length <= 1000), true);
    expect(chunks.join(), '${'你' * 999}👩‍👩‍👧‍👦é后');
  });
}
