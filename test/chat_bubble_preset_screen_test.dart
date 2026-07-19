import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/screens/chat_bubble_preset_screen.dart';
import 'package:whisnya/screens/character_edit_screen.dart';
import 'package:whisnya/screens/settings_screen.dart';
import 'package:whisnya/screens/theater/theater_screens.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/chat_bubble_preset_picker.dart';

void main() {
  testWidgets('settings opens the global chat bubble preset list', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: SettingsScreen(
            storage: storage,
            settings: const AppSettings(),
            onSettingsChanged: () async {},
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('聊天气泡'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('聊天气泡'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatBubblePresetScreen), findsOneWidget);
    expect(find.text('新建气泡'), findsOneWidget);
  });

  testWidgets('preset list only manages user-created presets', (tester) async {
    ChatBubblePreset preset(String id, String name) => ChatBubblePreset(
      id: id,
      name: name,
      appearance: const ChatBubbleAppearance(),
    );
    final storage = _MemoryStorage(
      ChatBubblePresetSettings(
        presets: [
          preset('character_legacy_bubble_alice_role', '爱丽丝旧气泡'),
          preset('bubble_custom', '蓝色星星'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: ChatBubblePresetScreen(storage: storage),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝色星星'), findsOneWidget);
    expect(find.text('爱丽丝旧气泡'), findsNothing);
    expect(find.text('角色预览'), findsNothing);
    expect(find.text('我的预览'), findsNothing);
    expect(find.text('默认角色'), findsNothing);
    expect(find.text('默认我的'), findsNothing);
  });

  testWidgets('preset picker offers ten built-ins then user presets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preset = ChatBubblePreset(
      id: 'bubble_custom',
      name: '自定义星星',
      appearance: const ChatBubbleAppearance(),
    );
    var selected = '';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: ChatBubblePresetSelectionTile(
            title: '角色气泡',
            presetId: selected,
            presets: ChatBubblePresetSettings(presets: [preset]),
            isUser: false,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('角色气泡'));
    await tester.pumpAndSettle();
    for (final style in ChatBubbleStyle.values) {
      expect(find.text(chatBubbleStyleLabel(style)), findsWidgets);
    }
    expect(find.text('自定义星星'), findsOneWidget);
    expect(find.text('使用全局默认'), findsNothing);
    await tester.tap(find.text('极简方角'));
    await tester.pumpAndSettle();

    expect(selected, builtInBubblePresetId(ChatBubbleStyle.square));
  });

  testWidgets('PNG editor is compact and range changes move visible regions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory directory;
    final file = await tester.runAsync<File>(() async {
      directory = await Directory.systemTemp.createTemp('bubble-editor-');
      final file = File('${directory.path}${Platform.pathSeparator}skin.png');
      await file.writeAsBytes(
        img.encodePng(img.Image(width: 120, height: 80, numChannels: 4)),
      );
      return file;
    });
    addTearDown(() => directory.delete(recursive: true));
    final preset = ChatBubblePreset(
      id: 'bubble_skin',
      name: '图片气泡',
      appearance: ChatBubbleAppearance(
        imageSkin: ChatBubbleImageSkin(
          imagePath: file!.path,
          imageWidth: 120,
          imageHeight: 80,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: ChatBubblePresetScreen(
          storage: _MemoryStorage(ChatBubblePresetSettings(presets: [preset])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sourcePreview = find.byKey(
      const ValueKey('bubble-skin-region-preview'),
    );
    final stretchRegion = find.byKey(
      const ValueKey('bubble-skin-stretch-region'),
    );
    final fillRegion = find.byKey(const ValueKey('bubble-skin-fill-region'));
    expect(sourcePreview, findsOneWidget);
    expect(stretchRegion, findsOneWidget);
    expect(fillRegion, findsOneWidget);
    final sourceSize = tester.getSize(sourcePreview);
    expect(sourceSize.width, lessThanOrEqualTo(280));
    expect(sourceSize.height, lessThanOrEqualTo(180));

    final decorations = find.byKey(
      const ValueKey('chat-bubble-image-decoration'),
    );
    expect(decorations, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      final size = tester.getSize(decorations.at(index));
      expect(size.width, lessThanOrEqualTo(180));
      expect(size.height, lessThanOrEqualTo(96));
    }

    final before = tester.getRect(stretchRegion);
    tester.widget<RangeSlider>(find.byType(RangeSlider).first).onChanged!(
      const RangeValues(0.15, 0.85),
    );
    await tester.pump();
    expect(tester.getRect(stretchRegion), isNot(before));
  });

  testWidgets('character and theater editors only select global presets', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    MaterialApp app(Widget home) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: home,
    );

    await tester.pumpWidget(app(CharacterEditScreen(storage: storage)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('角色气泡'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('角色气泡'), findsOneWidget);
    expect(find.text('我的气泡'), findsOneWidget);
    expect(find.text('上传透明 PNG'), findsNothing);

    await tester.pumpWidget(
      app(TheaterEditScreen(storage: storage, aiService: AiService())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Scrollable), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('群聊外观'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('群聊外观'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('AI 共用气泡'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AI 共用气泡'), findsOneWidget);
    expect(find.text('我的气泡'), findsOneWidget);
    expect(find.text('上传透明 PNG'), findsNothing);
  });
}

final class _MemoryStorage extends LocalStorageService {
  _MemoryStorage([this.settings = const ChatBubblePresetSettings()]);

  ChatBubblePresetSettings settings;

  @override
  Future<ChatBubblePresetSettings> loadChatBubblePresets() async => settings;

  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig();

  @override
  Future<List<AppCharacter>> loadCharacters() async => const [];

  @override
  Future<List<NovelBook>> loadNovels() async => const [];

  @override
  Future<void> saveChatBubblePresets(ChatBubblePresetSettings value) async {
    settings = value;
  }

  @override
  Future<ChatBubblePresetReferences> bubblePresetReferences(
    String presetId,
  ) async => const ChatBubblePresetReferences();
}
