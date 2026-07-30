import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/chat_search.dart';

void main() {
  test('chat search matches message content case-insensitively', () {
    expect(
      findChatSearchResults(const [
        'Alpha target',
        'nothing',
        'TARGET again',
      ], ' target '),
      [0, 2],
    );
    expect(findChatSearchResults(const ['target'], '   '), isEmpty);
  });
}
