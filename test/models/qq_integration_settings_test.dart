import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_integration_settings.dart';

void main() {
  test('defaults are safe and settings clamp persisted ranges', () {
    const defaults = QqIntegrationSettings();
    expect(defaults.enabled, isFalse);
    expect(defaults.mode, QqIntegrationMode.disabled);
    expect(defaults.oneBotHost, '127.0.0.1');
    expect(defaults.mergeWindowMilliseconds, 1800);
    expect(defaults.notificationPackageName, 'com.tencent.mobileqq');

    final parsed = QqIntegrationSettings.fromJson({
      'mode': 'oneBot',
      'mergeWindowMilliseconds': -2,
      'replyDelayMilliseconds': 20000,
      'maxReplyCharacters': 20,
      'replyChunkCharacters': 99999,
      'requestTimeoutSeconds': 5,
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
    expect(parsed.oneBotPort, 65535);
    expect(parsed.quietHoursStartMinutes, 0);
    expect(parsed.quietHoursEndMinutes, 1439);
  });

  test('round trips every transport setting', () {
    final value = QqIntegrationSettings.fromJson({
      'enabled': true,
      'mode': 'notification',
      'defaultCharacterId': 'role',
      'oneBotHost': 'localhost',
      'oneBotPort': 4321,
      'oneBotPath': '/onebot',
      'oneBotSecure': true,
      'allowInsecureRemoteOneBot': true,
      'accessibilityFallbackEnabled': true,
      'returnAfterAccessibilitySend': false,
    });
    expect(
      QqIntegrationSettings.fromJson(value.toJson()).toJson(),
      value.toJson(),
    );
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

  test('remote plaintext onebot is rejected unless explicitly allowed', () {
    expect(
      const QqIntegrationSettings(
        mode: QqIntegrationMode.oneBot,
        oneBotHost: '192.168.1.20',
      ).oneBotConfigurationError,
      isNotNull,
    );
    expect(
      const QqIntegrationSettings(
        mode: QqIntegrationMode.oneBot,
        oneBotHost: '192.168.1.20',
        allowInsecureRemoteOneBot: true,
      ).oneBotConfigurationError,
      isNull,
    );
  });
}
