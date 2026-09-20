import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';

void main() {
  test(
    'selection scans invalid candidates and clamps without materializing lists',
    () {
      final variants = _NoMaterializeVariants([
        ChatReplyVariant(content: ' ', time: DateTime(2026)),
        ChatReplyVariant(content: 'A', time: DateTime(2026)),
        ChatReplyVariant(content: '', time: DateTime(2026)),
        ChatReplyVariant(content: 'B', time: DateTime(2026)),
      ]);
      final message = ChatMessage(
        role: 'assistant',
        content: 'old',
        time: DateTime(2026),
        variants: variants,
        selectedVariantIndex: 8,
      );
      expect(message.selectedVariant?.content, 'B');
      expect(message.selectedVariantIndex, 1);
      expect(message.variantCount, 2);
      expect(
        message.copyWith(selectedVariantIndex: -1).selectedVariant?.content,
        'A',
      );
    },
  );
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
    expect(message.innerVoice, isEmpty);
    expect(message.effectiveInnerVoice, isEmpty);
  });

  test('round trips top-level inner voice without variants', () {
    final message = ChatMessage(
      role: 'assistant',
      content: 'reply',
      innerVoice: 'unsaid thought',
      time: originalTime,
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.innerVoice, 'unsaid thought');
    expect(restored.effectiveInnerVoice, 'unsaid thought');
    expect(restored.toJson()['innerVoice'], 'unsaid thought');
  });

  test('selected variant owns its inner voice even when empty', () {
    final message = ChatMessage(
      role: 'assistant',
      content: 'legacy reply',
      innerVoice: 'legacy voice',
      time: originalTime,
      variants: [
        ChatReplyVariant(
          content: 'first reply',
          innerVoice: 'first voice',
          time: originalTime,
        ),
        ChatReplyVariant(content: 'second reply', time: newerTime),
      ],
      selectedVariantIndex: 1,
    );

    expect(message.effectiveContent, 'second reply');
    expect(message.effectiveInnerVoice, isEmpty);
    expect(message.toJson().containsKey('innerVoice'), isFalse);

    final first = message.copyWith(selectedVariantIndex: 0);
    expect(first.effectiveContent, 'first reply');
    expect(first.effectiveInnerVoice, 'first voice');

    final restored = ChatMessage.fromJson(first.toJson());
    expect(restored.variants.first.innerVoice, 'first voice');
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
    expect(message.effectiveInnerVoice, isEmpty);
  });

  test('reply variant inner voice is optional and round trips', () {
    final variant = ChatReplyVariant(
      content: 'reply',
      innerVoice: 'voice',
      time: newerTime,
    );

    expect(ChatReplyVariant.fromJson(variant.toJson()).innerVoice, 'voice');
    expect(
      ChatReplyVariant.fromJson({
        'content': 'legacy',
        'time': originalTime.toIso8601String(),
      }).innerVoice,
      isEmpty,
    );
    expect(
      ChatReplyVariant(
        content: 'empty',
        time: originalTime,
      ).toJson().containsKey('innerVoice'),
      isFalse,
    );
  });
}

class _NoMaterializeVariants extends ListBase<ChatReplyVariant> {
  _NoMaterializeVariants(this.items);
  final List<ChatReplyVariant> items;
  @override
  int get length => items.length;
  @override
  set length(int value) => items.length = value;
  @override
  ChatReplyVariant operator [](int index) => items[index];
  @override
  void operator []=(int index, ChatReplyVariant value) => items[index] = value;
  @override
  Iterable<ChatReplyVariant> where(bool Function(ChatReplyVariant) test) =>
      throw StateError('selection should not allocate filtered iterables');
}
