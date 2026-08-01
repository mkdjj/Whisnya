import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/services/chat/chat_session_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';
import 'package:whisnya/services/storage/storage_paths.dart';

void main() {
  late Directory directory;
  late ChatSessionService service;
  late StoragePaths paths;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whisnya_sessions_');
    service = ChatSessionService(root: directory);
    paths = StoragePaths(directory);
  });

  tearDown(() => directory.delete(recursive: true));

  test('first load creates one stable default session', () async {
    final first = await service.loadChatSessions('c1');
    final second = await service.loadChatSessions('c1');

    expect(first, hasLength(1));
    expect(first.single.title, '默认对话');
    expect(second.single.id, first.single.id);
    expect(await paths.chatBySession(first.single.id).exists(), isTrue);
    expect(await paths.summaryBySession(first.single.id).exists(), isTrue);
  });

  for (final fixture in const [
    (chat: true, summary: false),
    (chat: false, summary: true),
    (chat: true, summary: true),
  ]) {
    test(
      'migrates legacy chat=${fixture.chat} summary=${fixture.summary}',
      () async {
        if (fixture.chat) {
          await _writeJson(paths.chat('c1'), {
            'characterId': 'c1',
            'messages': [
              {
                'role': 'user',
                'content': 'legacy message',
                'time': '2026-01-01T00:00:00.000',
              },
            ],
          });
        }
        if (fixture.summary) {
          await _writeJson(paths.summary('c1'), {
            'characterId': 'c1',
            'summary': 'legacy summary',
            'updatedAt': '2026-01-01T00:00:00.000',
            'summarizedMessageCount': 1,
          });
        }

        final session = (await service.loadChatSessions('c1')).single;

        expect(session.id, 'legacy_session_c1');
        expect(
          (await service.loadChatBySession(
            session,
          )).map((message) => message.content),
          fixture.chat ? ['legacy message'] : isEmpty,
        );
        expect(
          (await service.loadSummaryBySession(session)).summary,
          fixture.summary ? 'legacy summary' : isEmpty,
        );
        expect(await paths.chat('c1').exists(), isFalse);
        expect(await paths.summary('c1').exists(), isFalse);
        expect(await service.loadChatSessions('c1'), hasLength(1));
        expect(session.toJson()['openingMessageInitialized'], fixture.chat);
      },
    );
  }

  test('existing session prevents duplicate legacy migration', () async {
    final existing = await service.createChatSession('c1', title: 'Current');
    await _writeJson(paths.chat('c1'), {
      'characterId': 'c1',
      'messages': <dynamic>[],
    });

    final sessions = await service.loadChatSessions('c1');

    expect(sessions.map((session) => session.id), [existing.id]);
    expect(await paths.chat('c1').exists(), isTrue);
  });

  test('migration failure leaves legacy files for a retry', () async {
    await _writeJson(paths.chat('c1'), {
      'characterId': 'c1',
      'messages': <dynamic>[],
    });
    final failing = ChatSessionService(
      root: directory,
      jsonStore: _FailingStore('legacy_session_c1.json'),
    );

    await expectLater(
      failing.loadChatSessions('c1'),
      throwsA(isA<FileSystemException>()),
    );

    expect(await paths.chat('c1').exists(), isTrue);
    expect(await paths.chatSessions.exists(), isFalse);
  });

  test(
    'create save copy archive and delete preserve session boundaries',
    () async {
      final first = (await service.loadChatSessions('c1')).single;
      final renamed = first.copyWith(
        title: ' Main ',
        lastUsedAt: DateTime(2026),
      );
      await service.saveChatSession(renamed);
      await service.saveChatBySession(renamed, [
        ChatMessage(role: 'user', content: 'hello', time: DateTime(2026)),
      ]);
      await service.saveSummaryBySession(
        ChatSummary(
          characterId: 'c1',
          sessionId: renamed.id,
          summary: 'summary',
          updatedAt: DateTime(2026),
          summarizedMessageCount: 1,
        ),
      );

      final copy = await service.duplicateChatSession(renamed);

      expect(copy.id, isNot(renamed.id));
      expect(copy.title, 'Main（副本）');
      expect((await service.loadChatBySession(copy)).single.content, 'hello');
      expect((await service.loadSummaryBySession(copy)).summary, 'summary');
      await service.archiveChatSession(copy);
      expect(
        (await service.loadChatSessions(
          'c1',
        )).singleWhere((session) => session.id == copy.id).isArchived,
        isTrue,
      );
      await service.unarchiveChatSession(copy);
      await service.deleteChatSession(copy);
      expect(
        (await service.loadChatSessions('c1')).map((session) => session.id),
        isNot(contains(copy.id)),
      );
      expect(await paths.chatBySession(copy.id).exists(), isFalse);
      expect(await paths.summaryBySession(copy.id).exists(), isFalse);
    },
  );

  test(
    'last active session cannot be archived and deletion replaces it',
    () async {
      final only = (await service.loadChatSessions('c1')).single;

      await expectLater(
        service.archiveChatSession(only),
        throwsA(isA<StateError>()),
      );
      await service.deleteChatSession(only);

      final replacement = (await service.loadChatSessions('c1')).single;
      expect(replacement.id, isNot(only.id));
      expect(replacement.isArchived, isFalse);
    },
  );

  test('concurrent saves keep all sessions in the index', () async {
    await Future.wait([
      for (var index = 0; index < 8; index++)
        service.createChatSession('c1', title: 'Session $index'),
    ]);

    expect(await service.loadChatSessions('c1'), hasLength(8));
  });

  test(
    'duplicating a populated session keeps opening message initialized',
    () async {
      final source = await service.createChatSession('c1');
      await service.saveChatBySession(source, [
        ChatMessage(role: 'user', content: 'hello', time: DateTime(2026)),
      ]);

      final copy = await service.duplicateChatSession(source);

      expect(copy.toJson()['openingMessageInitialized'], isTrue);
    },
  );

  test(
    'duplicating an initialized empty session does not reset its state',
    () async {
      final source = await service.createChatSession('c1');
      await service.saveChatSession(
        ChatSession.fromJson({
          ...source.toJson(),
          'openingMessageInitialized': true,
        }),
      );

      final refreshed = (await service.loadChatSessions('c1')).single;
      final copy = await service.duplicateChatSession(refreshed);

      expect(copy.toJson()['openingMessageInitialized'], isTrue);
    },
  );

  test(
    'duplicating with a stale source uses the latest opening state',
    () async {
      final stale = await service.createChatSession('c1');
      await service.saveChatSession(
        stale.copyWith(openingMessageInitialized: true),
      );

      final copy = await service.duplicateChatSession(stale);

      expect(copy.openingMessageInitialized, isTrue);
    },
  );

  test('saving chat with a stale session preserves the latest title', () async {
    final stale = await service.createChatSession('c1', title: 'Old');
    await service.saveChatSession(stale.copyWith(title: 'New'));

    await service.saveChatBySession(stale, [
      ChatMessage(role: 'user', content: 'hello', time: DateTime(2026)),
    ]);

    final saved = (await service.loadChatSessions('c1')).single;
    expect(saved.title, 'New');
    expect(saved.createdAt, stale.createdAt);
  });

  test('saving chat with a stale session preserves archived state', () async {
    final stale = await service.createChatSession('c1', title: 'Archived');
    await service.createChatSession('c1', title: 'Active');
    await service.archiveChatSession(stale);

    await service.saveChatBySession(stale, [
      ChatMessage(role: 'user', content: 'hello', time: DateTime(2026)),
    ]);

    final saved = (await service.loadChatSessions(
      'c1',
    )).singleWhere((session) => session.id == stale.id);
    expect(saved.isArchived, isTrue);
  });

  test(
    'opening initialization updates only the latest indexed session',
    () async {
      final stale = await service.createChatSession('c1', title: 'Old');
      await service.createChatSession('c1', title: 'Active');
      await service.saveChatSession(stale.copyWith(title: 'New'));
      final current = (await service.loadChatSessions(
        'c1',
      )).singleWhere((session) => session.id == stale.id);
      await service.archiveChatSession(current);

      final updated = await service.markOpeningMessageInitialized(
        sessionId: stale.id,
        characterId: stale.characterId,
      );

      expect(updated.title, 'New');
      expect(updated.isArchived, isTrue);
      expect(updated.createdAt, stale.createdAt);
      expect(updated.openingMessageInitialized, isTrue);
    },
  );

  test('deleting a character removes all its session data only', () async {
    final c1 = await service.createChatSession('c1');
    final c2 = await service.createChatSession('c2');
    await service.saveChatBySession(c1, [
      ChatMessage(role: 'user', content: 'one', time: DateTime(2026)),
    ]);

    await service.deleteCharacterSessions('c1');

    expect(await paths.chatBySession(c1.id).exists(), isFalse);
    expect((await service.loadChatSessions('c2')).single.id, c2.id);
  });

  test('memory writes upsert and serialize concurrent changes', () async {
    final now = DateTime(2026);
    final first = CharacterMemoryEntry(
      id: 'memory_1',
      characterId: 'c1',
      scope: MemoryScope.character,
      title: 'First',
      content: 'one',
      createdAt: now,
      updatedAt: now,
    );
    final second = CharacterMemoryEntry(
      id: 'memory_2',
      characterId: 'c1',
      scope: MemoryScope.character,
      title: 'Second',
      content: 'two',
      createdAt: now,
      updatedAt: now,
    );

    await Future.wait([
      service.saveCharacterMemory(first),
      service.saveCharacterMemory(second),
    ]);
    await service.saveCharacterMemory(first.copyWith(content: 'updated'));

    final memories = await service.loadCharacterMemories('c1');
    expect(memories, hasLength(2));
    expect(
      memories.singleWhere((entry) => entry.id == first.id).content,
      'updated',
    );
  });

  test(
    'session memory duplicates and deletes without touching shared memory',
    () async {
      final source = await service.createChatSession('c1');
      final now = DateTime(2026);
      await service.saveCharacterMemory(
        CharacterMemoryEntry(
          id: 'shared',
          characterId: 'c1',
          scope: MemoryScope.character,
          title: 'Shared',
          content: 'all sessions',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await service.saveCharacterMemory(
        CharacterMemoryEntry(
          id: 'local',
          characterId: 'c1',
          scope: MemoryScope.session,
          sessionId: source.id,
          title: 'Local',
          content: 'one session',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final target = await service.duplicateChatSession(source);
      final copied = await service.loadCharacterMemories('c1');

      expect(
        copied.where((entry) => entry.scope == MemoryScope.character),
        hasLength(1),
      );
      expect(
        copied.where((entry) => entry.sessionId == target.id).single.content,
        'one session',
      );
      await service.deleteSessionMemories('c1', target.id);
      final remaining = await service.loadCharacterMemories('c1');
      expect(remaining.any((entry) => entry.sessionId == target.id), isFalse);
      expect(remaining.any((entry) => entry.id == 'shared'), isTrue);
    },
  );

  test(
    'local storage exposes session APIs and character deletion cleans them',
    () async {
      final storage = LocalStorageService(appDataDirectory: directory);
      final session = await storage.createChatSession('c1', title: 'Direct');
      await storage.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'hello', time: DateTime(2026)),
      ]);
      await storage.saveCharacterMemory(
        CharacterMemoryEntry(
          id: 'memory',
          characterId: 'c1',
          scope: MemoryScope.session,
          sessionId: session.id,
          title: 'Local',
          content: 'memory',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      expect(
        (await storage.loadChatBySession(session)).single.content,
        'hello',
      );
      await storage.deleteCharacter('c1');
      expect(await paths.chatBySession(session.id).exists(), isFalse);
      expect(await paths.characterMemories('c1').exists(), isFalse);
    },
  );

  test('full backup advertises schema version 3', () async {
    final storage = LocalStorageService(appDataDirectory: directory);
    final archive = ZipDecoder().decodeBytes(await storage.exportAllData());
    final manifest = archive.findFile('backup_manifest.json')!;
    final decoded =
        jsonDecode(utf8.decode(manifest.content as List<int>))
            as Map<String, dynamic>;

    expect(decoded['schemaVersion'], 3);
  });
}

Future<void> _writeJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(value));
}

final class _FailingStore extends JsonFileStore {
  _FailingStore(this.fileName);

  final String fileName;

  @override
  Future<void> writeNow(File file, dynamic data, {bool compact = false}) {
    if (file.path.endsWith(fileName)) {
      throw FileSystemException('simulated write failure', file.path);
    }
    return super.writeNow(file, data, compact: compact);
  }
}
