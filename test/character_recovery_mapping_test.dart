import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/models/chat_session.dart';

void main() {
  late Directory root;
  late LocalStorageService storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('whisnya_recovery_');
    storage = LocalStorageService(appDataDirectory: root);
    await storage.ensureReady();
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> write(String path, Object value) async {
    await File('${root.path}/$path').writeAsString(jsonEncode(value));
  }

  test(
    'empty session recovery does not parse or modify corrupt index',
    () async {
      final file = File('${root.path}/chat_sessions.json');
      await file.writeAsString('{broken');
      await storage.restoreRecoveredChatSessions([]);
      expect(await file.readAsString(), '{broken');
    },
  );

  for (final broken in ['{broken', '{"unexpected":"object"}']) {
    test(
      'verified metadata rebuild preserves corrupt index evidence: $broken',
      () async {
        final file = File('${root.path}/chat_sessions.json');
        await file.writeAsString(broken);
        await storage.restoreRecoveredChatSessions([
          ChatSession.fromJson({
            'id': 's_verified',
            'characterId': 'c_verified',
          }),
        ]);
        final rows = jsonDecode(await file.readAsString()) as List<dynamic>;
        expect((rows.single as Map<String, dynamic>)['id'], 's_verified');
        final evidence = await root
            .list()
            .where(
              (f) =>
                  f is File && f.path.contains('chat_sessions.json.corrupt.'),
            )
            .cast<File>()
            .toList();
        expect(evidence, hasLength(1));
        expect(await evidence.single.readAsString(), broken);
        await storage.restoreRecoveredChatSessions([
          ChatSession.fromJson({
            'id': 's_verified',
            'characterId': 'c_verified',
          }),
        ]);
        expect(await evidence.single.readAsString(), broken);
      },
    );
  }

  test(
    'index recovery leaves existing raw rows untouched and appends only missing ids',
    () async {
      final old = {
        'id': 's1',
        'characterId': 'c1',
        'custom': {'futureField': true},
        'title': '  untouched  ',
      };
      await write('chat_sessions.json', [old, 'damaged row']);
      final file = File('${root.path}/chat_sessions.json');
      final before = await file.readAsString();
      await storage.restoreRecoveredChatSessions([
        ChatSession.fromJson({'id': 's1', 'characterId': 'c1'}),
      ]);
      expect(await file.readAsString(), before);
      await storage.restoreRecoveredChatSessions([
        ChatSession.fromJson({'id': 's1', 'characterId': 'c1'}),
        ChatSession.fromJson({'id': 's2', 'characterId': 'c1'}),
      ]);
      final rows = jsonDecode(await file.readAsString()) as List;
      expect(rows, hasLength(3));
      expect(rows[0], old);
      expect(rows[1], 'damaged row');
      expect((rows[2] as Map)['id'], 's2');
    },
  );

  test(
    'four sessions recover two real characters without changing files',
    () async {
      final sessions = [
        for (var i = 0; i < 4; i++)
          {
            'id': 'chat_session_$i',
            'characterId': 'character_${i ~/ 2}',
            'title': 's$i',
          },
      ];
      await write('chat_sessions.json', sessions);
      for (final session in sessions) {
        await write('chats/${session['id']}.json', {
          'sessionId': session['id'],
          'characterId': session['characterId'],
          'messages': [
            {'role': 'assistant', 'content': 'hello', 'innerVoice': 'voice'},
          ],
        });
      }
      final before = await File(
        '${root.path}/chats/chat_session_0.json',
      ).readAsString();
      final characters = await storage.loadCharacters();
      expect(characters.map((c) => c.id).toSet(), {
        'character_0',
        'character_1',
      });
      expect((await storage.loadCharacters()).length, 2);
      expect(
        await File('${root.path}/chats/chat_session_0.json').readAsString(),
        before,
      );
      expect(
        jsonDecode(
          await File('${root.path}/chat_sessions.json').readAsString(),
        ),
        sessions,
      );
    },
  );

  test('unmapped session filename never becomes a character', () async {
    await write('chats/chat_session_123.json', {'messages': <dynamic>[]});
    expect(await storage.loadCharacters(), isEmpty);
    expect(storage.takeRecoveryMessages(), isNotEmpty);
  });

  test(
    'explicit metadata rebuilds missing index with original session ids',
    () async {
      await write('chats/chat_session_77.json', {
        'sessionId': 'chat_session_77',
        'characterId': 'character_77',
        'messages': [
          {'role': 'assistant', 'content': 'recover me'},
        ],
      });
      expect((await storage.loadCharacters()).single.id, 'character_77');
      final sessions = await storage.loadChatSessions('character_77');
      expect(sessions.single.id, 'chat_session_77');
      expect(
        (await storage.loadChatBySession(sessions.single)).single.content,
        'recover me',
      );
    },
  );

  test('legacy character filename is accepted only for legacy data', () async {
    await write('chats/character_123.json', [
      {'role': 'user', 'content': 'legacy'},
    ]);
    expect((await storage.loadCharacters()).single.id, 'character_123');
  });

  test(
    'recovered legacy bare chat list opens without losing raw fields or original evidence',
    () async {
      final rows = [
        {
          'role': 'user',
          'content': 'original text',
          'custom': {'keep': true},
        },
        {
          'role': 'assistant',
          'content': 'reply',
          'innerVoice': 'voice',
          'futureField': 42,
        },
      ];
      await write('chats/character_456.json', rows);
      final original = File('${root.path}/chats/character_456.json');
      final before = await original.readAsString();
      final characters = await storage.loadCharacters();
      expect(characters.single.id, 'character_456');
      final session = (await storage.loadChatSessions('character_456')).single;
      final chat = await storage.loadChatBySession(session);
      expect(chat.map((m) => m.content), ['original text', 'reply']);
      expect(chat.last.effectiveInnerVoice, 'voice');
      final migrated =
          jsonDecode(
                await File(
                  '${root.path}/chats/${session.id}.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final migratedRows = (migrated['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(migratedRows.map((row) => row['id']), chat.map((m) => m.id));
      expect(chat.every((message) => message.id.isNotEmpty), isTrue);
      expect(chat.map((message) => message.id).toSet(), hasLength(rows.length));
      expect([
        for (final row in migratedRows)
          Map<String, dynamic>.from(row)..remove('id'),
      ], rows);
      final reopened = await storage.loadChatBySession(session);
      expect(
        reopened.map((message) => message.id),
        chat.map((message) => message.id),
      );
      final evidence = await Directory('${root.path}/chats')
          .list()
          .where(
            (f) => f is File && f.path.contains('character_456.json.migrated.'),
          )
          .cast<File>()
          .toList();
      expect(evidence, hasLength(1));
      expect(await evidence.single.readAsString(), before);
    },
  );

  test(
    'conflicting metadata is reported without assigning either character',
    () async {
      await write('chat_sessions.json', [
        {'id': 'chat_session_1', 'characterId': 'character_1'},
      ]);
      await write('chats/chat_session_1.json', {
        'sessionId': 'chat_session_1',
        'characterId': 'character_2',
        'messages': <dynamic>[],
      });
      expect(await storage.loadCharacters(), isEmpty);
      expect(storage.takeRecoveryMessages().join(), contains('冲突'));
    },
  );

  test(
    'explicit empty characters list does not resurrect deleted records',
    () async {
      await write('characters.json', []);
      await write('chats/character_123.json', []);
      expect(await storage.loadCharacters(), isEmpty);
    },
  );

  test(
    'malformed character row preserves usable entries and raw evidence',
    () async {
      await write('characters.json', [
        {'id': 'character_1', 'name': 'kept'},
        {'id': 7, 'name': 'bad'},
      ]);
      final result = await storage.loadCharacters();
      expect(result.single.name, 'kept');
      expect(storage.takeRecoveryMessages().join(), contains('1'));
      expect(
        await File('${root.path}/characters.json').readAsString(),
        contains('bad'),
      );
    },
  );
}
