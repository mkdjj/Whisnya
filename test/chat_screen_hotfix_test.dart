import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/screens/chat/chat_screen.dart';
import 'package:whisnya/screens/chat/chat_session_list_screen.dart';
import 'package:whisnya/screens/chat/memory_manager_screen.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/message_bubble_parts.dart';

void main() {
  testWidgets(
    'a cleared initialized session does not insert its opening again',
    (tester) async {
      final character = _character(openingMessage: '唯一开场白');
      final storage = _SessionStorage(
        character: character,
        sessions: [_session()],
      );

      await _pumpChat(tester, storage, character);

      expect(find.text('唯一开场白'), findsOneWidget);
      expect(storage.sessions.single.openingMessageInitialized, isTrue);
      expect(storage.chats['session']!.single.content, '唯一开场白');

      storage.chats['session'] = [];
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpChat(tester, storage, character);

      expect(find.text('唯一开场白'), findsNothing);
      expect(find.text('当前还没有聊天记录。'), findsOneWidget);
      expect(storage.chats['session'], isEmpty);
    },
  );

  testWidgets('first opening marks an empty opening message as initialized', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session()],
    );

    await _pumpChat(tester, storage, character);

    expect(storage.sessions.single.openingMessageInitialized, isTrue);
    expect(storage.chats['session'], isEmpty);
  });

  testWidgets(
    'opening initialization preserves newer stored session metadata',
    (tester) async {
      final character = _character();
      final stale = _session(title: '旧标题');
      final latest = stale.copyWith(title: '新标题', isArchived: true);
      final storage = _SessionStorage(character: character, sessions: [latest]);

      await _pumpChat(tester, storage, character, session: stale);

      final saved = storage.sessions.single;
      expect(saved.title, '新标题');
      expect(saved.isArchived, isTrue);
      expect(saved.createdAt, stale.createdAt);
      expect(saved.openingMessageInitialized, isTrue);
    },
  );

  testWidgets(
    'latest initialized state prevents opening replay from a stale session',
    (tester) async {
      final character = _character(openingMessage: '唯一开场白');
      final stale = _session();
      final latest = stale.copyWith(openingMessageInitialized: true);
      final storage = _SessionStorage(character: character, sessions: [latest]);

      await _pumpChat(tester, storage, character, session: stale);

      expect(find.text('唯一开场白'), findsNothing);
      expect(storage.chats['session'], isEmpty);
      expect(storage.sessions.single.openingMessageInitialized, isTrue);
    },
  );

  testWidgets('returning from session management refreshes the same session', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(title: '旧标题', openingMessageInitialized: true)],
    );
    await _pumpChat(tester, storage, character);

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    storage.sessions[0] = storage.sessions[0].copyWith(title: '新标题');
    Navigator.of(tester.element(find.byType(ChatSessionListScreen))).pop();
    await tester.pumpAndSettle();

    expect(find.text('新标题'), findsOneWidget);
    expect(find.text('旧标题'), findsNothing);
  });

  testWidgets('chat reads entries only for referenced enabled world books', (
    tester,
  ) async {
    final character = _character(worldBookIds: const ['book_b']);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      worldBooks: [_book('book_a'), _book('book_b'), _book('book_c')],
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '普通消息');
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(storage.loadedWorldBookEntryIds, ['book_b']);
  });

  testWidgets('chat with no world book references reads no entry files', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      worldBooks: [_book('book_a'), _book('book_b')],
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '普通消息');
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(storage.loadedWorldBookEntryIds, isEmpty);
  });

  testWidgets('chat skips entry files for referenced disabled world books', (
    tester,
  ) async {
    final character = _character(worldBookIds: const ['book_b']);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      worldBooks: [_book('book_b', enabled: false)],
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '普通消息');
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(storage.loadedWorldBookEntryIds, isEmpty);
    expect(
      gateway.messages!.map((message) => message['content']).join('\n'),
      isNot(contains('世界书命中内容')),
    );
  });

  testWidgets(
    'regeneration excludes the old assistant from world book matching',
    (tester) async {
      final character = _character(worldBookIds: const ['book_b']);
      final storage = _SessionStorage(
        character: character,
        sessions: [_session(openingMessageInitialized: true)],
        chat: [_message('user', '普通问题'), _message('assistant', '旧回复提到了天剑宗')],
        worldBooks: [_book('book_b')],
        worldBookEntries: {
          'book_b': [_worldEntry('book_b')],
        },
      );
      final gateway = _RecordingGateway();
      await _pumpChat(tester, storage, character, gateway: gateway);

      await tester.tap(find.text('重新生成'));
      await _pumpUntil(tester, () => gateway.messages != null);

      final request = gateway.messages!
          .map((message) => message['content'])
          .join('\n');
      expect(request, contains('普通问题'));
      expect(request, isNot(contains('旧回复提到了天剑宗')));
      expect(request, isNot(contains('世界书命中内容')));
    },
  );

  testWidgets('regeneration still matches a keyword from the user context', (
    tester,
  ) async {
    final character = _character(worldBookIds: const ['book_b']);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [_message('user', '请介绍天剑宗'), _message('assistant', '旧回复')],
      worldBooks: [_book('book_b')],
      worldBookEntries: {
        'book_b': [_worldEntry('book_b')],
      },
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await tester.tap(find.text('重新生成'));
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(
      gateway.messages!.map((message) => message['content']).join('\n'),
      contains('世界书命中内容'),
    );
  });

  testWidgets('an old request cannot detach the newer buffer from stop', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '请求 A');
    await _pumpUntil(tester, () => gateway.callCount == 1);
    gateway.controllers[0].add('A 的片段');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    await _send(tester, '请求 B');
    await _pumpUntil(tester, () => gateway.callCount == 2);
    await gateway.controllers[0].close();
    await tester.pump();
    await tester.pump();

    gateway.controllers[1].add('B 待刷新片段');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => storage.chats['session']?.last.content == 'B 待刷新片段',
    );

    expect(storage.chats['session']!.last.role, 'assistant');
    expect(storage.chats['session']!.last.content, isNot(contains('A 的片段')));
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('an old variant request cannot clear a newer typing state', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [_message('user', '问题'), _message('assistant', '原回复')],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await tester.tap(find.text('重新生成'));
    await _pumpUntil(tester, () => gateway.callCount == 1);
    expect(find.byType(TypingBubble), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    await tester.tap(find.text('重新生成'));
    await _pumpUntil(tester, () => gateway.callCount == 2);
    expect(find.byType(TypingBubble), findsOneWidget);

    await gateway.controllers[0].close();
    await tester.pump();
    await tester.pump();

    expect(find.byType(TypingBubble), findsOneWidget);

    gateway.controllers[1].add('新回复');
    await gateway.controllers[1].close();
    await tester.pumpAndSettle();
    expect(storage.chats['session']!.last.effectiveContent, '新回复');
  });

  testWidgets('swiping memory tabs keeps the add action in sync', (
    tester,
  ) async {
    final character = _character();
    final session = _session(openingMessageInitialized: true);
    final storage = _SessionStorage(character: character, sessions: [session]);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MemoryManagerScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: character,
          session: session,
          selectedEndpointId: 'endpoint',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加长期记忆'), findsWidgets);
    await tester.drag(find.byType(TabBarView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('添加当前对话记忆'), findsWidgets);

    await tester.drag(find.byType(TabBarView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('添加世界书'), findsWidgets);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('引用已有世界书'), findsOneWidget);
    expect(find.text('新建世界书'), findsOneWidget);
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  _SessionStorage storage,
  AppCharacter character, {
  AiGateway? gateway,
  ChatSession? session,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: ChatScreen(
        storage: storage,
        aiService: gateway ?? _RecordingGateway(),
        character: character,
        settings: const AppSettings(),
        session: session ?? storage.sessions.first,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 100 && !condition(); index++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

AppCharacter _character({
  String openingMessage = '',
  List<String> worldBookIds = const [],
}) => AppCharacter.fromJson({
  'id': 'character',
  'name': '角色',
  'openingMessage': openingMessage,
  'defaultEndpointId': 'endpoint',
  'worldBookIds': worldBookIds,
});

ChatSession _session({
  String title = '对话',
  bool openingMessageInitialized = false,
}) {
  final now = DateTime(2026);
  return ChatSession(
    id: 'session',
    characterId: 'character',
    title: title,
    createdAt: now,
    updatedAt: now,
    lastUsedAt: now,
    openingMessageInitialized: openingMessageInitialized,
  );
}

ChatMessage _message(String role, String content) =>
    ChatMessage(role: role, content: content, time: DateTime(2026));

WorldBook _book(String id, {bool enabled = true}) => WorldBook(
  id: id,
  name: id,
  enabled: enabled,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

WorldBookEntry _worldEntry(String worldBookId) => WorldBookEntry(
  id: 'entry',
  worldBookId: worldBookId,
  title: '宗门',
  content: '世界书命中内容',
  keywords: const ['天剑宗'],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ApiConfig _apiConfig() => ApiConfig(
  endpoints: [
    AiEndpointConfig(
      id: 'endpoint',
      name: 'Endpoint',
      apiKey: 'key',
      baseUrl: 'https://example.test/v1',
      model: 'model',
      enabled: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ],
  defaultEndpointId: 'endpoint',
);

final class _SessionStorage extends LocalStorageService {
  _SessionStorage({
    required this.character,
    required List<ChatSession> sessions,
    List<ChatMessage> chat = const [],
    this.worldBooks = const [],
    this.worldBookEntries = const {},
  }) : sessions = [...sessions],
       chats = {
         for (final session in sessions) session.id: [...chat],
       },
       super();

  AppCharacter character;
  final List<ChatSession> sessions;
  final Map<String, List<ChatMessage>> chats;
  final List<WorldBook> worldBooks;
  final Map<String, List<WorldBookEntry>> worldBookEntries;
  final loadedWorldBookEntryIds = <String>[];

  @override
  bool get usesSessionStorage => true;

  @override
  Future<ApiConfig> loadApiConfig() async => _apiConfig();

  @override
  Future<AppSettings> loadSettings() async => const AppSettings();

  @override
  Future<List<AppCharacter>> loadCharacters() async => [character];

  @override
  Future<void> saveCharacter(AppCharacter value) async => character = value;

  @override
  Future<List<ChatSession>> loadChatSessions(String characterId) async =>
      sessions.where((session) => session.characterId == characterId).toList();

  @override
  Future<ChatSession> getOrCreateRecentChatSession(String characterId) async =>
      sessions.first;

  @override
  Future<void> saveChatSession(ChatSession session) async {
    final index = sessions.indexWhere((item) => item.id == session.id);
    index < 0 ? sessions.add(session) : sessions[index] = session;
  }

  @override
  Future<ChatSession> markOpeningMessageInitialized({
    required String sessionId,
    required String characterId,
  }) async {
    final index = sessions.indexWhere(
      (session) =>
          session.id == sessionId && session.characterId == characterId,
    );
    if (index < 0) throw StateError('对话不存在');
    final updated = sessions[index].copyWith(
      openingMessageInitialized: true,
      updatedAt: DateTime.now(),
    );
    sessions[index] = updated;
    return updated;
  }

  @override
  Future<List<ChatMessage>> loadChatBySession(ChatSession session) async => [
    ...chats[session.id] ?? const <ChatMessage>[],
  ];

  @override
  Future<void> saveChatBySession(
    ChatSession session,
    List<ChatMessage> messages,
  ) async {
    chats[session.id] = [...messages];
  }

  @override
  Future<ChatSummary> loadSummaryBySession(ChatSession session) async =>
      ChatSummary.empty(session.characterId, session.id);

  @override
  Future<void> saveSummaryBySession(ChatSummary summary) async {}

  @override
  Future<List<CharacterMemoryEntry>> loadCharacterMemories(
    String characterId,
  ) async => const [];

  @override
  Future<List<WorldBook>> loadWorldBooks() async => [...worldBooks];

  @override
  Future<List<WorldBookEntry>> loadWorldBookEntries(String worldBookId) async {
    loadedWorldBookEntryIds.add(worldBookId);
    return [...worldBookEntries[worldBookId] ?? const <WorldBookEntry>[]];
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

class _RecordingGateway implements AiGateway {
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
  }) async => '回复';

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
    this.messages = messages;
    yield '回复';
  }
}

final class _ControlledGateway extends _RecordingGateway {
  final controllers = <StreamController<String>>[];

  int get callCount => controllers.length;

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
  }) {
    this.messages = messages;
    final controller = StreamController<String>();
    controllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    for (final controller in controllers) {
      if (!controller.isClosed) await controller.close();
    }
  }
}
