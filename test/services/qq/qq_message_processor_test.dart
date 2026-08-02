import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/qq_contact_binding.dart';
import 'package:whisnya/models/qq_diagnostic_event.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/models/unified_qq_message.dart';
import 'package:whisnya/models/unified_qq_reply.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/qq/background_character_chat_service.dart';
import 'package:whisnya/services/qq/qq_message_debouncer.dart';
import 'package:whisnya/services/qq/qq_message_processor.dart';

void main() {
  late _FakeStorage storage;
  late _FakeReplyService replies;
  late QqMessageProcessor processor;

  setUp(() {
    storage = _FakeStorage();
    replies = _FakeReplyService();
    processor = QqMessageProcessor(
      storage: storage,
      chatService: replies,
      debouncer: QqMessageDebouncer(
        mergeWindow: const Duration(milliseconds: 20),
      ),
    );
  });

  tearDown(() => processor.dispose());

  test('silently ignores unknown contacts and duplicate messages', () async {
    final unknown = await processor.handle(
      _message(userId: 'unknown'),
      settings: _settings(),
    );
    expect(unknown.status, QqProcessStatus.ignored);
    expect(unknown.message, isEmpty);

    final first = processor.handle(_message(), settings: _settings());
    final duplicate = await processor.handle(_message(), settings: _settings());
    expect(duplicate.reason, 'duplicate');
    await first;
    expect(replies.calls, 1);
  });

  test(
    'merges messages and only the latest invocation receives the reply',
    () async {
      final first = processor.handle(
        _message(id: 'm1', text: 'first'),
        settings: _settings(),
      );
      final second = processor.handle(
        _message(id: 'm2', text: 'second'),
        settings: _settings(),
      );
      expect((await first).reason, 'merged');
      final result = await second;
      expect(result.status, QqProcessStatus.reply);
      expect(replies.lastMessage!.text, 'first\nsecond');
    },
  );

  test(
    'quiet hours ignore ordinary messages but commands still work',
    () async {
      final quiet = await processor.handle(
        _message(timestamp: DateTime(2026, 8, 3, 23, 30)),
        settings: _settings().copyWith(
          quietHoursEnabled: true,
          quietHoursStartMinutes: 23 * 60,
          quietHoursEndMinutes: 7 * 60,
        ),
      );
      expect(quiet.reason, 'quietHours');

      final help = await processor.handle(
        _message(
          id: 'help',
          text: '/帮助',
          timestamp: DateTime(2026, 8, 3, 23, 30),
        ),
        settings: _settings(),
      );
      expect(help.text, contains('/新对话'));
    },
  );

  test(
    '/继续 is handled before enabled check and /暂停 disables binding',
    () async {
      storage.bindings[0] = storage.bindings.single.copyWith(enabled: false);
      final resumed = await processor.handle(
        _message(id: 'resume', text: '/继续'),
        settings: _settings(),
      );
      expect(resumed.status, QqProcessStatus.reply);
      expect(storage.bindings.single.enabled, isTrue);

      final paused = await processor.handle(
        _message(id: 'pause', text: '/暂停'),
        settings: _settings(),
      );
      expect(paused.status, QqProcessStatus.reply);
      expect(storage.bindings.single.enabled, isFalse);
    },
  );

  test('/新对话 keeps the old session and updates only this binding', () async {
    final oldSession = storage.bindings.single.sessionId;
    final result = await processor.handle(
      _message(id: 'new', text: '/新对话'),
      settings: _settings(),
    );
    expect(result.status, QqProcessStatus.reply);
    expect(storage.bindings.single.sessionId, isNot(oldSession));
    expect(
      storage.sessions.map((item) => item.id),
      containsAll([oldSession, storage.bindings.single.sessionId]),
    );
    expect(storage.sessions.last.openingMessageInitialized, isTrue);
  });

  test('does not deliver a reply when binding is disabled during AI', () async {
    replies.beforeReturn = () async {
      storage.bindings[0] = storage.bindings.single.copyWith(enabled: false);
    };
    final result = await processor.handle(
      _message(id: 'disabled-during-ai'),
      settings: _settings(),
    );
    expect(result.status, QqProcessStatus.ignored);
    expect(result.reason, 'bindingChangedAfterReply');
  });
}

QqIntegrationSettings _settings() => const QqIntegrationSettings(
  enabled: true,
  mode: QqIntegrationMode.oneBot,
  mergeWindowMilliseconds: 20,
);

UnifiedQqMessage _message({
  String id = 'm1',
  String userId = '10001',
  String text = 'hello',
  DateTime? timestamp,
}) => UnifiedQqMessage(
  source: QqIntegrationMode.oneBot,
  messageId: id,
  externalUserId: userId,
  senderDisplayName: 'Alice',
  text: text,
  timestamp: timestamp ?? DateTime(2026, 8, 3, 12),
  rawConversationTitle: 'Alice',
);

final class _FakeReplyService implements QqCharacterReplyService {
  var calls = 0;
  UnifiedQqMessage? lastMessage;
  Future<void> Function()? beforeReturn;

  @override
  Future<UnifiedQqReply> reply({
    required QqContactBinding binding,
    required UnifiedQqMessage message,
    required QqIntegrationSettings settings,
  }) async {
    calls++;
    lastMessage = message;
    await beforeReturn?.call();
    return UnifiedQqReply(
      externalUserId: binding.externalUserId,
      bindingId: binding.id,
      sessionId: binding.sessionId,
      text: 'reply: ${message.text}',
      createdAt: DateTime.now(),
    );
  }
}

final class _FakeStorage extends LocalStorageService {
  _FakeStorage() : super(appDataDirectory: Directory.systemTemp);

  final now = DateTime(2026, 8, 3);
  late final bindings = <QqContactBinding>[
    QqContactBinding(
      id: 'binding',
      mode: QqIntegrationMode.oneBot,
      externalUserId: '10001',
      displayName: 'Alice',
      characterId: 'character',
      sessionId: 'old-session',
      createdAt: now,
      updatedAt: now,
    ),
  ];
  late final characters = <AppCharacter>[_character(now)];
  late final sessions = <ChatSession>[
    ChatSession(
      id: 'old-session',
      characterId: 'character',
      title: 'Old',
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
      openingMessageInitialized: true,
    ),
  ];

  @override
  Future<List<QqContactBinding>> loadQqContactBindings() async => [...bindings];

  @override
  Future<void> saveQqContactBinding(QqContactBinding value) async {
    final index = bindings.indexWhere((item) => item.id == value.id);
    if (index < 0) {
      bindings.add(value);
    } else {
      bindings[index] = value;
    }
  }

  @override
  Future<List<AppCharacter>> loadCharacters() async => [...characters];

  @override
  Future<ChatSession> createChatSession(
    String characterId, {
    String? title,
  }) async {
    final session = ChatSession(
      id: 'new-session-${sessions.length}',
      characterId: characterId,
      title: title ?? '',
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
    sessions.add(session);
    return session;
  }

  @override
  Future<ChatSession> markOpeningMessageInitialized({
    required String sessionId,
    required String characterId,
  }) async {
    final index = sessions.indexWhere((item) => item.id == sessionId);
    sessions[index] = sessions[index].copyWith(openingMessageInitialized: true);
    return sessions[index];
  }

  @override
  Future<void> appendQqDiagnosticEvent(QqDiagnosticEvent event) async {}
}

AppCharacter _character(DateTime now) => AppCharacter(
  id: 'character',
  name: 'Role',
  avatar: '',
  backgroundImage: '',
  backgroundImageOpacity: 1,
  backgroundBlur: 0,
  inputOpacity: 1,
  description: '',
  personality: '',
  background: '',
  speakingStyle: '',
  openingMessage: '',
  extraPrompt: '',
  createdAt: now,
  updatedAt: now,
  lastUsedAt: now,
);
