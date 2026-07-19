import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/screens/theater/theater_reply_settings.dart';
import 'package:whisnya/screens/theater/theater_screens.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';

void main() {
  testWidgets('theater bubble settings follow input opacity', (tester) async {
    final storage = _MemoryStorage(session: _session, messages: _messages);
    await tester.pumpWidget(
      MaterialApp(
        home: TheaterChatScreen(
          storage: storage,
          aiService: _FakeGateway('回复'),
          settings: const AppSettings(),
          session: _session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final expansion = find.byKey(
      const ValueKey('theater-chat-bubble-theme-expansion'),
    );
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
        ValueKey('theater-chat-input-opacity-setting'),
        ValueKey('theater-chat-bubble-theme-expansion'),
      ]),
    );
  });

  testWidgets('reply choices follow the available participant count', (
    tester,
  ) async {
    Future<void> pump(int participantCount) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            body: TheaterReplySettings(
              participantCount: participantCount,
              mainReplyCount: 1,
              extraReplyMode: 0,
              onMainReplyCountChanged: (_) {},
              onExtraReplyModeChanged: (_) {},
            ),
          ),
        ),
      );
    }

    await pump(5);
    for (final label in const ['1 人', '2 人', '3 人', '4 人', '全部角色']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in const ['不追加', '0-1个', '0-2个', '0-3个', '0-4个']) {
      expect(find.text(label), findsOneWidget);
    }

    await pump(4);
    expect(find.text('4 人'), findsNothing);
    expect(find.text('0-4个'), findsNothing);
  });

  testWidgets('bottom continuation is labeled as continuing one round', (
    tester,
  ) async {
    final storage = _MemoryStorage(session: _session, messages: _messages);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: TheaterChatScreen(
          storage: storage,
          aiService: _FakeGateway('回复'),
          settings: const AppSettings(streamResponses: false),
          session: _session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('继续一轮').evaluate().length +
          find.byTooltip('Continue one round').evaluate().length,
      1,
    );
    expect(find.byTooltip('再生成一轮'), findsNothing);
    expect(find.byTooltip('Generate another round'), findsNothing);
  });

  testWidgets('background image opacity fades over white', (tester) async {
    final session = _session.copyWith(
      backgroundImage: 'missing-background.png',
      backgroundImageOpacity: 0.25,
    );
    final storage = _MemoryStorage(session: session, messages: _messages);

    await tester.pumpWidget(
      MaterialApp(
        home: TheaterChatScreen(
          storage: storage,
          aiService: _FakeGateway('回复'),
          settings: const AppSettings(),
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final background = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('theater-chat-background-base')),
    );
    expect(background.color, Colors.white);
  });

  testWidgets('turn-based continuation invokes only the next participant', (
    tester,
  ) async {
    final storage = _MemoryStorage(session: _session, messages: _messages);
    final service = _FakeGateway('接着说');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: TheaterChatScreen(
          storage: storage,
          aiService: service,
          settings: const AppSettings(streamResponses: false),
          session: _session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(service.models, ['model-b']);
    expect(storage.messages.last.speakerId, 'b');
    expect(storage.savedSessions.last.nextSpeakerIndex, 0);
  });

  testWidgets('non-turn-based continuation uses only main reply count', (
    tester,
  ) async {
    final session = _session.copyWith(
      multiApiReplyMode: TheaterMultiApiReplyMode.parallel,
      mainReplyCount: 1,
      extraReplyMode: 2,
    );
    final storage = _MemoryStorage(session: session, messages: _messages);
    final service = _FakeGateway('接着说');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: TheaterChatScreen(
          storage: storage,
          aiService: service,
          settings: const AppSettings(streamResponses: false),
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(service.models, hasLength(1));
    expect(
      storage.messages.where((message) => message.round == 2),
      hasLength(1),
    );
  });

  testWidgets('reply once only invokes the selected participant', (
    tester,
  ) async {
    final storage = _MemoryStorage(session: _session, messages: _messages);
    final service = _FakeGateway('乙单独回复');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: TheaterChatScreen(
          storage: storage,
          aiService: service,
          settings: const AppSettings(streamResponses: false),
          session: _session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('theater-reply-once-role-b-message')),
    );
    await tester.pumpAndSettle();

    expect(service.models, ['model-b']);
    expect(storage.messages, hasLength(_messages.length + 1));
    expect(storage.messages.last.speakerId, 'b');
    expect(storage.messages.last.content, '乙单独回复');
    expect(
      storage.savedSessions.every(
        (session) => session.nextSpeakerIndex == _session.nextSpeakerIndex,
      ),
      isTrue,
    );
  });

  testWidgets('reply once rejects a muted participant', (tester) async {
    final mutedSession = _session.copyWith(
      participants: [_first, _second.copyWith(isMuted: true)],
    );
    final storage = _MemoryStorage(session: mutedSession, messages: _messages);
    final service = _FakeGateway('不应生成');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: TheaterChatScreen(
          storage: storage,
          aiService: service,
          settings: const AppSettings(streamResponses: false),
          session: mutedSession,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('theater-reply-once-role-b-message')),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(service.models, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining(RegExp('该角色已被禁言|This character is muted')),
      findsOneWidget,
    );
    expect(storage.messages, hasLength(_messages.length));
  });

  testWidgets('parallel partial results are saved when one role fails', (
    tester,
  ) async {
    final session = _session.copyWith(
      multiApiReplyMode: TheaterMultiApiReplyMode.parallel,
      mainReplyCount: 2,
    );
    final storage = _MemoryStorage(session: session, messages: _messages);
    final service = _FakeGateway('甲完成', failures: const {'model-b'});

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: TheaterChatScreen(
          storage: storage,
          aiService: service,
          settings: const AppSettings(streamResponses: false),
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(
      storage.messages.any(
        (message) =>
            message.round == 2 && message.speakerId == 'a' && !message.isError,
      ),
      isTrue,
    );
    expect(
      storage.messages.any(
        (message) =>
            message.round == 2 && message.speakerId == 'b' && message.isError,
      ),
      isTrue,
    );
  });
}

final class _FakeGateway implements AiGateway {
  _FakeGateway(this.response, {this.failures = const {}});

  final String response;
  final Set<String> failures;
  final models = <String>[];

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
    models.add(model);
    if (failures.contains(model)) {
      return Stream.error(AiException('$model 请求失败'));
    }
    return Stream.value(response);
  }

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) => throw UnimplementedError();
}

const _first = TheaterParticipant(
  id: 'a',
  source: TheaterRoleSource.appCharacter,
  name: '甲',
  avatar: '',
  description: '',
  personality: '',
  background: '',
  speakingStyle: '',
  endpointId: 'a',
);

const _second = TheaterParticipant(
  id: 'b',
  source: TheaterRoleSource.appCharacter,
  name: '乙',
  avatar: '',
  description: '',
  personality: '',
  background: '',
  speakingStyle: '',
  endpointId: 'b',
);

final _session = TheaterSession(
  id: 'session',
  title: '群聊',
  apiMode: TheaterApiMode.multiApi,
  multiApiReplyMode: TheaterMultiApiReplyMode.turnBased,
  nextSpeakerIndex: 1,
  participants: const [_first, _second],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _messages = [
  TheaterMessage(
    id: 'user-message',
    sessionId: 'session',
    round: 1,
    speakerType: TheaterSpeakerType.user,
    speakerId: '',
    speakerName: '我',
    content: '你好',
    time: DateTime(2026),
  ),
  TheaterMessage(
    id: 'role-b-message',
    sessionId: 'session',
    round: 1,
    speakerType: TheaterSpeakerType.role,
    speakerId: 'b',
    speakerName: '乙',
    content: '你好',
    time: DateTime(2026),
  ),
];

final class _MemoryStorage extends LocalStorageService {
  _MemoryStorage({
    required this.session,
    required List<TheaterMessage> messages,
  }) : messages = [...messages];

  final TheaterSession session;
  List<TheaterMessage> messages;
  final savedSessions = <TheaterSession>[];

  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig(
    endpoints: [
      for (final id in const ['a', 'b'])
        AiEndpointConfig(
          id: id,
          name: id,
          apiKey: 'key',
          baseUrl: 'https://example.com/v1',
          model: 'model-$id',
          enabled: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
    ],
  );

  @override
  Future<List<TheaterMessage>> loadTheaterMessages(String sessionId) async => [
    ...messages,
  ];

  @override
  Future<List<NovelBook>> loadNovels() async => const [];

  @override
  Future<void> saveTheaterMessages(
    String sessionId,
    List<TheaterMessage> messages,
  ) async {
    this.messages = [...messages];
  }

  @override
  Future<void> saveTheaterSession(TheaterSession session) async {
    savedSessions.add(session);
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
