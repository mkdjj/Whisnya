import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/screens/chat/chat_screen.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets('character bubble settings follow input opacity', (tester) async {
    final storage = _ApiStorage(_config(model: 'model', apiKey: 'key'));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: AppCharacter.fromJson({
            'id': 'character',
            'name': 'Character',
          }),
          settings: const AppSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final expansion = find.byKey(const ValueKey('chat-bubble-theme-expansion'));
    await tester.scrollUntilVisible(
      expansion,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.widget<ExpansionTile>(expansion).initiallyExpanded, isFalse);

    final settings = tester.widget<ListView>(find.byType(ListView).last);
    final children =
        (settings.childrenDelegate as SliverChildListDelegate).children;
    expect(
      children.map((child) => child.key),
      containsAllInOrder(const [
        ValueKey('chat-input-opacity-setting'),
        ValueKey('chat-bubble-theme-expansion'),
        ValueKey('chat-clear-history-setting'),
      ]),
    );
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
  _ApiStorage(this.config, {this.settings = const AppSettings()}) : super();

  ApiConfig config;
  AppSettings settings;
  var loadApiConfigCalls = 0;
  var saveChatCalls = 0;

  @override
  Future<void> markCharacterUsed(String characterId) async {}

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
  Future<ChatSession> loadChat(String characterId) async =>
      ChatSession.empty(characterId);

  @override
  Future<void> saveChat(String characterId, List<ChatMessage> messages) async {
    saveChatCalls++;
  }

  @override
  Future<void> saveCharacter(AppCharacter character) async {}

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
