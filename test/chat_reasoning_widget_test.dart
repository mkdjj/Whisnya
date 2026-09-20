import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/screens/chat/chat_screen.dart';
import 'package:whisnya/screens/chat/chat_session_list_screen.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/session_operation_coordinator.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/message_content.dart';

void main() {
  testWidgets('route back retains unsaved reply and succeeds after retry', (
    tester,
  ) async {
    final storage = _Storage();
    final gateway = _Gateway();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: const Scaffold(body: Text('home route')),
      ),
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            storage: storage,
            aiService: gateway,
            character: storage.character,
            session: storage.session,
            settings: const AppSettings(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _send(tester, gateway);
    storage.safeSaveError = StateError('disk full');
    gateway.stream.add(
      const AiResponseDelta(contentDelta: 'keep unsaved reply'),
    );
    unawaited(gateway.stream.close());
    await tester.pumpAndSettle();
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('keep unsaved reply'), findsOneWidget);
    storage.safeSaveError = null;
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('home route'), findsOneWidget);
    expect(storage.chat.last.content, 'keep unsaved reply');
  });
  testWidgets(
    'delete confirmation from old dataset cannot delete imported message',
    (tester) async {
      final storage = _Storage()
        ..chat = [
          ChatMessage(
            role: 'assistant',
            content: 'old dataset',
            time: DateTime(2026),
          ),
        ];
      final gateway = _Gateway();
      await _pump(tester, storage, gateway);
      await tester.tap(find.byTooltip('删除消息'));
      await tester.pumpAndSettle();
      storage.chat = [
        ChatMessage(
          role: 'assistant',
          content: 'new dataset',
          time: DateTime(2026),
        ),
      ];
      storage.jsonStore.datasetEpochNotifier.value++;
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(storage.chat.single.content, 'new dataset');
      unawaited(gateway.stream.close());
    },
  );
  testWidgets(
    'late cancellation save failure does not mark imported chat unsaved',
    (tester) async {
      final storage = _Storage();
      final gateway = _Gateway();
      await _pump(tester, storage, gateway);
      await _send(tester, gateway);
      gateway.stream.add(const AiResponseDelta(contentDelta: 'old partial'));
      await tester.pump(const Duration(milliseconds: 50));
      final gate = Completer<void>();
      storage.safeSaveGate = gate;
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.stop))
          .onPressed!();
      await tester.pump();
      storage.chat = [
        ChatMessage(
          role: 'assistant',
          content: 'new dataset',
          time: DateTime(2026),
        ),
      ];
      storage.jsonStore.datasetEpochNotifier.value++;
      await tester.pumpAndSettle();
      gate.completeError(StateError('old cancellation write rejected'));
      await tester.pumpAndSettle();
      expect(find.text('new dataset'), findsOneWidget);
      expect(find.text('重试保存'), findsNothing);
      unawaited(gateway.stream.close());
    },
  );
  testWidgets(
    'endpoint load from old epoch cannot start a new-dataset request',
    (tester) async {
      final storage = _Storage();
      final gateway = _Gateway();
      await _pump(tester, storage, gateway);
      final gate = Completer<void>();
      storage.apiGate = gate;
      await tester.enterText(find.byType(TextField).last, 'old question');
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed!();
      await tester.pump();
      storage.chat = [
        ChatMessage(
          role: 'assistant',
          content: 'new dataset',
          time: DateTime(2026),
        ),
      ];
      storage.jsonStore.datasetEpochNotifier.value++;
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(gateway.started, isFalse);
      expect(storage.chat.single.content, 'new dataset');
      unawaited(gateway.stream.close());
    },
  );

  testWidgets('late initial save failure never restores pre-import history', (
    tester,
  ) async {
    final storage = _Storage()
      ..chat = [
        ChatMessage(
          role: 'assistant',
          content: 'old dataset',
          time: DateTime(2026),
        ),
      ];
    final gateway = _Gateway();
    await _pump(tester, storage, gateway);
    final gate = Completer<void>();
    storage.initialSaveGate = gate;
    await tester.enterText(find.byType(TextField).last, 'old question');
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
        .onPressed!();
    await tester.pump();
    storage.chat = [
      ChatMessage(
        role: 'assistant',
        content: 'new dataset',
        time: DateTime(2026),
      ),
    ];
    storage.jsonStore.datasetEpochNotifier.value++;
    await tester.pumpAndSettle();
    gate.completeError(StateError('old write cancelled'));
    await tester.pumpAndSettle();
    expect(find.text('old dataset'), findsNothing);
    expect(find.text('new dataset'), findsOneWidget);
    expect(gateway.started, isFalse);
    unawaited(gateway.stream.close());
  });

  testWidgets('unsaved reply blocks session navigation until retry succeeds', (
    tester,
  ) async {
    final storage = _Storage();
    final gateway = _Gateway();
    await _pump(tester, storage, gateway);
    await _send(tester, gateway);
    storage.safeSaveError = StateError('disk full');
    gateway.stream.add(const AiResponseDelta(contentDelta: 'unsaved reply'));
    unawaited(gateway.stream.close());
    await tester.pumpAndSettle();
    await tester.tap(find.text('chat').first);
    await tester.pumpAndSettle();
    expect(find.byType(ChatSessionListScreen), findsOneWidget);
    await tester.tap(find.text('other chat'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatSessionListScreen), findsNothing);
    expect(find.text('重试保存'), findsOneWidget);
    storage.safeSaveError = null;
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(find.text('重试保存'), findsNothing);
    expect(storage.chat.last.content, 'unsaved reply');
  });

  testWidgets('late token capture cannot replace a newer generation token', (
    tester,
  ) async {
    final storage = _Storage();
    final gateway = _Gateway();
    await _pump(tester, storage, gateway);
    final oldToken = Completer<SessionOperationToken>();
    storage.tokenGate = oldToken;
    await tester.enterText(find.byType(TextField).last, 'A');
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
        .onPressed!();
    for (var i = 0; i < 20 && storage.tokenCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.stop))
        .onPressed!();
    await tester.pumpAndSettle();
    await _send(tester, gateway);
    gateway.stream.add(const AiResponseDelta(contentDelta: 'B partial'));
    await tester.pump(const Duration(milliseconds: 50));
    oldToken.complete(const SessionOperationToken('s', 0, 999));
    await tester.pump(const Duration(milliseconds: 50));
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.stop))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(storage.savedTokens.last?.revision, 0);
    expect(storage.chat.last.content, 'B partial');
    unawaited(gateway.stream.close());
  });
  for (final count in [1000, 10000]) {
    testWidgets('$count message history does not rebuild during draft chunks', (
      tester,
    ) async {
      final storage = _Storage()
        ..chat = List.generate(
          count,
          (i) => ChatMessage(
            role: i.isEven ? 'user' : 'assistant',
            content: 'history-$i',
            time: DateTime(2026),
          ),
        );
      final gateway = _Gateway();
      await _pump(tester, storage, gateway);
      await _send(tester, gateway);
      await tester.pump(const Duration(milliseconds: 50));
      var historicalBuilds = 0;
      var draftBuilds = 0;
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is MessageContent && widget.text.startsWith('history-'),
        ),
        findsWidgets,
      );
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        final widget = element.widget;
        if (widget is MessageContent && widget.text.startsWith('history-')) {
          historicalBuilds++;
        }
        if (widget is MessageContent && widget.text.startsWith('chunk')) {
          draftBuilds++;
        }
      };
      try {
        for (var i = 0; i < 100; i++) {
          gateway.stream.add(const AiResponseDelta(contentDelta: 'chunk'));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          historicalBuilds,
          0,
          reason: '$count stored messages, 100 streamed updates',
        );
        expect(
          draftBuilds,
          greaterThan(0),
          reason: 'probe must observe real draft rebuilds',
        );
        debugPrint(
          'history=$count chunks=100 historical_builds=$historicalBuilds draft_builds=$draftBuilds',
        );
      } finally {
        debugOnRebuildDirtyWidget = previous;
        unawaited(gateway.stream.close());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets(
    'failed structured candidate preserves original choice and inner voice',
    (tester) async {
      final original = ChatMessage(
        role: 'assistant',
        content: '原候选',
        innerVoice: '原心声',
        reasoningContent: '原思考',
        time: DateTime(2026),
        variants: [
          ChatReplyVariant(
            content: '原候选',
            innerVoice: '原心声',
            reasoningContent: '原思考',
            time: DateTime(2026),
          ),
        ],
      );
      final storage = _Storage()
        ..chat = [
          ChatMessage(role: 'user', content: '问题', time: DateTime(2026)),
          original,
        ];
      final gateway = _Gateway();
      await _pump(tester, storage, gateway);
      await tester.tap(find.text('重新生成'));
      for (var i = 0; i < 100 && !gateway.started; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(gateway.started, isTrue);
      gateway.stream.add(
        const AiResponseDelta(contentDelta: '未完成候选', reasoningDelta: '新思考'),
      );
      gateway.stream.addError(StateError('candidate interrupted'));
      unawaited(gateway.stream.close());
      await tester.pumpAndSettle();
      expect(storage.chat.last.effectiveContent, '原候选');
      expect(storage.chat.last.effectiveInnerVoice, '原心声');
      expect(storage.chat.last.effectiveReasoningContent, '原思考');
      expect(storage.chat.last.variantCount, 1);
      expect(find.text('未完成候选'), findsNothing);
    },
  );
  testWidgets(
    'structured reply saves reasoning separately and toggle hides existing reasoning',
    (tester) async {
      final storage = _Storage();
      final gateway = _Gateway();
      await _pump(tester, storage, gateway, visible: true);
      await _send(tester, gateway);
      gateway.stream.add(
        const AiResponseDelta(contentDelta: '正式回复', reasoningDelta: '接口独立思考'),
      );
      unawaited(gateway.stream.close());
      await tester.pumpAndSettle();
      expect(storage.chat.last.content, '正式回复');
      expect(storage.chat.last.reasoningContent, '接口独立思考');
      expect(storage.chat.last.innerVoice, '');
      expect(find.text('正式回复'), findsOneWidget);
      expect(find.text('接口思考'), findsOneWidget);
      await tester.tap(find.text('接口思考'));
      await tester.pumpAndSettle();
      expect(find.text('接口独立思考'), findsOneWidget);
      await _pump(tester, storage, gateway, visible: false);
      expect(find.text('接口思考'), findsNothing);
      expect(find.text('接口独立思考'), findsNothing);
      expect(storage.chat.last.reasoningContent, '接口独立思考');
    },
  );

  testWidgets('reasoning-only completion never saves an assistant reply', (
    tester,
  ) async {
    final storage = _Storage();
    final gateway = _Gateway();
    await _pump(tester, storage, gateway);
    await _send(tester, gateway);
    gateway.stream.add(const AiResponseDelta(reasoningDelta: '仅有思考'));
    unawaited(gateway.stream.close());
    await tester.pumpAndSettle();
    expect(storage.chat, hasLength(1));
    expect(storage.chat.single.isUser, isTrue);
    expect(find.text('仅有思考'), findsNothing);
  });

  testWidgets(
    'structured network failure retains unflushed formal and reasoning buffers',
    (tester) async {
      final storage = _Storage();
      final gateway = _Gateway();
      await _pump(tester, storage, gateway);
      await _send(tester, gateway);
      gateway.stream.add(
        const AiResponseDelta(contentDelta: '第一段', reasoningDelta: '说明'),
      );
      gateway.stream.add(const AiResponseDelta(contentDelta: '第二段'));
      gateway.stream.addError(StateError('network'));
      unawaited(gateway.stream.close());
      for (var i = 0; i < 100 && storage.chat.length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      expect(
        storage.chat.last.content,
        '第一段第二段',
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((e) => e.data)
            .join('|'),
      );
      expect(storage.chat.last.reasoningContent, '说明');
      expect(storage.chat.last.replyState, 'interrupted');
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Storage storage,
  _Gateway gateway, {
  bool visible = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: ChatScreen(
        storage: storage,
        aiService: gateway,
        character: storage.character,
        session: storage.session,
        settings: AppSettings(showReasoningContent: visible),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, _Gateway gateway) async {
  await tester.enterText(find.byType(TextField).last, '问题');
  tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
      .onPressed!();
  for (var i = 0; i < 100 && !gateway.started; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(gateway.started, isTrue);
}

class _Gateway implements AiGateway, StructuredAiGateway {
  _Gateway() {
    addTearDown(() async {
      unawaited(stream.close());
    });
  }
  final stream = StreamController<AiResponseDelta>.broadcast();
  bool started = false;
  @override
  Stream<AiResponseDelta> streamResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) {
    started = true;
    return stream.stream;
  }

  @override
  Future<AiResponse> sendResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) => throw StateError('stream expected');
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('structured API expected: ${invocation.memberName}');
}

class _Storage extends LocalStorageService {
  Completer<void>? apiGate;
  Completer<void>? initialSaveGate;
  Completer<void>? safeSaveGate;
  Completer<SessionOperationToken>? tokenGate;
  Object? safeSaveError;
  int tokenCalls = 0;
  final savedTokens = <SessionOperationToken?>[];
  final character = AppCharacter.fromJson({
    'id': 'c',
    'name': '角色',
    'defaultEndpointId': 'e',
    'useFullChatContext': true,
  });
  final session = ChatSession(
    id: 's',
    characterId: 'c',
    title: 'chat',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    lastUsedAt: DateTime(2026),
    openingMessageInitialized: true,
  );
  List<ChatMessage> chat = [];
  @override
  bool get usesSessionStorage => true;
  @override
  Future<AppSettings> loadSettings() async => const AppSettings();
  @override
  Future<List<AppCharacter>> loadCharacters() async => [character];
  @override
  Future<void> saveCharacter(AppCharacter value) async {}
  @override
  Future<List<ChatSession>> loadChatSessions(String characterId) async => [
    session,
    session.copyWith(id: 'other', title: 'other chat'),
  ];
  @override
  Future<void> backfillMessageCounts(
    List<ChatSession> sessions, {
    void Function(ChatSession)? onUpdated,
    void Function(String, Object)? onError,
  }) async {}
  @override
  Future<void> saveChatSession(ChatSession value) async {}
  @override
  Future<List<ChatMessage>> loadChatBySession(ChatSession value) async => [
    ...chat,
  ];
  @override
  Future<void> saveChatBySession(
    ChatSession session,
    List<ChatMessage> messages,
  ) async {
    final gate = initialSaveGate;
    initialSaveGate = null;
    if (gate != null) await gate.future;
    chat = [...messages];
  }

  @override
  Future<bool> saveChatBySessionIfExists(
    ChatSession session,
    List<ChatMessage> messages, {
    SessionOperationToken? token,
  }) async {
    final gate = safeSaveGate;
    safeSaveGate = null;
    if (gate != null) await gate.future;
    if (safeSaveError != null) throw safeSaveError!;
    savedTokens.add(token);
    chat = [...messages];
    return true;
  }

  @override
  Future<SessionOperationToken> captureSessionToken(ChatSession session) async {
    tokenCalls++;
    final gate = tokenGate;
    tokenGate = null;
    if (gate != null) return gate.future;
    return SessionOperationToken(session.id, datasetEpoch, 0);
  }

  @override
  Future<ChatSummary> loadSummaryBySession(ChatSession value) async =>
      ChatSummary.empty('c', 's');
  @override
  Future<List<CharacterMemoryEntry>> loadCharacterMemories(
    String characterId,
  ) async => [];
  @override
  Future<List<WorldBook>> loadWorldBooks() async => [];
  @override
  Future<ApiConfig> loadApiConfig() async {
    final gate = apiGate;
    apiGate = null;
    if (gate != null) await gate.future;
    return ApiConfig(
      defaultEndpointId: 'e',
      endpoints: [
        AiEndpointConfig(
          id: 'e',
          name: 'endpoint',
          apiKey: 'key',
          baseUrl: 'https://example.test',
          model: 'm',
          enabled: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );
  }
}
