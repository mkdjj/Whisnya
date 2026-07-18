import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/screens/chat/chat_screen.dart';
import 'package:whisnya/screens/home_screen.dart';
import 'package:whisnya/screens/novel/novel_screens.dart';
import 'package:whisnya/screens/settings_screen.dart';
import 'package:whisnya/screens/theater/theater_screens.dart';
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

  for (final entry in const [(0.0, 0), (0.5, 128), (1.0, 255)]) {
    testWidgets('character card opacity ${entry.$1}', (tester) async {
      final colorScheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: entry.$1 == 0.5 ? Brightness.dark : Brightness.light,
      );
      final storage = _TrackingStorage(
        characters: [
          AppCharacter.fromJson({'id': 'character', 'name': 'Character'}),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: colorScheme),
          home: HomeScreen(
            storage: storage,
            aiService: AiService(
              client: MockClient((request) async => throw UnimplementedError()),
            ),
            settings: AppSettings(characterListCardOpacity: entry.$1),
            onSettingsChanged: () async {},
          ),
        ),
      );
      await _pumpFrames(tester);

      final card = tester.widget<Card>(
        find.byKey(const ValueKey('character-card-character')),
      );
      expect(card.color?.a, closeTo(entry.$2 / 255, 0.01));
      expect(card.color?.withValues(alpha: 1), colorScheme.surface);
      expect(find.text('Character'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Character'),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });
  }

  testWidgets('list card opacity affects novel and theater lists', (
    tester,
  ) async {
    final now = DateTime(2026);
    final storage = _TrackingStorage(
      novels: [
        NovelBook(
          id: 'novel',
          title: 'Novel',
          textPath: 'novel.txt',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      theaterSessions: [
        TheaterSession(
          id: 'theater',
          title: 'Theater',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          storage: storage,
          aiService: AiService(
            client: MockClient((request) async => throw UnimplementedError()),
          ),
          settings: const AppSettings(characterListCardOpacity: 0.5),
          onSettingsChanged: () async {},
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await _pumpFrames(tester);
    final novelCard = tester.widget<Card>(
      find.byKey(const ValueKey('novel-card-novel')),
    );
    expect(novelCard.color?.a, closeTo(0.5, 0.01));

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await _pumpFrames(tester);
    final theaterCardFinder = find.byKey(
      const ValueKey('theater-card-theater'),
    );
    final theaterCard = tester.widget<Card>(theaterCardFinder);
    expect(theaterCard.color?.a, closeTo(0.5, 0.01));

    await tester.tap(
      find.descendant(
        of: theaterCardFinder,
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await _pumpFrames(tester);
    expect(
      find.textContaining(RegExp('编辑群聊|Edit theater chat')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final class _TrackingStorage extends LocalStorageService {
  _TrackingStorage({
    this.characters = const [],
    this.novels = const [],
    this.theaterSessions = const [],
  }) : super();

  final List<AppCharacter> characters;
  final List<NovelBook> novels;
  final List<TheaterSession> theaterSessions;

  var markCharacterUsedCalls = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<List<AppCharacter>> loadCharacters() async => characters;

  @override
  List<String> takeRecoveryMessages() => const [];

  @override
  Future<List<NovelBook>> loadNovels() async => novels;

  @override
  Future<List<TheaterSession>> loadTheaterSessions() async => theaterSessions;

  @override
  Future<AppSettings> loadSettings() async => const AppSettings();

  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig();

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
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) async => '';

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
  }) => const Stream.empty();
}
