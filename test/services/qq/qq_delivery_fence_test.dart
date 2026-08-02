import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/services/qq/qq_delivery_fence.dart';

void main() {
  const settings = QqIntegrationSettings(
    enabled: true,
    mode: QqIntegrationMode.notification,
  );

  test('stop pause and stale generations fence reply delivery', () {
    bool permits({
      bool running = true,
      bool paused = false,
      int current = 4,
      int result = 4,
    }) => qqDeliveryPermitted(
      running: running,
      paused: paused,
      currentGeneration: current,
      resultGeneration: result,
      settings: settings,
      mode: QqIntegrationMode.notification,
    );

    expect(permits(), isTrue);
    expect(permits(running: false), isFalse);
    expect(permits(paused: true), isFalse);
    expect(permits(current: 5, result: 4), isFalse);
  });
}
