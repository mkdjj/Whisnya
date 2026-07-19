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

  test('chat top bar opacity defaults to transparent and round trips', () {
    final defaultCharacter = AppCharacter.fromJson({'id': 'c'});
    final character = defaultCharacter.copyWith(topBarOpacity: 0.4);
    final theater = TheaterSession.fromJson({'id': 't', 'topBarOpacity': 0.6});

    expect(defaultCharacter.topBarOpacity, 0);
    expect(AppCharacter.fromJson(character.toJson()).topBarOpacity, 0.4);
    expect(theater.topBarOpacity, 0.6);
  });

  test('character endpoint id round trips without mapping', () {
    const id = 'private-openai-compatible-node';
    final json = AppCharacter.fromJson({
      'id': 'c',
      'defaultEndpointId': id,
    }).toJson();

    expect(json['defaultEndpointId'], id);
    expect(AppCharacter.fromJson(json).defaultEndpointId, id);
  });

  test('character and theater bubble preset ids round trip', () {
    final character = AppCharacter.fromJson({
      'id': 'c',
      'roleBubblePresetId': 'role-preset',
      'userBubblePresetId': 'user-preset',
    });
    final theater = TheaterSession.fromJson({
      'id': 't',
      'roleBubblePresetId': 'theater-role',
      'userBubblePresetId': 'theater-user',
    });

    expect(character.roleBubblePresetId, 'role-preset');
    expect(character.userBubblePresetId, 'user-preset');
    expect(
      AppCharacter.fromJson(character.toJson()).roleBubblePresetId,
      'role-preset',
    );
    expect(theater.roleBubblePresetId, 'theater-role');
    expect(theater.userBubblePresetId, 'theater-user');
    expect(
      TheaterSession.fromJson(theater.toJson()).userBubblePresetId,
      'theater-user',
    );
  });
}
