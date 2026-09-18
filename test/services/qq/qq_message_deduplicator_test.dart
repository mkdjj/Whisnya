import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/models/unified_qq_message.dart';
import 'package:whisnya/services/qq/qq_message_deduplicator.dart';

void main() {
  UnifiedQqMessage message({
    String id = 'm1',
    String text = 'hello',
    QqIntegrationMode source = QqIntegrationMode.oneBot,
    DateTime? time,
  }) => UnifiedQqMessage(
    source: source,
    messageId: id,
    externalUserId: 'u1',
    senderDisplayName: 'Alice',
    text: text,
    timestamp: time ?? DateTime.utc(2026, 8, 3),
    rawConversationTitle: 'Alice',
  );

  test('deduplicates message ids and expires them after thirty minutes', () {
    final deduplicator = QqMessageDeduplicator();
    final now = DateTime.utc(2026, 8, 3);
    expect(deduplicator.isDuplicate(message(), now: now), isFalse);
    expect(deduplicator.isDuplicate(message(), now: now), isTrue);
    expect(
      deduplicator.isDuplicate(
        message(),
        now: now.add(const Duration(minutes: 31)),
      ),
      isFalse,
    );
  });

  test('keeps at most five hundred ids', () {
    final deduplicator = QqMessageDeduplicator();
    final now = DateTime.utc(2026, 8, 3);
    for (var index = 0; index < 501; index++) {
      deduplicator.isDuplicate(message(id: 'm$index'), now: now);
    }
    expect(deduplicator.size, 500);
  });
}
