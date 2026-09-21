import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
import 'package:whisnya/models/message_anchor.dart';

void main() {
  final now = DateTime(2026);
  ChatMessage reply(String id, String text) =>
      ChatMessage(id: id, role: 'assistant', content: text, time: now);
  test(
    'identity round trips and old data does not create identity on read',
    () {
      expect(ChatMessage.fromJson({'role': 'user', 'content': 'hi'}).id, '');
      expect(ChatMessage.fromJson(reply('a', 'hi').toJson()).id, 'a');
    },
  );
  test('anchor checks entire formal prefix but ignores late inner voice', () {
    final messages = [reply('a', 'one'), reply('b', 'two')];
    final anchor = MessageAnchor.capture('session', messages, 1);
    expect(
      anchor.matches([messages[0].copyWith(innerVoice: 'secret'), messages[1]]),
      true,
    );
    expect(
      anchor.matches([messages[0].copyWith(content: 'edited'), messages[1]]),
      false,
    );
    expect(anchor.matches([messages[1]]), false);
  });
  test('flat reply and original candidate have identical logical identity', () {
    final original = reply('a', 'same');
    final anchor = MessageAnchor.capture('s', [original], 0);
    final withVariants = original.copyWith(
      variants: [
        ChatReplyVariant(id: 'original_a', content: 'same', time: now),
        ChatReplyVariant(id: 'different', content: 'same', time: now),
      ],
    );
    expect(anchor.matches([withVariants]), true);
    expect(
      anchor.matches([withVariants.copyWith(selectedVariantIndex: 1)]),
      false,
    );
  });
}
