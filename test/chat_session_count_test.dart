import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/services/chat/chat_session_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';

void main() {
  late Directory root;
  late ChatSessionService service;
  late CountingStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('counts_');
    store = CountingStore();
    service = ChatSessionService(root: root, jsonStore: store);
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'rename queued during backfill preserves both count and title',
    () async {
      final session = await service.createChatSession('c1');
      await service.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'one', time: DateTime(2026)),
      ]);
      await File('${root.path}/chat_sessions.json').writeAsString(
        jsonEncode([
          {...session.toJson(), 'messageCount': null},
        ]),
      );
      store.readEntered = Completer<void>();
      store.readRelease = Completer<void>();
      final backfill = service.backfillMessageCounts(
        await service.loadChatSessions('c1'),
      );
      await store.readEntered!.future.timeout(const Duration(seconds: 5));
      final rename = service.saveChatSession(
        session.copyWith(title: 'Renamed concurrently'),
      );
      store.readRelease!.complete();
      await Future.wait([backfill, rename]).timeout(const Duration(seconds: 5));
      final result = (await service.loadChatSessions('c1')).single;
      expect(result.title, 'Renamed concurrently');
      expect(result.messageCount, 1);
    },
  );
  test(
    'structurally damaged chat count stays unknown without blocking healthy rows',
    () async {
      final damaged = await service.createChatSession('c1');
      final healthy = await service.createChatSession('c1');
      await File('${root.path}/chat_sessions.json').writeAsString(
        jsonEncode([
          for (final s in [damaged, healthy])
            {...s.toJson(), 'messageCount': null},
        ]),
      );
      await File(
        '${root.path}/chats/${damaged.id}.json',
      ).writeAsString('{"messages":"broken"}');
      final errors = <String>[];
      await service.backfillMessageCounts(
        await service.loadChatSessions('c1'),
        onError: (id, _) => errors.add(id),
      );
      expect(errors, [damaged.id]);
      final current = await service.loadChatSessions('c1');
      expect(current.singleWhere((s) => s.id == healthy.id).messageCount, 0);
      expect(
        current.singleWhere((s) => s.id == damaged.id).messageCount,
        isNull,
      );
    },
  );
  test('stale title patch preserves archive and latest count', () async {
    final session = await service.createChatSession('c1');
    await service.createChatSession('c1');
    await service.archiveChatSession(session);
    await service.saveChatBySession(session, [
      ChatMessage(role: 'user', content: 'one', time: DateTime(2026)),
    ]);
    await service.saveChatSession(session.copyWith(title: 'new'));
    final current = (await service.loadChatSessions(
      'c1',
    )).singleWhere((s) => s.id == session.id);
    expect(current.isArchived, isTrue);
    expect(current.messageCount, 1);
  });
  test(
    'empty assistant placeholders are neither persisted nor counted',
    () async {
      final session = await service.createChatSession('c1');
      await service.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'hello', time: DateTime(2026)),
        ChatMessage(role: 'assistant', content: '', time: DateTime(2026)),
      ]);
      expect((await service.loadChatSessions('c1')).single.messageCount, 1);
      expect(await service.loadChatBySession(session), hasLength(1));
    },
  );
  test(
    'known counts do not read chats and writes preserve latest title',
    () async {
      final old = await service.createChatSession('c1');
      await service.saveChatSession(old.copyWith(title: 'renamed'));
      await service.saveChatBySession(old, [
        ChatMessage(role: 'user', content: 'one', time: DateTime(2026)),
      ]);
      final sessions = await service.loadChatSessions('c1');
      store.chatReads = 0;
      await service.backfillMessageCounts(sessions);
      expect(store.chatReads, 0);
      expect(sessions.single.messageCount, 1);
      expect(sessions.single.title, 'renamed');
    },
  );
  test(
    'missing old chat reports unavailable instead of caching zero',
    () async {
      final session = await service.createChatSession('c1');
      await File('${root.path}/chat_sessions.json').writeAsString(
        jsonEncode([
          {...session.toJson(), 'messageCount': null},
        ]),
      );
      await File('${root.path}/chats/${session.id}.json').delete();
      final errors = <String>[];
      await service.backfillMessageCounts(
        await service.loadChatSessions('c1'),
        onError: (id, _) => errors.add(id),
      );
      expect(errors, [session.id]);
      expect(
        (await service.loadChatSessions('c1')).single.messageCount,
        isNull,
      );
    },
  );
  test('legacy backfill has at most two reads and keeps dates', () async {
    final sessions = [
      for (var i = 0; i < 8; i++) await service.createChatSession('c1'),
    ];
    await File('${root.path}/chat_sessions.json').writeAsString(
      jsonEncode([
        for (final s in sessions) {...s.toJson(), 'messageCount': null},
      ]),
    );
    await service.backfillMessageCounts(await service.loadChatSessions('c1'));
    expect(store.peak, lessThanOrEqualTo(2));
    final updated = await service.loadChatSessions('c1');
    expect(updated.every((s) => s.messageCount == 0), isTrue);
    for (final s in sessions) {
      expect(updated.singleWhere((u) => u.id == s.id).lastUsedAt, s.lastUsedAt);
    }
  });
}

class CountingStore extends JsonFileStore {
  Completer<void>? readEntered;
  Completer<void>? readRelease;
  int chatReads = 0;
  int active = 0;
  int peak = 0;
  @override
  Future<dynamic> read(
    File file,
    dynamic fallback, {
    bool recoverOnInvalid = false,
  }) async {
    final chat = file.path.replaceAll('\\', '/').contains('/chats/');
    if (chat) {
      chatReads++;
      active++;
      if (active > peak) peak = active;
    }
    try {
      if (chat && readEntered != null && !readEntered!.isCompleted) {
        readEntered!.complete();
        await readRelease!.future;
      }
      if (chat) await Future<void>.delayed(const Duration(milliseconds: 5));
      return await super.read(
        file,
        fallback,
        recoverOnInvalid: recoverOnInvalid,
      );
    } finally {
      if (chat) active--;
    }
  }
}
