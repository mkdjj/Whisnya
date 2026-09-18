import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_integration_settings.dart';

void main() {
  test('defaults are safe and settings clamp persisted ranges', () {
    const defaults = QqIntegrationSettings();
    expect(defaults.enabled, isFalse);
    expect(defaults.mode, QqIntegrationMode.disabled);
    expect(defaults.mergeWindowMilliseconds, 1800);

    final parsed = QqIntegrationSettings.fromJson({
      'mode': 'oneBot',
      'mergeWindowMilliseconds': -2,
      'replyDelayMilliseconds': 20000,
      'maxReplyCharacters': 20,
      'replyChunkCharacters': 99999,
      'requestTimeoutSeconds': 5,
      'oneBotHost': 'legacy.example',
      'oneBotPort': 90000,
      'quietHoursStartMinutes': -1,
      'quietHoursEndMinutes': 9999,
    });

    expect(parsed.mode, QqIntegrationMode.oneBot);
    expect(parsed.mergeWindowMilliseconds, 0);
    expect(parsed.replyDelayMilliseconds, 10000);
    expect(parsed.maxReplyCharacters, 100);
    expect(parsed.replyChunkCharacters, 100);
    expect(parsed.requestTimeoutSeconds, 15);
    expect(parsed.quietHoursStartMinutes, 0);
    expect(parsed.quietHoursEndMinutes, 1439);
    expect(parsed.toJson(), isNot(contains('oneBotHost')));
    expect(parsed.toJson(), isNot(contains('oneBotPort')));
  });

  test('round trips onebot settings', () {
    final value = QqIntegrationSettings.fromJson({
      'enabled': true,
      'mode': 'oneBot',
      'oneBotHost': 'localhost',
      'oneBotPort': 4321,
      'oneBotPath': '/onebot',
      'oneBotSecure': true,
      'allowInsecureRemoteOneBot': true,
    });
    expect(
      QqIntegrationSettings.fromJson(value.toJson()).toJson(),
      value.toJson(),
    );
  });

  test('legacy notification mode is downgraded to disabled', () {
    final value = QqIntegrationSettings.fromJson({
      'enabled': true,
      'mode': 'notification',
      'notificationRemoteInputEnabled': true,
    });
    expect(value.mode, QqIntegrationMode.disabled);
    expect(value.enabled, isFalse);
    expect(value.toJson(), isNot(contains('notificationRemoteInputEnabled')));
  });

  test('quiet hours supports ranges crossing midnight', () {
    final settings = const QqIntegrationSettings(
      quietHoursEnabled: true,
      quietHoursStartMinutes: 23 * 60,
      quietHoursEndMinutes: 7 * 60,
    );
    expect(settings.isQuietAt(DateTime(2026, 8, 3, 23, 30)), isTrue);
    expect(settings.isQuietAt(DateTime(2026, 8, 4, 6, 59)), isTrue);
    expect(settings.isQuietAt(DateTime(2026, 8, 4, 12)), isFalse);
  });
}
