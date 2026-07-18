import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/models/theater.dart';

void main() {
  test('bubble theme round trips every style and nullable colors', () {
    for (final style in ChatBubbleStyle.values) {
      final theme = ChatBubbleTheme(
        role: ChatBubbleAppearance(style: style, opacity: 0.5),
        user: ChatBubbleAppearance(
          style: style,
          backgroundColor: 0xFF123456,
          textColor: 0xFFABCDEF,
          opacity: 0,
        ),
      );
      final restored = ChatBubbleTheme.fromJson(theme.toJson());
      expect(restored.role.style, style);
      expect(restored.role.backgroundColor, isNull);
      expect(restored.user.toJson(), theme.user.toJson());
    }
  });

  test('unknown style falls back and opacity clamps', () {
    final theme = ChatBubbleTheme.fromJson({
      'role': {'style': 'unknown', 'opacity': -1},
      'user': {'style': 'rounded', 'opacity': 2},
    });
    expect(theme.role.style, ChatBubbleStyle.rounded);
    expect(theme.role.opacity, 0);
    expect(theme.user.opacity, 1);
    expect(ChatBubbleAppearance(opacity: -1).opacity, 0);
    expect(ChatBubbleAppearance(opacity: 2).opacity, 1);
  });

  test('legacy character and theater opacity maps to both sides', () {
    final character = AppCharacter.fromJson({'id': 'c', 'bubbleOpacity': 0.3});
    final theater = TheaterSession.fromJson({'id': 't', 'bubbleOpacity': 0.6});
    expect(character.bubbleTheme.role.opacity, 0.3);
    expect(character.bubbleTheme.user.opacity, 0.3);
    expect(theater.bubbleTheme.role.opacity, 0.6);
    expect(theater.bubbleTheme.user.opacity, 0.6);
    expect(character.toJson(), isNot(contains('bubbleOpacity')));
    expect(theater.toJson(), isNot(contains('bubbleOpacity')));
  });

  test('character and theater preserve new bubble theme json', () {
    const theme = ChatBubbleTheme(
      role: ChatBubbleAppearance(
        style: ChatBubbleStyle.comic,
        backgroundColor: 0xFF123456,
        textColor: 0xFFFFFFFF,
        opacity: 0.4,
      ),
      user: ChatBubbleAppearance(style: ChatBubbleStyle.textOnly, opacity: 0),
    );
    final character = AppCharacter.fromJson({
      'id': 'c',
      'bubbleTheme': theme.toJson(),
    });
    final theater = TheaterSession.fromJson({
      'id': 't',
      'bubbleTheme': theme.toJson(),
    });
    expect(character.bubbleTheme.toJson(), theme.toJson());
    expect(theater.bubbleTheme.toJson(), theme.toJson());
  });
}
