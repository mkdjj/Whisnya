import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';

void main() {
  test('built-in bubble IDs round trip every style', () {
    for (final style in ChatBubbleStyle.values) {
      expect(builtInBubbleStyle(builtInBubblePresetId(style)), style);
    }
  });

  test('unknown old custom preset falls back to the stored appearance', () {
    const fallback = ChatBubbleAppearance(
      style: ChatBubbleStyle.note,
      backgroundColor: 0xFF123456,
      opacity: 0.8,
    );

    final resolved = resolveBubbleAppearance(
      presetId: 'old-custom-preset',
      fallback: fallback,
      opacityOverride: 0.4,
    );

    expect(resolved.style, ChatBubbleStyle.note);
    expect(resolved.backgroundColor, 0xFF123456);
    expect(resolved.opacity, 0.4);
  });

  test('legacy image skin JSON is safely read as a parameter bubble', () {
    final appearance = ChatBubbleAppearance.fromJson({
      'style': 'square',
      'opacity': 0.7,
      'renderMode': 'imageSkin',
      'imageSkin': {'imagePath': 'old.png'},
    });

    expect(appearance.style, ChatBubbleStyle.square);
    expect(appearance.opacity, 0.7);
    expect(appearance.toJson(), isNot(contains('imageSkin')));
  });
}
