import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/services/chat/chat_session_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';
import 'package:whisnya/services/chat/chat_summary_service.dart';
import 'package:whisnya/utils/chat_context_policy.dart';

void main() {
  late Directory root;
  late ChatSessionService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('clear_regression_');
    service = ChatSessionService(root: root);
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'token captured before deletion cannot recreate chat or summary',
    () async {
      final session = await service.createChatSession('c1');
      final token = service.captureToken(session);
      await service.deleteChatSession(session);
      expect(
        await service.saveChatBySessionIfExists(session, [], token: token),
        isFalse,
      );
      await expectLater(
        service.saveSummaryBySession(
          ChatSummary.empty('c1', session.id),
          token: token,
        ),
        throwsStateError,
      );
      expect(
        await File('${root.path}/chats/${session.id}.json').exists(),
        isFalse,
      );
      expect(
        await File('${root.path}/summaries/${session.id}.json').exists(),
        isFalse,
      );
    },
  );
  test(
    'rollback preserves raw chat entries and unknown metadata without dropping damaged rows',
    () async {
      final store = FailingClearStore();
      service = ChatSessionService(root: root, jsonStore: store);
      final session = await service.createChatSession('c1');
      final file = File('${root.path}/chats/${session.id}.json');
      final raw = {
        'sessionId': session.id,
        'characterId': 'c1',
        'custom': 'keep',
        'messages': [
          {'role': 'user', 'content': 'old', 'time': '2026-01-01T00:00:00'},
          'damaged entry',
        ],
      };
      await file.writeAsString(jsonEncode(raw));
      store.fail = 'summaries';
      await expectLater(
        service.clearChatPreservingSummary(session),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(await file.readAsString()), raw);
    },
  );
  test(
    'repeated clears are isolated and concurrent save delete finishes',
    () async {
      final first = await service.createChatSession('c1');
      final second = await service.createChatSession('c1');
      final message = ChatMessage(
        role: 'user',
        content: 'kept',
        time: DateTime(2026),
      );
      await service.saveChatBySession(second, [message]);
      await service.clearChatPreservingSummary(first);
      await service.clearChatPreservingSummary(first);
      expect((await service.loadSummaryBySession(first)).summary, isEmpty);
      expect((await service.loadChatBySession(second)).single.content, 'kept');
      await Future.wait([
        service.saveChatBySessionIfExists(first, [message]),
        service.clearChatPreservingSummary(first),
        service.deleteChatSession(first),
      ]).timeout(const Duration(seconds: 5));
      expect(
        await File('${root.path}/chats/${first.id}.json').exists(),
        isFalse,
      );
    },
  );
  test(
    'clear preserves summary text and opening flag but resets coverage',
    () async {
      var session = await service.createChatSession('c1');
      session = await service.markOpeningMessageInitialized(
        sessionId: session.id,
        characterId: 'c1',
      );
      await service.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'old', time: DateTime(2026)),
      ]);
      await service.saveSummaryBySession(
        ChatSummary(
          characterId: 'c1',
          sessionId: session.id,
          summary: 'S',
          updatedAt: DateTime(2026),
          summarizedMessageCount: 100,
        ),
      );
      final result = await service.clearChatPreservingSummary(session);
      expect(result.summary, 'S');
      expect(result.summarizedMessageCount, 0);
      expect(await service.loadChatBySession(session), isEmpty);
      final saved = (await service.loadChatSessions('c1')).single;
      expect(saved.openingMessageInitialized, isTrue);
      expect(saved.messageCount, 0);
    },
  );
  test('ordinary late save cannot recreate deleted chat', () async {
    final session = await service.createChatSession('c1');
    await service.deleteChatSession(session);
    await expectLater(
      service.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'late', time: DateTime(2026)),
      ]),
      throwsStateError,
    );
    expect(
      await File('${root.path}/chats/${session.id}.json').exists(),
      isFalse,
    );
  });
  test('new sessions persist a known zero count', () async {
    final session = await service.createChatSession('c1');
    expect(session.toJson()['messageCount'], 0);
  });
  for (final target in ['summaries', 'chats', 'chat_sessions.json']) {
    test('failed clear at $target restores all original data', () async {
      final store = FailingClearStore();
      service = ChatSessionService(root: root, jsonStore: store);
      final session = await service.createChatSession('c1');
      await service.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'before', time: DateTime(2026)),
      ]);
      await service.saveSummaryBySession(
        ChatSummary(
          characterId: 'c1',
          sessionId: session.id,
          summary: 'S',
          updatedAt: DateTime(2026),
          summarizedMessageCount: 100,
        ),
      );
      store.fail = target;
      await expectLater(
        service.clearChatPreservingSummary(session),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (await service.loadChatBySession(session)).single.content,
        'before',
      );
      expect(
        (await service.loadSummaryBySession(session)).summarizedMessageCount,
        100,
      );
      expect((await service.loadChatSessions('c1')).single.messageCount, 1);
    });
  }
  test('token captured before clear cannot restore old messages', () async {
    final session = await service.createChatSession('c1');
    final token = service.captureToken(session);
    await service.clearChatPreservingSummary(session);
    expect(
      await service.saveChatBySessionIfExists(session, [
        ChatMessage(role: 'user', content: 'late', time: DateTime(2026)),
      ], token: token),
      isFalse,
    );
    expect(await service.loadChatBySession(session), isEmpty);
  });
  test(
    'startup retries interrupted rollback and restores consistent snapshot',
    () async {
      final store = FailingClearStore();
      service = ChatSessionService(root: root, jsonStore: store);
      final session = await service.createChatSession('c1');
      await service.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'durable', time: DateTime(2026)),
      ]);
      await service.saveSummaryBySession(
        ChatSummary(
          characterId: 'c1',
          sessionId: session.id,
          summary: 'S',
          updatedAt: DateTime(2026),
          summarizedMessageCount: 100,
        ),
      );
      store.fail = 'chats';
      store.persistent = true;
      await expectLater(
        service.clearChatPreservingSummary(session),
        throwsA(isA<FileSystemException>()),
      );
      final restarted = ChatSessionService(root: root);
      final restored = (await restarted.loadChatSessions('c1')).single;
      expect(
        (await restarted.loadChatBySession(restored)).single.content,
        'durable',
      );
      expect(
        (await restarted.loadSummaryBySession(restored)).summarizedMessageCount,
        100,
      );
      expect(restored.messageCount, 1);
    },
  );
  test('dataset replacement invalidates previously captured saves', () async {
    final store = JsonFileStore();
    service = ChatSessionService(root: root, jsonStore: store);
    final session = await service.createChatSession('c1');
    final token = service.captureToken(session);
    await store.maintain(() async {}, advanceEpoch: true);
    expect(
      await service.saveChatBySessionIfExists(session, [], token: token),
      isFalse,
    );
  });
  test('preserved summary never skips the first thirteen new messages', () {
    final next = summaryAfterChatClear(
      ChatSummary(
        characterId: 'c1',
        sessionId: 's1',
        summary: 'S',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 100,
      ),
      DateTime(2026),
    );
    expect(
      chatContextStartIndex(
        summarizedMessageCount: next.summarizedMessageCount,
        messageCount: 25,
      ),
      0,
    );
  });
  test('late summary cannot recreate deleted summary', () async {
    final session = await service.createChatSession('c1');
    await service.deleteChatSession(session);
    await expectLater(
      service.saveSummaryBySession(ChatSummary.empty('c1', session.id)),
      throwsStateError,
    );
    expect(
      await File('${root.path}/summaries/${session.id}.json').exists(),
      isFalse,
    );
  });
}

class FailingClearStore extends JsonFileStore {
  String? fail;
  bool persistent = false;
  @override
  Future<void> writeNow(File file, dynamic data, {bool compact = false}) {
    if (fail != null && file.path.contains(fail!)) {
      if (!persistent) fail = null;
      throw FileSystemException('injected failure', file.path);
    }
    return super.writeNow(file, data, compact: compact);
  }
}
