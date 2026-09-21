import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_state.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/story/character_state_service.dart';
import 'package:whisnya/services/chat/chat_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalStorageService storage;
  late CharacterStateService service;
  final messages = [
    ChatMessage(
      id: 'm1',
      role: 'assistant',
      content: 'Hello',
      time: DateTime(2026),
    ),
  ];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('state_test_');
    storage = LocalStorageService(appDataDirectory: root);
    service = CharacterStateService(storage);
    await storage.jsonStore.write(File('${root.path}/chat_sessions.json'), [
      {'id': 's', 'characterId': 'c'},
    ]);
    await storage.jsonStore.write(File('${root.path}/chats/s.json'), {
      'sessionId': 's',
      'characterId': 'c',
      'messages': [for (final m in messages) m.toJson()],
    });
  });
  tearDown(() async {
    service.cancelStateRefresh('s');
    await root.delete(recursive: true);
  });
  test('locked null and text persist and refuse AI writes', () async {
    await service.editState(
      's',
      'c',
      messages,
      const StateEdit(
        expectedRevision: 0,
        values: {'location': 'room'},
        locks: {'location': true, 'emotion': true},
      ),
    );
    await service.requestStateRefresh(
      StateRefreshContext(
        sessionId: 's',
        characterId: 'c',
        messages: messages,
        loadMessages: () async => messages,
        isCurrent: () => true,
        generate: (s, u, t) async =>
            '{"emotion":"happy","location":"park","action":"wait"}',
      ),
    );
    final value = await CharacterStateService(
      storage,
    ).loadCurrentState('s', 'c', messages);
    expect(value.values['location'], 'room');
    expect(value.values['emotion'], null);
    expect(value.values['action'], 'wait');
  });
  test(
    'manual revision defeats late AI and prefix rollback is unknown',
    () async {
      final response = Completer<String>(), started = Completer<void>();
      final pending = service.requestStateRefresh(
        StateRefreshContext(
          sessionId: 's',
          characterId: 'c',
          messages: messages,
          loadMessages: () async => messages,
          isCurrent: () => true,
          generate: (s, u, t) {
            started.complete();
            return response.future;
          },
        ),
      );
      await started.future;
      await service.editState(
        's',
        'c',
        messages,
        const StateEdit(expectedRevision: 0, values: {'location': 'manual'}),
      );
      response.complete('{"location":"AI"}');
      await expectLater(pending, throwsStateError);
      expect(
        (await service.loadCurrentState('s', 'c', messages)).values['location'],
        'manual',
      );
      expect(
        (await service.loadCurrentState('s', 'c', [])).values['location'],
        null,
      );
    },
  );
  test('dataset replacement discards pending result', () async {
    final response = Completer<String>(), started = Completer<void>();
    final pending = service.requestStateRefresh(
      StateRefreshContext(
        sessionId: 's',
        characterId: 'c',
        messages: messages,
        loadMessages: () async => messages,
        isCurrent: () => true,
        generate: (s, u, t) {
          started.complete();
          return response.future;
        },
      ),
    );
    await started.future;
    await storage.jsonStore.maintain(() {}, advanceEpoch: true);
    response.complete('{"location":"old"}');
    await pending;
    expect(
      (await service.loadCurrentState('s', 'c', messages)).values['location'],
      null,
    );
  });
  test('new requests coalesce and discard in-flight older target', () async {
    final first = Completer<String>(), started = Completer<void>();
    var calls = 0;
    StateRefreshContext request() => StateRefreshContext(
      sessionId: 's',
      characterId: 'c',
      messages: messages,
      loadMessages: () async => messages,
      isCurrent: () => true,
      generate: (s, u, t) {
        calls++;
        if (calls == 1) {
          started.complete();
          return first.future;
        }
        return Future.value('{"location":"latest"}');
      },
    );
    final one = service.requestStateRefresh(request());
    await started.future;
    final two = service.requestStateRefresh(request());
    final three = service.requestStateRefresh(request());
    first.complete('{"location":"old"}');
    await Future.wait([one, two, three]);
    expect(calls, 2);
    expect(
      (await service.loadCurrentState('s', 'c', messages)).values['location'],
      'latest',
    );
  });
  test(
    'deleted session and stale formal prefix cannot recreate state',
    () async {
      await storage.jsonStore.write(File('${root.path}/chats/s.json'), {
        'sessionId': 's',
        'characterId': 'c',
        'messages': <dynamic>[],
      });
      await expectLater(
        service.editState(
          's',
          'c',
          messages,
          const StateEdit(expectedRevision: 0, values: {'location': 'stale'}),
        ),
        throwsStateError,
      );
      await storage.jsonStore.write(
        File('${root.path}/chat_sessions.json'),
        <dynamic>[],
      );
      await expectLater(
        service.editState(
          's',
          'c',
          [],
          const StateEdit(expectedRevision: 0, values: {'location': 'deleted'}),
        ),
        throwsStateError,
      );
      expect(await File('${root.path}/story/states/s.json').exists(), false);
    },
  );
  test('written state carries schema version for backup routing', () async {
    await service.editState(
      's',
      'c',
      messages,
      const StateEdit(expectedRevision: 0, values: {'location': 'room'}),
    );
    final data =
        jsonDecode(
              await File('${root.path}/story/states/s.json').readAsString(),
            )
            as Map<String, dynamic>;
    expect(data['schemaVersion'], 1);
    validateCharacterStateFile(data, sessionId: 's', characterId: 'c');
  });
  test('invalid JSON and null fields preserve known state on disk', () async {
    await service.editState(
      's',
      'c',
      messages,
      const StateEdit(expectedRevision: 0, values: {'location': 'room'}),
    );
    StateRefreshContext request(String response) => StateRefreshContext(
      sessionId: 's',
      characterId: 'c',
      messages: messages,
      loadMessages: () async => messages,
      isCurrent: () => true,
      generate: (s, u, t) async => response,
    );
    await expectLater(
      service.requestStateRefresh(request('{"location":"park","action":[]}')),
      throwsFormatException,
    );
    await service.requestStateRefresh(
      request('{"location":null,"emotion":""}'),
    );
    final state = await CharacterStateService(
      storage,
    ).loadCurrentState('s', 'c', messages);
    expect(state.values['location'], 'room');
    expect(state.revision, 1);
  });
  test('only one global request executes across service instances', () async {
    final second = CharacterStateService(storage);
    final started = Completer<void>(), release = Completer<String>();
    var secondStarted = false;
    final first = service.requestStateRefresh(
      StateRefreshContext(
        sessionId: 's',
        characterId: 'c',
        messages: messages,
        loadMessages: () async => messages,
        isCurrent: () => true,
        generate: (s, u, t) {
          started.complete();
          return release.future;
        },
      ),
    );
    await started.future;
    final next = second.requestStateRefresh(
      StateRefreshContext(
        sessionId: 's',
        characterId: 'c',
        messages: messages,
        loadMessages: () async => messages,
        isCurrent: () => true,
        generate: (s, u, t) async {
          secondStarted = true;
          return '{"action":"second"}';
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(secondStarted, false);
    release.complete('{"action":"first"}');
    await Future.wait([first, next]);
    expect(
      (await second.loadCurrentState('s', 'c', messages)).values['action'],
      'second',
    );
  });
  test(
    'whole-session duplicate copies independent state history and anchors',
    () async {
      final chats = ChatSessionService(
        root: root,
        jsonStore: storage.jsonStore,
      );
      final original = await chats.createChatSession('real_character');
      await chats.saveChatBySession(original, messages);
      final persisted = await chats.loadChatBySession(original);
      await service.editState(
        original.id,
        original.characterId,
        persisted,
        const StateEdit(
          expectedRevision: 0,
          values: {'location': 'original'},
          locks: {'location': true},
        ),
      );
      final copy = await chats.duplicateChatSession(original);
      final copied = await service.loadCurrentState(
        copy.id,
        copy.characterId,
        persisted,
      );
      expect(copied.values['location'], 'original');
      expect(copied.locks['location'], true);
      expect(copied.anchor!.sessionId, copy.id);
      await service.editState(
        copy.id,
        copy.characterId,
        persisted,
        StateEdit(
          expectedRevision: copied.revision,
          values: const {'location': 'copy only'},
        ),
      );
      expect(
        (await service.loadCurrentState(
          original.id,
          original.characterId,
          persisted,
        )).values['location'],
        'original',
      );
    },
  );
}
