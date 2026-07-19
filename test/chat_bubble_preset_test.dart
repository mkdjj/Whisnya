import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';

void main() {
  test('image bubble preset json round trips sides and source metadata', () {
    final preset = ChatBubblePreset(
      id: 'bubble-stars',
      name: '星星',
      appearance: const ChatBubbleAppearance(
        backgroundColor: 0xFF123456,
        textColor: 0xFFFFFFFF,
        opacity: 0.4,
        imageSkin: ChatBubbleImageSkin(
          imagePath: '/app_data/media/bubble_skins/stars.png',
          imageWidth: 128,
          imageHeight: 96,
          stretchRegion: BubbleNormalizedRect(
            left: 0.2,
            top: 0.3,
            right: 0.7,
            bottom: 0.8,
          ),
          fillRegion: BubbleNormalizedRect(
            left: 0.1,
            top: 0.2,
            right: 0.9,
            bottom: 0.85,
          ),
          textPadding: BubbleContentInsets(
            left: 18,
            top: 12,
            right: 24,
            bottom: 10,
          ),
        ),
      ),
      userAppearance: const ChatBubbleAppearance(
        imageSkin: ChatBubbleImageSkin(
          imagePath: '/app_data/media/bubble_skins/stars/user.png',
          imageWidth: 96,
          imageHeight: 72,
        ),
      ),
      author: '作者',
      license: 'CC0',
      sourceDescription: 'ZIP 导入',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 2),
    );

    final restored = ChatBubblePreset.fromJson(preset.toJson());

    expect(restored.toJson(), preset.toJson());
    expect(restored.appearance.isImageSkin, isTrue);
    expect(restored.userAppearance!.imageSkin!.imagePath, endsWith('user.png'));
    expect(restored.author, '作者');
    expect(restored.license, 'CC0');
    expect(restored.createdAt, DateTime.utc(2026));
    expect(
      restored.appearance.imageSkin!.fillRegion.mirrored.left,
      closeTo(0.1, 0.000001),
    );
    expect(restored.appearance.imageSkin!.textPadding.mirrored.left, 24);
    expect(restored.appearance.imageSkin!.textPadding.mirrored.right, 18);
  });

  test('old preset json keeps one shared appearance and epoch metadata', () {
    final restored = ChatBubblePreset.fromJson({
      'id': 'old',
      'name': '旧预设',
      'appearance': const ChatBubbleAppearance(
        style: ChatBubbleStyle.square,
      ).toJson(),
    });

    expect(restored.userAppearance, isNull);
    expect(restored.author, isEmpty);
    expect(
      restored.createdAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test(
    'resolver supports built in ids without replacing colors or opacity',
    () {
      const fallback = ChatBubbleAppearance(
        backgroundColor: 0xFF112233,
        opacity: 0.4,
        imageSkin: ChatBubbleImageSkin(
          imagePath: 'skin.png',
          imageWidth: 32,
          imageHeight: 32,
        ),
      );

      final resolved = resolveBubbleAppearance(
        presetId: builtInBubblePresetId(ChatBubbleStyle.square),
        presets: const ChatBubblePresetSettings(),
        isUser: false,
        fallback: fallback,
      );

      expect(resolved.style, ChatBubbleStyle.square);
      expect(resolved.backgroundColor, 0xFF112233);
      expect(resolved.opacity, 0.4);
      expect(resolved.imageSkin, isNull);
    },
  );

  test('user presets exclude legacy migration entries', () {
    ChatBubblePreset preset(String id) => ChatBubblePreset(
      id: id,
      name: id,
      appearance: const ChatBubbleAppearance(),
    );

    final settings = ChatBubblePresetSettings(
      presets: [
        preset('character_legacy_bubble_alice_role'),
        preset('theater_legacy_bubble_group_user'),
        preset('bubble_custom'),
      ],
    );

    expect(settings.userPresets.map((preset) => preset.id), ['bubble_custom']);
  });

  test('resolver selects the requested side of an imported preset', () {
    final settings = ChatBubblePresetSettings(
      presets: [
        ChatBubblePreset(
          id: 'pair',
          name: '双图',
          appearance: const ChatBubbleAppearance(backgroundColor: 0xFF112233),
          userAppearance: const ChatBubbleAppearance(
            backgroundColor: 0xFF445566,
          ),
        ),
      ],
    );

    expect(
      resolveBubbleAppearance(
        presetId: 'pair',
        presets: settings,
        isUser: false,
      ).backgroundColor,
      0xFF112233,
    );
    expect(
      resolveBubbleAppearance(
        presetId: 'pair',
        presets: settings,
        isUser: true,
      ).backgroundColor,
      0xFF445566,
    );
  });

  test('removed global default fields are ignored instead of rewritten', () {
    final settings = ChatBubblePresetSettings.fromJson({
      'defaultRolePresetId': 'old-role',
      'defaultUserPresetId': 'old-user',
      'presets': <dynamic>[],
    });

    expect(settings.toJson(), {'presets': <dynamic>[]});
  });

  test('preset references read the latest edited global appearance', () {
    final original = ChatBubblePreset(
      id: 'shared',
      name: 'shared',
      appearance: const ChatBubbleAppearance(opacity: 0.2),
    );
    final settings = ChatBubblePresetSettings(presets: [original]);
    final edited = settings.copyWith(
      presets: [
        original.copyWith(
          appearance: original.appearance.copyWith(opacity: 0.8),
        ),
      ],
    );

    expect(
      resolveBubbleAppearance(
        presetId: 'shared',
        presets: edited,
        isUser: false,
      ).opacity,
      0.8,
    );
  });
}
