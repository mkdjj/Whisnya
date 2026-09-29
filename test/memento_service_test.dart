import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/memento.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
import 'package:whisnya/services/memento_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';

class FailingCollectionIndexStore extends JsonFileStore {
  bool fail = false;
  @override
  Future<void> writeNow(File file, dynamic data, {bool compact = false}) {
    if (fail &&
        file.path.replaceAll('\\', '/').endsWith('/collection/index.json')) {
      return Future.error(FileSystemException('injected'));
    }
    return super.writeNow(file, data, compact: compact);
  }
}

class CountingCollectionItemStore extends JsonFileStore {
  final itemReads = <String, int>{};
  int characterReads = 0;

  @override
  Future<dynamic> read(
    File file,
    dynamic fallback, {
    bool recoverOnInvalid = false,
  }) {
    final path = file.path.replaceAll('\\', '/');
    if (path.contains('/collection/items/')) {
      itemReads.update(file.path, (count) => count + 1, ifAbsent: () => 1);
    }
    if (path.endsWith('/characters.json')) characterReads++;
    return super.read(file, fallback, recoverOnInvalid: recoverOnInvalid);
  }
}

void main() {
  late Directory dir;
  late LocalStorageService storage;
  final messages = [
    ChatMessage(
      id: 'm',
      role: 'assistant',
      content: 'Stay',
      innerVoice: 'relief',
      time: DateTime.utc(2026),
    ),
  ];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mementos');
    storage = LocalStorageService(appDataDirectory: dir);
    await storage.jsonStore.write(File('${dir.path}/chat_sessions.json'), [
      {'id': 's', 'characterId': 'c'},
    ]);
    await storage.jsonStore.write(File('${dir.path}/chats/s.json'), {
      'messages': messages.map((m) => m.toJson()).toList(),
    });
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'selected candidate snapshot is immutable after disk candidate switch and contains no reasoning',
    () async {
      final message = messages.single.copyWith(
        variants: [
          ChatReplyVariant(
            id: 'v1',
            content: 'A',
            innerVoice: 'IA',
            reasoningContent: 'PRIVATE_R',
            time: DateTime.utc(2026),
          ),
          ChatReplyVariant(
            id: 'v2',
            content: 'B',
            innerVoice: 'IB',
            time: DateTime.utc(2026),
          ),
        ],
      );
      await storage.jsonStore.write(File('${dir.path}/chats/s.json'), [
        message.toJson(),
      ]);
      final saved = await MementoService(storage: storage).createMemento(
        MementoDraft(
          idempotencyKey: 'variant',
          title: 'Moment',
          characterId: 'c',
          characterNameSnapshot: 'Before',
          sessionTitleSnapshot: 'Chat',
          sourceSessionId: 's',
          entries: [
            MementoEntry.capture(
              sessionId: 's',
              messages: [message],
              index: 0,
              speakerName: 'Before',
            ),
          ],
        ),
      );
      await storage.jsonStore.write(File('${dir.path}/chats/s.json'), [
        message.copyWith(selectedVariantIndex: 1).toJson(),
      ]);
      final reloaded = await MementoService(
        storage: storage,
      ).loadMemento(saved.id);
      expect(reloaded.entries.single.contentSnapshot, 'A');
      expect(reloaded.entries.single.innerVoiceSnapshot, 'IA');
      expect(reloaded.entries.single.sourceVariantId, 'v1');
      expect(
        await (await MementoService(
          storage: storage,
        ).paths).item(saved.id).readAsString(),
        isNot(contains('PRIVATE_R')),
      );
      expect(
        await MementoService(storage: storage).locateMementoSource(saved.id, 0),
        SourceNavigationResult.variantChanged,
      );
    },
  );
  MementoDraft draft(String key, {bool locked = false}) => MementoDraft(
    idempotencyKey: key,
    title: 'Moment',
    characterId: 'c',
    characterNameSnapshot: 'Before',
    sessionTitleSnapshot: 'Chat',
    sourceSessionId: 's',
    requiresUnlock: locked,
    entries: [
      MementoEntry.capture(
        sessionId: 's',
        messages: messages,
        index: 0,
        speakerName: 'Before',
      ),
    ],
  );
  test(
    'disk snapshots survive restart; submission retries do not duplicate',
    () async {
      final service = MementoService(storage: storage);
      final saved = await service.createMemento(draft('retry'));
      expect(await service.protectionState(saved.id), false);
      expect(await service.hasEquivalentCapture(draft('new')), true);
      expect((await service.createMemento(draft('retry'))).id, saved.id);
      final other = await service.createMemento(draft('new'));
      expect(other.id, isNot(saved.id));
      final reloaded = await MementoService(
        storage: storage,
      ).loadMemento(saved.id);
      expect(reloaded.entries.single.contentSnapshot, 'Stay');
      expect(reloaded.entries.single.innerVoiceSnapshot, 'relief');
      expect(() => reloaded.entries.clear(), throwsUnsupportedError);
      await File('${dir.path}/chat_sessions.json').delete();
      expect(
        await service.locateMementoSource(saved.id, 0),
        SourceNavigationResult.sourceMissing,
      );
      await service.updateMementoMetadata(
        MementoMetadataPatch(
          id: saved.id,
          title: 'Changed',
          tags: ['tag'],
          note: 'note',
        ),
      );
      expect(
        (await service.loadMemento(saved.id)).entries.single.contentSnapshot,
        'Stay',
      );
    },
  );
  test('deleted source never unlocks a protected snapshot or search', () async {
    final unlocked = MementoService(
      storage: storage,
      authorize: (_, _) async => true,
    );
    final saved = await unlocked.createMemento(draft('secret', locked: true));
    final locked = MementoService(storage: storage);
    await expectLater(
      locked.hasEquivalentCapture(draft('other', locked: true)),
      throwsStateError,
    );
    expect(
      await locked.queryMementos(const MementoQuery(keyword: 'Stay')),
      isEmpty,
    );
    await expectLater(locked.loadMemento(saved.id), throwsStateError);
    await expectLater(locked.deleteMemento(saved.id), throwsStateError);
  });
  test('metadata limits reject invalid snapshots before publication', () async {
    final d = draft('bad');
    await expectLater(
      MementoService(storage: storage).createMemento(
        MementoDraft(
          idempotencyKey: d.idempotencyKey,
          title: '',
          characterId: 'c',
          characterNameSnapshot: 'c',
          sessionTitleSnapshot: 's',
          sourceSessionId: 's',
          entries: d.entries,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      await MementoService(
        storage: storage,
      ).queryMementos(const MementoQuery()),
      isEmpty,
    );
  });
  test('stale selected source fails without publishing a snapshot', () async {
    final d = draft('stale');
    await storage.jsonStore.write(File('${dir.path}/chats/s.json'), [
      messages.single.copyWith(content: 'Leave').toJson(),
    ]);
    await expectLater(
      MementoService(storage: storage).createMemento(d),
      throwsStateError,
    );
    expect(
      await MementoService(
        storage: storage,
      ).queryMementos(const MementoQuery()),
      isEmpty,
    );
  });
  test(
    'collection media survives source deletion then is reclaimed with last reference',
    () async {
      final source = File('${dir.path}/avatar.png');
      await source.writeAsBytes([1, 2, 3]);
      final service = MementoService(storage: storage);
      final asset = await service.copyRecognizedAvatar(
        source.path,
        recognizedPaths: {source.path},
      );
      final d = draft('avatar');
      final item = await service.createMemento(
        MementoDraft(
          idempotencyKey: d.idempotencyKey,
          title: d.title,
          characterId: d.characterId,
          characterNameSnapshot: d.characterNameSnapshot,
          sessionTitleSnapshot: d.sessionTitleSnapshot,
          sourceSessionId: d.sourceSessionId,
          entries: [
            MementoEntry.capture(
              sessionId: 's',
              messages: messages,
              index: 0,
              speakerName: 'Before',
              avatarAssetId: asset,
            ),
          ],
        ),
      );
      await source.delete();
      final media = (await service.paths).media(asset!);
      expect(await media.readAsBytes(), [1, 2, 3]);
      await service.deleteMemento(item.id);
      expect(await media.exists(), false);
    },
  );
  test('deleting a snapshot without avatars skips other item reads', () async {
    final store = CountingCollectionItemStore();
    final service = MementoService(
      storage: LocalStorageService(appDataDirectory: dir, jsonStore: store),
    );
    final removed = await service.createMemento(draft('no-avatar-removed'));
    final kept = await service.createMemento(draft('no-avatar-kept'));
    final paths = await service.paths;
    store.itemReads.clear();

    await service.deleteMemento(removed.id);

    expect(store.itemReads[paths.item(kept.id).path] ?? 0, 0);
    expect(await paths.item(removed.id).exists(), false);
    expect(await paths.item(kept.id).exists(), true);
  });
  test(
    'collection query reads current character locks once for all rows',
    () async {
      final store = CountingCollectionItemStore();
      final service = MementoService(
        storage: LocalStorageService(appDataDirectory: dir, jsonStore: store),
      );
      await service.createMemento(draft('query-a'));
      await service.createMemento(draft('query-b'));
      await service.createMemento(draft('query-c'));
      store.characterReads = 0;

      expect(await service.queryMementos(const MementoQuery()), hasLength(3));
      expect(store.characterReads, 1);

      store.characterReads = 0;
      expect(
        await service.queryMementos(const MementoQuery(keyword: 'STAY')),
        hasLength(3),
      );
      expect(store.characterReads, 1);
    },
  );
  test('avatar scan stops after a retained item accounts for it', () async {
    final store = CountingCollectionItemStore();
    final service = MementoService(
      storage: LocalStorageService(appDataDirectory: dir, jsonStore: store),
    );
    final source = File('${dir.path}/shared-avatar.png');
    await source.writeAsBytes([4, 5, 6]);
    final asset = await service.copyRecognizedAvatar(
      source.path,
      recognizedPaths: {source.path},
    );
    Future<MementoSnapshot> withAvatar(String key) {
      final base = draft(key);
      return service.createMemento(
        MementoDraft(
          idempotencyKey: base.idempotencyKey,
          title: base.title,
          characterId: base.characterId,
          characterNameSnapshot: base.characterNameSnapshot,
          sessionTitleSnapshot: base.sessionTitleSnapshot,
          sourceSessionId: base.sourceSessionId,
          entries: [
            MementoEntry.capture(
              sessionId: 's',
              messages: messages,
              index: 0,
              speakerName: 'Before',
              avatarAssetId: asset,
            ),
          ],
        ),
      );
    }

    final removed = await withAvatar('shared-removed');
    final shared = await withAvatar('shared-kept');
    final tail = await service.createMemento(draft('shared-tail'));
    final paths = await service.paths;
    store.itemReads.clear();

    await service.deleteMemento(removed.id);

    expect(store.itemReads[paths.item(shared.id).path], 1);
    expect(store.itemReads[paths.item(tail.id).path] ?? 0, 0);
    expect(await paths.item(removed.id).exists(), false);
    expect(await paths.media(asset!).readAsBytes(), [4, 5, 6]);
  });
  test(
    'index failure rolls back metadata instead of splitting list and detail',
    () async {
      final store = FailingCollectionIndexStore();
      final service = MementoService(
        storage: LocalStorageService(appDataDirectory: dir, jsonStore: store),
      );
      final saved = await service.createMemento(draft('rollback'));
      store.fail = true;
      await expectLater(
        service.updateMementoMetadata(
          MementoMetadataPatch(
            id: saved.id,
            title: 'Changed',
            tags: [],
            note: '',
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await service.loadMemento(saved.id)).title, 'Moment');
    },
  );
}
