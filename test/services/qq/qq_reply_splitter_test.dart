import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/qq/qq_reply_splitter.dart';

void main() {
  test('truncates and splits on rune boundaries', () {
    final parts = QqReplySplitter.splitOneBot(
      '🙂🙂。🙂🙂！🙂🙂？🙂🙂',
      maxReplyCharacters: 7,
      replyChunkCharacters: 3,
    );
    expect(parts.every((part) => part.runes.length <= 3), isTrue);
    expect(parts.join().runes.length, 7);
    expect(parts.join(), isNot(contains('�')));
  });

  test('truncate produces one complete limited reply', () {
    final reply = QqReplySplitter.truncate('123456789', maxReplyCharacters: 5);
    expect(reply, '12345');
  });

  test('prefers paragraph and sentence boundaries', () {
    final parts = QqReplySplitter.splitOneBot(
      'first paragraph.\n\nsecond sentence！tail',
      maxReplyCharacters: 100,
      replyChunkCharacters: 20,
    );
    expect(parts.first, 'first paragraph.');
  });
}
