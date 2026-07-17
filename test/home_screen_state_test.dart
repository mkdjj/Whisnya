import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/screens/chat_screen.dart';
import 'package:whisnya/screens/home_screen.dart';
import 'package:whisnya/screens/novel_screen.dart';
import 'package:whisnya/screens/settings_screen.dart';
import 'package:whisnya/screens/theater_screen.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets('home mounts tabs on first visit and keeps them mounted', (
    tester,
  ) async {
    final storage = _TrackingStorage();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          storage: storage,
          aiService: AiService(
            client: MockClient((request) async => throw UnimplementedError()),
          ),
          settings: const AppSettings(),
          onSettingsChanged: () async {},
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(NovelScreen, skipOffstage: false), findsNothing);
    expect(find.byType(TheaterListScreen, skipOffstage: false), findsNothing);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await _pumpFrames(tester);
    expect(find.byType(NovelScreen, skipOffstage: false), findsOneWidget);

    await tester.tap(find.byIcon(Icons.people_outline));
    await _pumpFrames(tester);
    expect(find.byType(NovelScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('chat marks a character used once when opened', (tester) async {
    final storage = _TrackingStorage();
    final character = AppCharacter.fromJson({
      'id': 'character',
      'name': 'Character',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          storage: storage,
          aiService: _FakeGateway(),
          character: character,
          settings: const AppSettings(),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(storage.markCharacterUsedCalls, 1);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final class _TrackingStorage extends LocalStorageService {
  _TrackingStorage() : super();

  var markCharacterUsedCalls = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<List<AppCharacter>> loadCharacters() async => const [];

  @override
  List<String> takeRecoveryMessages() => const [];

  @override
  Future<List<NovelBook>> loadNovels() async => const [];

  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig.defaults();

  @override
  Future<ChatSummary> loadSummary(String characterId) async =>
      ChatSummary.empty(characterId);

  @override
  Future<ChatSession> loadChat(String characterId) async =>
      ChatSession.empty(characterId);

  @override
  Future<void> markCharacterUsed(String characterId) async {
    markCharacterUsedCalls++;
  }
}

final class _FakeGateway implements AiGateway {
  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async => '';

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) => const Stream.empty();
}
