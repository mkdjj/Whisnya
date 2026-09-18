import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_diagnostic_event.dart';

void main() {
  test(
    'legacy notification diagnostics are not reported as reply failures',
    () {
      final event = QqDiagnosticEvent.fromJson({
        'time': '2026-08-09T00:00:00Z',
        'mode': 'notification',
        'eventType': 'captureStarted',
        'success': true,
      });

      expect(event.eventType.name, 'legacyUnsupported');
    },
  );
}
