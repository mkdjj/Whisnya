import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_state.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/services/chat/chat_session_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';

class _FailingIndexStore extends JsonFileStore {
  bool fail = false;
  @override
  Future<void> writeNow(File file, dynamic data, {bool compact = false}) {
    if (fail && file.path.endsWith('chat_sessions.json')) {
      fail = false;
      throw FileSystemException('injected index failure', file.path);
    }
    return super.writeNow(file, data, compact: compact);
  }
}

void main() {
  late Directory root;
  late _FailingIndexStore store;
  late ChatSessionService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('state_lifecycle_');
    store = _FailingIndexStore();
    service = ChatSessionService(root: root, jsonStore: store);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<File> initialState(String id) async {
    final value = CharacterStateView.unknown(id, 'c').apply(
      const StateEdit(
        expectedRevision: 0,
        values: {'location': 'initial room'},
        locks: {'location': true},
      ),
      null,
      'branchInitial',
    );
    final file = File('${root.path}/story/states/$id.json');
    await store.write(file, {
      'schemaVersion': 1,
      'sessionId': id,
      'characterId': 'c',
      'stateRevision': 1,
      'history': [value.toJson()],
    });
    return file;
  }

  test('successful clear removes even anchor-null initial state', () async {
    final session = await service.createChatSession('c');
    final state = await initialState(session.id);
    await service.clearChatPreservingSummary(session);
    expect(await state.exists(), false);
  });
  test(
    'failed clear restores exact raw state with locks and provenance',
    () async {
      final session = await service.createChatSession('c');
      await service.saveChatBySession(session, [
        ChatMessage(role: 'user', content: 'before', time: DateTime(2026)),
      ]);
      final state = await initialState(session.id);
      final previous = jsonDecode(await state.readAsString());
      store.fail = true;
      await expectLater(
        service.clearChatPreservingSummary(session),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(await state.readAsString()), previous);
      expect(
        (await service.loadChatBySession(session)).single.content,
        'before',
      );
    },
  );
  test(
    'delete session removes its state without touching other state',
    () async {
      final one = await service.createChatSession('c'),
          two = await service.createChatSession('c');
      final removed = await initialState(one.id),
          kept = await initialState(two.id);
      await service.deleteChatSession(one);
      expect(await removed.exists(), false);
      expect(await kept.exists(), true);
    },
  );
  test('restart rolls back state removed by an interrupted clear', () async {
    final session = await service.createChatSession('c');
    final state = await initialState(session.id);
    final rawState = jsonDecode(await state.readAsString());
    final rawChat = jsonDecode(
      await File('${root.path}/chats/${session.id}.json').readAsString(),
    );
    final rawSummary = jsonDecode(
      await File('${root.path}/summaries/${session.id}.json').readAsString(),
    );
    await store
        .write(File('${root.path}/transactions/clear_${session.id}.json'), {
          'session': session.toJson(),
          'chat': rawChat,
          'summary': rawSummary,
          'state': rawState,
        });
    await state.delete();
    await ChatSessionService(root: root).recoverPendingClears();
    expect(jsonDecode(await state.readAsString()), rawState);
    expect(
      await File('${root.path}/transactions/clear_${session.id}.json').exists(),
      false,
    );
  });
  test(
    'startup quarantines orphan state but retains indexed and corrupt-index data',
    () async {
      final session = await service.createChatSession('c');
      final kept = await initialState(session.id),
          orphan = await initialState('deleted');
      await service.recoverPendingClears(pruneOrphanState: true);
      expect(await kept.exists(), true);
      expect(await orphan.exists(), false);
      expect(await File('${orphan.path}.orphan').exists(), true);
      final uncertain = await initialState('uncertain');
      await store.write(File('${root.path}/chat_sessions.json'), {
        'bad': 'index',
      });
      await service.recoverPendingClears(pruneOrphanState: true);
      expect(await uncertain.exists(), true);
    },
  );
  test(
    'duplicate of isolated branch keeps isolation and independent initial state',
    () async {
      final original = await service.createChatSession('c');
      final branch = ChatSession.fromJson({
        ...original.toJson(),
        'isStoryBranch': true,
        'sourceCheckpointId': 'cp',
        'parentSessionId': 'parent',
        'branchRootSessionId': 'parent',
        'allowSharedCharacterMemories': false,
      });
      await store.write(File('${root.path}/chat_sessions.json'), [
        branch.toJson(),
      ]);
      final source = await initialState(branch.id);
      final duplicate = await service.duplicateChatSession(branch);
      expect(duplicate.isStoryBranch, true);
      expect(duplicate.allowSharedCharacterMemories, false);
      expect(duplicate.sourceCheckpointId, 'cp');
      final copied =
          jsonDecode(
                await File(
                  '${root.path}/story/states/${duplicate.id}.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(copied['sessionId'], duplicate.id);
      final first =
          (copied['history'] as List<dynamic>).first as Map<String, dynamic>;
      expect(
        (first['values'] as Map<String, dynamic>)['location'],
        'initial room',
      );
      await service.clearChatPreservingSummary(duplicate);
      expect(await source.exists(), true);
    },
  );
}
