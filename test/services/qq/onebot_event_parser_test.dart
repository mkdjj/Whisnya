import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/qq/onebot/onebot_event_parser.dart';

void main() {
  test('parses private text and keeps very large ids as strings', () {
    final message = OneBotEventParser.parse({
      'post_type': 'message',
      'message_type': 'private',
      'user_id': '900719925474099312345',
      'self_id': '10000',
      'message_id': '999999999999999999999',
      'raw_message': 'hello',
      'message': 'ignored transport form',
      'sender': {'nickname': 'Alice'},
      'time': 1785715200,
    });
    expect(message, isNotNull);
    expect(message!.externalUserId, '900719925474099312345');
    expect(message.messageId, '999999999999999999999');
    expect(message.text, 'hello');
  });

  test('joins only text segments and ignores non-text-only messages', () {
    final parsed = OneBotEventParser.parse({
      'post_type': 'message',
      'message_type': 'private',
      'user_id': 123,
      'message_id': 456,
      'message': [
        {
          'type': 'text',
          'data': {'text': 'first'},
        },
        {
          'type': 'image',
          'data': {'file': 'secret.jpg'},
        },
        {
          'type': 'text',
          'data': {'text': ' second'},
        },
      ],
    });
    expect(parsed!.text, 'first second');
    expect(parsed.externalUserId, '123');

    expect(
      OneBotEventParser.parse({
        'post_type': 'message',
        'message_type': 'private',
        'user_id': '123',
        'message_id': '456',
        'message': [
          {
            'type': 'image',
            'data': {'file': 'secret.jpg'},
          },
        ],
      }),
      isNull,
    );
  });

  test('completely ignores group and non-message events', () {
    expect(
      OneBotEventParser.parse({
        'post_type': 'message',
        'message_type': 'group',
        'raw_message': 'hello',
      }),
      isNull,
    );
    expect(OneBotEventParser.parse({'post_type': 'notice'}), isNull);
  });
}
