import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/screens/character_edit_screen.dart';
import 'package:whisnya/screens/settings_screen.dart';
import 'package:whisnya/screens/theater/theater_screens.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/chat_bubble_preset_picker.dart';

void main() {
  testWidgets(
    'role subpage refreshes dependent switches and persists changes',
    (tester) async {
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
      await tester.tap(find.text('角色状态与语音'));
      await tester.pumpAndSettle();
      final auto = find.widgetWithText(SwitchListTile, '自动更新角色状态');
      expect(tester.widget<SwitchListTile>(auto).onChanged, isNull);
      await tester.tap(find.text('显示角色状态卡'));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(auto).onChanged, isNotNull);
      await tester.tap(auto);
      await tester.pumpAndSettle();
      expect(storage.savedSettings.last.autoUpdateCharacterState, isTrue);
      expect(storage.savedSettings.last.showCharacterStateCard, isTrue);
      expect(tester.widget<SwitchListTile>(auto).value, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings hides global custom bubble management', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: SettingsScreen(
            storage: _MemoryStorage(),
            settings: const AppSettings(),
            onSettingsChanged: () async {},
          ),
        ),
      ),
    );

    expect(find.text('聊天气泡'), findsNothing);
  });

  testWidgets('character inner voice sits between reasoning and bubbles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    await tester.tap(find.text('聊天与回复'));
    await tester.pumpAndSettle();
    final reasoning = find.byKey(const ValueKey('show-reasoning-setting'));
    final innerVoice = find.byKey(
      const ValueKey('show-character-inner-voice-setting'),
    );
    final continuous = find.byKey(
      const ValueKey('split-role-messages-setting'),
    );
    expect(reasoning, findsOneWidget);
    expect(innerVoice, findsOneWidget);
    expect(continuous, findsOneWidget);
    final stateCard = find.text('显示角色状态卡');
    expect(stateCard, findsNothing);
    expect(
      tester.getTopLeft(innerVoice).dy,
      greaterThan(tester.getTopLeft(reasoning).dy),
    );
    expect(
      tester.getTopLeft(continuous).dy,
      greaterThan(tester.getTopLeft(innerVoice).dy),
    );

    await tester.tap(innerVoice);
    await tester.pump();
    expect(storage.savedSettings.last.showCharacterInnerVoice, isTrue);
    expect(tester.widget<SwitchListTile>(innerVoice).value, isTrue);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天与回复'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(innerVoice).value, isTrue);
  });

  testWidgets('settings exposes the memory context character limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: SettingsScreen(
            storage: _MemoryStorage(),
            settings: const AppSettings(),
            onSettingsChanged: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('记忆与收藏'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('memory-context-limit-setting')),
      findsOneWidget,
    );
    expect(find.text('记忆上下文上限'), findsOneWidget);
    expect(find.text('每次最多注入 4000 个字符'), findsOneWidget);
  });
  testWidgets('preset picker offers only ten built-ins', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      ),
      findsNWidgets(ChatBubbleStyle.values.length),
    );

    await tester.tap(find.text('极简方角'));
    await tester.pumpAndSettle();
    expect(selected, builtInBubblePresetId(ChatBubbleStyle.square));
  });

  testWidgets('character and theater editors use built-in bubble pickers', (
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

    await tester.pumpWidget(app(TheaterEditScreen(storage: storage)));
    await tester.pumpAndSettle();
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
  });
}

final class _MemoryStorage extends LocalStorageService {
  final savedSettings = <AppSettings>[];

  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig();

  @override
  Future<List<AppCharacter>> loadCharacters() async => const [];

  @override
  Future<List<NovelBook>> loadNovels() async => const [];

  @override
  Future<void> saveSettings(AppSettings settings) async {
    savedSettings.add(settings);
  }
}
