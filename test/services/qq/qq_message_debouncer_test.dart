import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/models/unified_qq_message.dart';
import 'package:whisnya/services/qq/qq_message_debouncer.dart';

void main() {
  UnifiedQqMessage message(String id, String text) => UnifiedQqMessage(
    source: QqIntegrationMode.oneBot,
    messageId: id,
    externalUserId: 'u1',
    senderDisplayName: 'Alice',
    text: text,
    timestamp: DateTime.now(),
    rawConversationTitle: 'Alice',
  );

  test('merges consecutive messages for the same contact', () async {
    final ready = Completer<UnifiedQqMessage>();
    final debouncer = QqMessageDebouncer(
      mergeWindow: const Duration(milliseconds: 20),
    );
    debouncer.add(message('1', 'first'), ready.complete);
    debouncer.add(message('2', 'second'), ready.complete);
    final merged = await ready.future.timeout(const Duration(seconds: 1));
    expect(merged.text, 'first\nsecond');
    expect(merged.messageId, '2');
  });

  test('commands bypass merging', () async {
    final values = <UnifiedQqMessage>[];
    final debouncer = QqMessageDebouncer(mergeWindow: const Duration(hours: 1));
    debouncer.add(message('1', '/帮助'), values.add, isCommand: true);
    expect(values.single.text, '/帮助');
    debouncer.dispose();
  });

  test('caps a batch at ten messages and four thousand runes', () async {
    final ready = Completer<UnifiedQqMessage>();
    final debouncer = QqMessageDebouncer(
      mergeWindow: const Duration(milliseconds: 20),
    );
    for (var index = 0; index < 12; index++) {
      debouncer.add(message('$index', '🙂' * 500), ready.complete);
    }
    final merged = await ready.future.timeout(const Duration(seconds: 1));
    expect(merged.text.runes.length, lessThanOrEqualTo(4000));
    expect(merged.text.split('\n'), hasLength(8));
  });
}
