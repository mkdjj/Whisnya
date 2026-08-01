import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/screens/chat/chat_screen.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets('character chat resolves its built-in bubble style', (
    tester,
  ) async {
    final storage = _ApiStorage(_config(model: 'model', apiKey: 'key'));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'openingMessage': 'hello',
            'roleBubblePresetId': builtInBubblePresetId(ChatBubbleStyle.square),
            'bubbleTheme': {
              'role': {'backgroundColor': 0xFF123456},
            },
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bubble = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chat-bubble-square')),
    );
    expect(
      (bubble.decoration as BoxDecoration).color,
      const Color(0xFF123456).withValues(alpha: 0.92),
    );
  });

  testWidgets('character role output can render as continuous bubbles', (
    tester,
  ) async {
    final storage = _ApiStorage(
      _config(model: 'model', apiKey: 'key'),
      chat: [
        ChatMessage(
          role: 'assistant',
          content: 'love\n(hug)\nbaby',
          time: DateTime(2026),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'roleBubblePresetId': builtInBubblePresetId(ChatBubbleStyle.square),
          }),
          settings: const AppSettings(splitRoleMessages: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-bubble-square')), findsNWidgets(3));
  });

  testWidgets('character background slider maps opacity directly', (
    tester,
  ) async {
    final storage = _ApiStorage(_config(model: 'model', apiKey: 'key'));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'backgroundImageOpacity': 0.25,
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final setting = find.byKey(
      const ValueKey('chat-background-transparency-setting'),
    );
    await tester.scrollUntilVisible(
      setting,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final slider = tester.widget<Slider>(
      find.descendant(of: setting, matching: find.byType(Slider)),
    );
    expect(slider.value, 0.25);
    slider.onChanged!(1);
    slider.onChangeEnd!(1);
    await tester.pump();
    expect(storage.savedCharacters.last.backgroundImageOpacity, 1);

    slider.onChanged!(0);
    slider.onChangeEnd!(0);
    await tester.pump();
    expect(storage.savedCharacters.last.backgroundImageOpacity, 0);
  });

  testWidgets('character top bar follows opacity and exposes transparency', (
    tester,
  ) async {
    final storage = _ApiStorage(_config(model: 'model', apiKey: 'key'));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'topBarOpacity': 0.25,
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(
      find.byKey(const ValueKey('character-chat-app-bar')),
    );
    expect(appBar.backgroundColor!.a, closeTo(0.25, 0.001));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final setting = find.byKey(
      const ValueKey('chat-top-bar-transparency-setting'),
    );
    await tester.scrollUntilVisible(
      setting,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .widget<Slider>(
            find.descendant(of: setting, matching: find.byType(Slider)),
          )
          .value,
      0.75,
    );
  });

  testWidgets('character bubble preset settings follow input opacity', (
    tester,
  ) async {
    final storage = _ApiStorage(_config(model: 'model', apiKey: 'key'));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'openingMessage': 'hello',
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final rolePreset = find.byKey(
      const ValueKey('chat-role-bubble-preset-setting'),
    );
    await tester.scrollUntilVisible(
      rolePreset,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(rolePreset, findsOneWidget);

    final settings = tester.widget<ListView>(find.byType(ListView).last);
    final children =
        (settings.childrenDelegate as SliverChildListDelegate).children;
    expect(
      children.map((child) => child.key),
      containsAllInOrder(const [
        ValueKey('chat-input-opacity-setting'),
        ValueKey('chat-role-bubble-preset-setting'),
        ValueKey('chat-role-bubble-transparency-setting'),
        ValueKey('chat-user-bubble-preset-setting'),
        ValueKey('chat-user-bubble-transparency-setting'),
        ValueKey('chat-export-history-setting'),
        ValueKey('chat-clear-history-setting'),
      ]),
    );

    final roleTransparency = find.byKey(
      const ValueKey('chat-role-bubble-transparency-setting'),
    );
    await tester.scrollUntilVisible(
      roleTransparency,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final slider = tester.widget<Slider>(
      find.descendant(of: roleTransparency, matching: find.byType(Slider)),
    );
    slider.onChanged!(0.7);
    slider.onChangeEnd!(0.7);
    await tester.pump();
    expect(storage.savedCharacters.last.roleBubbleOpacity, closeTo(0.3, 0.001));

    Navigator.of(tester.element(roleTransparency)).pop();
    await tester.pumpAndSettle();
    final bubble = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chat-bubble-rounded')),
    );
    expect((bubble.decoration as BoxDecoration).color!.a, closeTo(0.3, 0.001));
  });

  testWidgets('character chat reloads edited API before sending', (
    tester,
  ) async {
    final storage = _ApiStorage(_config(model: 'old-model', apiKey: 'old-key'));
    final gateway = _RecordingGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: gateway,
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'defaultEndpointId': 'endpoint',
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    storage.config = _config(model: 'new-model', apiKey: 'new-key');
    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.tap(find.byIcon(Icons.send));
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(storage.loadApiConfigCalls, greaterThanOrEqualTo(2));
    expect(storage.saveChatCalls, greaterThanOrEqualTo(1));
    expect(gateway.model, 'new-model');
    expect(gateway.apiKey, 'new-key');
  });

  testWidgets('character chat reloads edited user profile before sending', (
    tester,
  ) async {
    final storage = _ApiStorage(
      _config(model: 'model', apiKey: 'key'),
      settings: const AppSettings(userProfile: UserProfile(name: '旧名字')),
    );
    final gateway = _RecordingGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: gateway,
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'defaultEndpointId': 'endpoint',
          }),
          settings: storage.settings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    storage.settings = const AppSettings(
      userProfile: UserProfile(
        name: '新名字',
        description: '旅行者',
        avatar: r'E:\private\avatar.png',
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.tap(find.byIcon(Icons.send));
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final prompt = gateway.messages!.first['content']!;
    expect(prompt, contains('名称：新名字'));
    expect(prompt, contains('身份简介：旅行者'));
    expect(prompt, isNot(contains('旧名字')));
    expect(prompt, isNot(contains('avatar.png')));
  });

  testWidgets('character chat restores input when the initial save fails', (
    tester,
  ) async {
    final storage = _ApiStorage(
      _config(model: 'model', apiKey: 'key'),
      failSaveChat: true,
    );
    final gateway = _RecordingGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: gateway,
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'defaultEndpointId': 'endpoint',
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'hello',
    );
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
    expect(gateway.messages, isNull);
    expect(find.textContaining('save failed'), findsOneWidget);
  });

  testWidgets('edit and resend rolls back when saving the edit fails', (
    tester,
  ) async {
    final storage = _ApiStorage(
      _config(model: 'model', apiKey: 'key'),
      chat: [
        ChatMessage(role: 'user', content: 'original', time: DateTime(2026)),
        ChatMessage(role: 'assistant', content: 'reply', time: DateTime(2026)),
      ],
      failSaveChat: true,
    );
    final gateway = _RecordingGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: gateway,
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'defaultEndpointId': 'endpoint',
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'edited');
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('original'), findsOneWidget);
    expect(find.text('reply'), findsOneWidget);
    expect(find.text('edited'), findsNothing);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
    expect(gateway.messages, isNull);
    expect(find.textContaining('save failed'), findsOneWidget);
  });

  testWidgets('deleting one character message requires confirmation', (
    tester,
  ) async {
    final storage = _ApiStorage(
      _config(model: 'model', apiKey: 'key'),
      chat: [
        ChatMessage(role: 'user', content: 'original', time: DateTime(2026)),
        ChatMessage(role: 'assistant', content: 'reply', time: DateTime(2026)),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
            'defaultEndpointId': 'endpoint',
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(storage.saveChatCalls, 0);

    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(storage.saveChatCalls, 1);
    expect(find.text('reply'), findsNothing);
  });
}

ApiConfig _config({required String model, required String apiKey}) => ApiConfig(
  endpoints: [
    AiEndpointConfig(
      id: 'endpoint',
      name: 'Endpoint',
      apiKey: apiKey,
      baseUrl: 'https://example.test/v1',
      model: model,
      enabled: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ],
  defaultEndpointId: 'endpoint',
);

final class _ApiStorage extends LocalStorageService {
  _ApiStorage(
    this.config, {
    this.settings = const AppSettings(),
    List<ChatMessage> chat = const [],
    this.failSaveChat = false,
  }) : chat = [...chat],
       super();

  ApiConfig config;
  AppSettings settings;
  final List<ChatMessage> chat;
  final bool failSaveChat;
  var loadApiConfigCalls = 0;
  var saveChatCalls = 0;
  final savedCharacters = <AppCharacter>[];

  @override
  Future<ApiConfig> loadApiConfig() async {
    loadApiConfigCalls++;
    return config;
  }

  @override
  Future<AppSettings> loadSettings() async => settings;

  @override
  Future<ChatSummary> loadSummary(String characterId) async =>
      ChatSummary.empty(characterId);

  @override
  Future<List<ChatMessage>> loadChat(String characterId) async => [...chat];

  @override
  Future<void> saveChat(String characterId, List<ChatMessage> messages) async {
    saveChatCalls++;
    if (failSaveChat) throw StateError('save failed');
  }

  @override
  Future<void> saveCharacter(AppCharacter character) async {
    savedCharacters.add(character);
  }

  @override
  Future<void> recordAiUsage({
    required String requestType,
    required String model,
    required AiUsage usage,
    required List<Map<String, String>> messages,
    required bool summaryUpdated,
  }) async {}
}

final class _RecordingGateway implements AiGateway {
  String? model;
  String? apiKey;
  List<Map<String, String>>? messages;

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) async => 'ok';

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) async* {
    this.apiKey = apiKey;
    this.model = model;
    this.messages = messages;
    yield 'ok';
  }
}
