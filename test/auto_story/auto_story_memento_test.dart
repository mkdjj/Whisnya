import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart' as story;
import 'package:whisnya/models/memento.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/memento_service.dart';
import 'auto_story_model_test.dart' show storyFixture, turnFixture;

void main() {
  late Directory root;
  late LocalStorageService storage;
  late story.AutoStoryDocument document;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('auto-story-memento-');
    storage = LocalStorageService(appDataDirectory: root);
    document = storyFixture().copyWith(turns: [turnFixture(0), turnFixture(1)]);
    final file = File('${root.path}/auto_stories/story-1.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(document.toJson()));
  });
  tearDown(() => root.delete(recursive: true));

  MementoSnapshot draft({bool tampered = false}) => MementoSnapshot.fromJson({
    'schemaVersion': 1,
    'id': 'draft',
    'sourceType': 'autoStory',
    'idempotencyKey': 'submission',
    'title': 'Memory',
    'characterId': '',
    'characterNameSnapshot': 'Same',
    'sessionTitleSnapshot': 'Story',
    'sourceSessionId': 'story-1',
    'requiresUnlock': false,
    'tags': <String>[],
    'note': '',
    'createdAt': '2026-09-21T00:00:00.000Z',
    'updatedAt': '2026-09-21T00:00:00.000Z',
    'entries': [
      {
        'sourceMessageId': 'turn-1',
        'sourceVariantId': null,
        'sourcePrefixDigest': sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  {
                    'turnId': 'turn-0',
                    'speakerId': 'A',
                    'content': 'Hello 0',
                    'source': 'ai',
                  },
                  {
                    'turnId': 'turn-1',
                    'speakerId': 'B',
                    'content': 'Hello 1',
                    'source': 'ai',
                  },
                ]),
              ),
            )
            .toString(),
        'role': 'user',
        'speakerNameSnapshot': 'Same (AI)',
        'time': document.turns[1].createdAt.toIso8601String(),
        'contentSnapshot': tampered ? 'forged body' : 'Hello 1',
      },
    ],
  });

  test('story memento captures B as AI and survives deleted story', () async {
    final service = MementoService(storage: storage);
    final saved = await service.createMemento(draft());
    expect(saved.toJson()['sourceType'], 'autoStory');
    expect(saved.entries.single.speakerNameSnapshot, 'Same (AI)');
    expect(
      await service.locateMementoSource(saved.id, 0),
      SourceNavigationResult.found,
    );
    await File('${root.path}/auto_stories/story-1.json').delete();
    expect(
      (await service.loadMemento(saved.id)).entries.single.contentSnapshot,
      'Hello 1',
    );
    expect(
      await service.locateMementoSource(saved.id, 0),
      SourceNavigationResult.sourceMissing,
    );
    await validateMementoBackup(root);
  });

  test('story memento rejects forged visible content', () async {
    await expectLater(
      MementoService(storage: storage).createMemento(draft(tampered: true)),
      throwsStateError,
    );
  });

  test(
    'story memento requires actual story privacy even when draft omits it',
    () async {
      document = document.copyWith(privacyRequired: true);
      await File(
        '${root.path}/auto_stories/story-1.json',
      ).writeAsString(jsonEncode(document.toJson()));
      await expectLater(
        MementoService(storage: storage).createMemento(draft()),
        throwsStateError,
      );
      final saved = await MementoService(
        storage: storage,
        authorize: (_, locked) async => locked,
      ).createMemento(draft());
      expect(saved.requiresUnlock, true);
      await expectLater(
        MementoService(storage: storage).loadMemento(saved.id),
        throwsStateError,
      );
    },
  );
}
