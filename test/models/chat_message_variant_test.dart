import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';

void main() {
  final originalTime = DateTime.utc(2026, 7, 31, 10);
  final newerTime = DateTime.utc(2026, 7, 31, 11);

  test('reads legacy assistant messages without variants', () {
    final message = ChatMessage.fromJson({
      'role': 'assistant',
      'content': 'legacy reply',
      'time': originalTime.toIso8601String(),
      'endpointId': 'old-endpoint',
      'endpointName': 'Old endpoint',
      'model': 'old-model',
    });

    expect(message.selectedVariant, isNull);
    expect(message.variantCount, 0);
    expect(message.effectiveContent, 'legacy reply');
    expect(message.effectiveTime, originalTime);
    expect(message.effectiveEndpointId, 'old-endpoint');
    expect(message.effectiveEndpointName, 'Old endpoint');
    expect(message.effectiveModel, 'old-model');
  });

  test('round trips variants and clamps an out-of-range selected index', () {
    final message = ChatMessage(
      role: 'assistant',
      content: 'legacy reply',
      time: originalTime,
      variants: [
        ChatReplyVariant(content: 'first reply', time: originalTime),
        ChatReplyVariant(
          content: 'second reply',
          time: newerTime,
          endpointId: 'new-endpoint',
          endpointName: 'New endpoint',
          model: 'new-model',
        ),
      ],
      selectedVariantIndex: 99,
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.variantCount, 2);
    expect(restored.selectedVariantIndex, 1);
    expect(restored.effectiveContent, 'second reply');
    expect(restored.effectiveTime, newerTime);
    expect(restored.effectiveEndpointId, 'new-endpoint');
    expect(restored.effectiveEndpointName, 'New endpoint');
    expect(restored.effectiveModel, 'new-model');
  });

  test('writes the selected variant into legacy top-level fields', () {
    final message = ChatMessage(
      role: 'assistant',
      content: 'legacy reply',
      time: originalTime,
      variants: [
        ChatReplyVariant(content: 'first reply', time: originalTime),
        ChatReplyVariant(
          content: 'selected reply',
          time: newerTime,
          endpointId: 'endpoint',
          endpointName: 'Endpoint',
          model: 'model',
        ),
      ],
      selectedVariantIndex: 1,
    );

    expect(message.toJson(), containsPair('content', 'selected reply'));
    expect(message.toJson(), containsPair('time', newerTime.toIso8601String()));
    expect(message.toJson(), containsPair('endpointId', 'endpoint'));
    expect(message.toJson(), containsPair('endpointName', 'Endpoint'));
    expect(message.toJson(), containsPair('model', 'model'));
  });

  test('falls back to legacy content when variants are malformed or empty', () {
    final message = ChatMessage.fromJson({
      'role': 'assistant',
      'content': 'legacy reply',
      'time': originalTime.toIso8601String(),
      'variants': [
        null,
        'broken',
        {'content': '   '},
      ],
      'selectedVariantIndex': 0,
    });

    expect(message.variantCount, 0);
    expect(message.effectiveContent, 'legacy reply');
    expect(message.toJson().containsKey('variants'), isFalse);
  });
}
