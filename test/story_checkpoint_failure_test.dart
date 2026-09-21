import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/message_anchor.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';
import 'package:whisnya/services/story/story_checkpoint_service.dart';

class FailingStore extends JsonFileStore {
  String? failSuffix;
  @override
  Future<void> writeNow(File file, dynamic data, {bool compact = false}) async {
    if (failSuffix != null &&
        file.path.replaceAll('\\', '/').endsWith(failSuffix!)) {
      failSuffix = null;
      throw FileSystemException('injected');
    }
    await super.writeNow(file, data, compact: compact);
  }
}

void main() {
  for (final failure in ['chats/', 'summaries/', 'chat_sessions.json']) {
    test(
      'failed branch publication recovers own unindexed files $failure',
      () async {
        final root = await Directory.systemTemp.createTemp('story_failure_');
        addTearDown(() => root.delete(recursive: true));
        final store = FailingStore();
        final storage = LocalStorageService(
          appDataDirectory: root,
          jsonStore: store,
        );
        final c = AppCharacter.fromJson({'id': 'c', 'name': 'Role'});
        await storage.saveCharacter(c);
        final source = await storage.createChatSession('c');
        final messages = [
          ChatMessage(
            id: 'm',
            role: 'user',
            content: 'past',
            time: DateTime(2026),
          ),
        ];
        await storage.saveChatBySession(source, messages);
        final service = StoryCheckpointService(storage);
        final checkpoint = await service.create(
          source: source,
          character: c,
          anchor: MessageAnchor.capture(source.id, messages, 0),
          title: 'checkpoint',
        );
        // The journal identifies the generated ID; intercept its next payload.
        final failing = _BranchFailingStore(store, failure);
        final faultStorage = LocalStorageService(
          appDataDirectory: root,
          jsonStore: failing,
        );
        await expectLater(
          StoryCheckpointService(
            faultStorage,
          ).fork(checkpoint.id, title: 'branch'),
          throwsA(isA<FileSystemException>()),
        );
        await StoryCheckpointService.recover(storage);
        expect(await storage.loadChatSessions('c'), hasLength(1));
        expect(
          (await storage.loadChatBySession(source)).single.content,
          'past',
        );
        expect(
          await Directory(
            '${root.path}/chats',
          ).list().where((f) => f.path.endsWith('.json')).length,
          1,
        );
      },
    );
  }
  test(
    'checkpoint failed index publication leaves no invisible payload',
    () async {
      final root = await Directory.systemTemp.createTemp('checkpoint_failure_');
      addTearDown(() => root.delete(recursive: true));
      final store = FailingStore();
      final storage = LocalStorageService(
        appDataDirectory: root,
        jsonStore: store,
      );
      final c = AppCharacter.fromJson({'id': 'c', 'name': 'Role'});
      await storage.saveCharacter(c);
      final s = await storage.createChatSession('c');
      final m = [
        ChatMessage(
          id: 'm',
          role: 'user',
          content: 'saved',
          time: DateTime(2026),
        ),
      ];
      await storage.saveChatBySession(s, m);
      store.failSuffix = 'checkpoints/index.json';
      await expectLater(
        StoryCheckpointService(storage).create(
          source: s,
          character: c,
          anchor: MessageAnchor.capture(s.id, m, 0),
          title: 'test',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await Directory('${root.path}/story/checkpoints').list().length,
        0,
      );
    },
  );
}

class _BranchFailingStore extends JsonFileStore {
  _BranchFailingStore(JsonFileStore _, this.target);
  final String target;
  bool failed = false;
  @override
  Future<void> writeNow(File f, dynamic data, {bool compact = false}) async {
    final path = f.path.replaceAll('\\', '/');
    if (!failed &&
        (target.endsWith('/')
            ? path.contains('/$target')
            : path.endsWith(target))) {
      failed = true;
      throw FileSystemException('injected');
    }
    await super.writeNow(f, data, compact: compact);
  }
}
