import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/role_message_segments.dart';

void main() {
  test('splits enabled role output around Chinese and ASCII parentheses', () {
    expect(roleMessageSegments('我爱你\n（抱住你）\n宝宝', enabled: true), [
      '我爱你',
      '（抱住你）',
      '宝宝',
    ]);
    expect(roleMessageSegments('love(hug)baby', enabled: true), [
      'love',
      '(hug)',
      'baby',
    ]);
  });

  test('keeps line breaks without parentheses in one bubble', () {
    expect(roleMessageSegments('我爱你\n宝宝', enabled: true), ['我爱你\n宝宝']);
  });

  test('keeps disabled role output in one bubble', () {
    expect(roleMessageSegments('love\n(hug)\nbaby', enabled: false), [
      'love\n(hug)\nbaby',
    ]);
  });
}
