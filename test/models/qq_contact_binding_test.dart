import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_contact_binding.dart';
import 'package:whisnya/models/qq_integration_settings.dart';

void main() {
  test('keeps external qq ids as strings', () {
    final now = DateTime.utc(2026, 8, 3);
    final binding = QqContactBinding.fromJson({
      'id': 'b1',
      'mode': 'oneBot',
      'externalUserId': '900719925474099312345',
      'displayName': 'Alice',
      'characterId': 'c1',
      'sessionId': 's1',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    expect(binding.externalUserId, '900719925474099312345');
    expect(binding.mode, QqIntegrationMode.oneBot);
    expect(
      QqContactBinding.fromJson(binding.toJson()).externalUserId,
      binding.externalUserId,
    );
  });

  test(
    'notification contact key is stable and does not use notification key',
    () {
      final first = notificationContactKey(
        packageName: 'com.tencent.mobileqq',
        conversationTitle: '  Alice   Zhang ',
        shortcutId: 'shortcut',
      );
      final second = notificationContactKey(
        packageName: 'com.tencent.mobileqq',
        conversationTitle: 'Alice Zhang',
        shortcutId: 'shortcut',
      );
      expect(first, second);
      expect(first, hasLength(64));
    },
  );
}
