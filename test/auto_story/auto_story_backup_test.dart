import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/services/auto_story/auto_story_store.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalStorageService storage;
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('auto-story-backup-');
    storage = LocalStorageService(
      appDataDirectory: Directory('${root.path}/app_data'),
    );
    await storage.appDataDirectory;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (call) async => null);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    await root.delete(recursive: true);
  });

  Future<void> write(String path, dynamic json) async {
    final file = File('${(await storage.appDataDirectory).path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
  }

  Map<String, dynamic> storyJson() => {
    'schemaVersion': 1,
    'id': 'story',
    'revision': 3,
    'runGeneration': 7,
    'status': 'running',
    'pauseAfterCurrent': false,
    'actors': [
      {
        'actorId': 'A',
        'sourceId': 'deleted-source',
        'name': 'A',
        'persona': 'Private A',
        'publicProfile': 'Public A',
        'avatarRelativePath': 'media/auto_stories/story/a.png',
        'endpointId': 'missing-endpoint',
        'model': 'model',
        'lockedSource': true,
      },
      {
        'actorId': 'B',
        'name': 'B',
        'persona': 'Private B',
        'publicProfile': 'Public B',
        'avatarRelativePath': null,
        'endpointId': 'missing-endpoint',
        'model': 'model',
        'lockedSource': false,
      },
    ],
    'config': {
      'title': 'Snapshot story',
      'opening': 'Rain',
      'targetEnding': 'Friends',
      'style': '',
      'plannedRounds': 10,
      'replyLengthPreset': 'standard',
      'interTurnDelayMs': 1000,
      'maxRequests': 34,
      'planVersion': 1,
    },
    'plan': <dynamic>[],
    'turns': <dynamic>[],
    'events': <dynamic>[],
    'directorCheckpoints': <dynamic>[],
    'nextActor': 'A',
    'completedRounds': 0,
    'goalStatus': 'pending',
    'worldBookSnapshots': <dynamic>[],
    'importedMemorySnapshots': <dynamic>[],
    'privacyRequired': true,
    'requestLedger': <dynamic>[],
    'usageTotals': <String, dynamic>{},
    'createdAt': '2026-09-21T00:00:00.000Z',
    'updatedAt': '2026-09-21T00:00:00.000Z',
    'futureField': {'preserved': true},
  };

  test('legacy backup without automatic stories remains valid', () async {
    await write('backup_manifest.json', {'format': 1, 'schemaVersion': 3});
    await validateBackupDirectory(await storage.appDataDirectory);
  });

  test(
    'failed restore invalidates incoming headers and pauses rolled back running story',
    () async {
      await write('auto_stories/story.json', storyJson());
      final backup = await storage.exportAllData();
      final original = storyJson();
      (original['config'] as Map)['title'] = 'Original current data';
      await write('auto_stories/story.json', original);
      await storage.autoStories.listStories();
      storage.backupFailureHook = (stage) async {
        if (stage == 'afterCredentials') throw StateError('Injected failure');
      };
      await expectLater(storage.importAllData(backup), throwsStateError);
      final header = (await storage.autoStories.listStories()).single;
      expect(header.title, 'Original current data');
      expect(header.status, StoryStatus.paused);
    },
  );

  test(
    'locking source invalidates the shared cached public story header',
    () async {
      final raw = storyJson()..['privacyRequired'] = false;
      ((raw['actors'] as List).first as Map)['lockedSource'] = false;
      await write('auto_stories/story.json', raw);
      expect(
        (await storage.autoStories.listStories()).single.privacyRequired,
        false,
      );
      await storage.saveCharacter(
        AppCharacter.fromJson({
          'id': 'deleted-source',
          'name': 'Source',
          'isLocked': true,
        }),
      );
      expect(
        (await storage.autoStories.listStories()).single.privacyRequired,
        true,
      );
      await storage.deleteCharacter('deleted-source');
      expect(
        (await storage.autoStories.listStories()).single.privacyRequired,
        true,
      );
    },
  );

  test(
    'startup recovers interrupted execution once without pausing a later run',
    () async {
      await write('auto_stories/story.json', storyJson());
      final stories = AutoStoryStore(storage);
      await storage.ensureReady();
      expect((await stories.loadStory('story')).status, StoryStatus.paused);
      await stories.beginRun('story');
      await storage.ensureReady();
      expect((await stories.loadStory('story')).status, StoryStatus.running);
    },
  );

  test(
    'import and rollback reject late commits from the previous dataset',
    () async {
      await write('auto_stories/story.json', storyJson());
      final stories = AutoStoryStore(storage);
      final token = await stories.reserveRequest(
        'story',
        RequestPurpose.actorA,
      );
      final backup = await storage.exportAllData();
      await storage.importAllData(backup);
      final turn = StoryTurn(
        turnId: 'late',
        ordinal: 0,
        speakerId: 'A',
        content: 'must not enter new dataset',
        requestId: token.requestId,
      );
      expect(await stories.commitTurn(token, turn), CommitResult.stale);
      final restored = await stories.loadStory('story');
      expect(restored.turns, isEmpty);
      expect(restored.requestLedger.single.status, 'unknown');
      await stories.beginRun('story');
      final second = await stories.reserveRequest(
        'story',
        RequestPurpose.actorA,
      );
      await storage.restorePreviousBackup();
      expect(
        await stories.commitTurn(
          second,
          turn.copyWith(requestId: second.requestId),
        ),
        CommitResult.stale,
      );
      expect((await stories.loadStory('story')).status, StoryStatus.paused);
    },
  );

  test(
    'backup refuses a malformed automatic story before activation',
    () async {
      await write('backup_manifest.json', {'format': 1, 'schemaVersion': 3});
      await write('auto_stories/story.json', {
        'schemaVersion': 99,
        'id': 'story',
      });
      await expectLater(
        validateBackupDirectory(await storage.appDataDirectory),
        throwsA(isA<StorageException>()),
      );
    },
  );

  test('backup rejects unrecognized files inside story namespace', () async {
    await write('backup_manifest.json', {'format': 1, 'schemaVersion': 3});
    await write('auto_stories/nested/story.json', <String, dynamic>{});
    await expectLater(
      validateBackupDirectory(await storage.appDataDirectory),
      throwsA(isA<StorageException>()),
    );
  });

  test('backup rejects inconsistent automatic story turn cursor', () async {
    await write('backup_manifest.json', {'format': 1, 'schemaVersion': 3});
    final data = storyJson()..['nextActor'] = 'B';
    await write('auto_stories/story.json', data);
    await expectLater(
      validateBackupDirectory(await storage.appDataDirectory),
      throwsA(isA<StorageException>()),
    );
  });

  test(
    'full backup preserves orphan actors, private media and unknown fields but pauses execution',
    () async {
      final directory = await storage.appDataDirectory;
      final media = File('${directory.path}/media/auto_stories/story/a.png');
      await media.parent.create(recursive: true);
      await media.writeAsBytes([11, 22, 33]);
      await write('auto_stories/story.json', storyJson());
      final target = LocalStorageService(
        appDataDirectory: Directory('${root.path}/target/app_data'),
      );
      final epoch = target.datasetEpoch;
      await target.importAllData(await storage.exportAllData());
      final targetDirectory = await target.appDataDirectory;
      final restored =
          jsonDecode(
                await File(
                  '${targetDirectory.path}/auto_stories/story.json',
                ).readAsString(),
              )
              as Map;
      expect(restored['status'], 'paused');
      expect(restored['pauseReason'], 'datasetChanged');
      expect(restored['runGeneration'], 8);
      expect(restored['privacyRequired'], true);
      expect(restored['futureField'], {'preserved': true});
      expect(
        ((restored['actors'] as List).first as Map)['sourceId'],
        'deleted-source',
      );
      expect(
        await File(
          '${targetDirectory.path}/media/auto_stories/story/a.png',
        ).readAsBytes(),
        [11, 22, 33],
      );
      expect(target.datasetEpoch, greaterThan(epoch));
      await target.cleanupUnusedMedia();
      expect(
        await File(
          '${targetDirectory.path}/media/auto_stories/story/a.png',
        ).exists(),
        true,
      );
    },
  );

  test('deleting a source keeps story-relative avatar copies', () async {
    final directory = await storage.appDataDirectory;
    final avatar = File('${directory.path}/media/auto_stories/story/a.png');
    await avatar.parent.create(recursive: true);
    await avatar.writeAsBytes([1, 2, 3]);
    await write('auto_stories/story.json', {
      'id': 'story',
      'actors': [
        {
          'sourceId': 'source',
          'avatarRelativePath': 'media/auto_stories/story/a.png',
        },
      ],
    });
    await storage.saveCharacter(
      AppCharacter.fromJson({'id': 'source', 'name': 'Source'}),
    );
    await storage.deleteCharacter('source');
    expect(await avatar.readAsBytes(), [1, 2, 3]);
  });

  test(
    'locking then deleting a source leaves its story privacy sticky',
    () async {
      await write('auto_stories/story.json', {
        'id': 'story',
        'privacyRequired': false,
        'actors': [
          {'actorId': 'A', 'sourceId': 'source', 'lockedSource': false},
        ],
      });
      await storage.saveCharacter(
        AppCharacter.fromJson({
          'id': 'source',
          'name': 'Source',
          'isLocked': true,
        }),
      );
      await storage.deleteCharacter('source');
      final data =
          jsonDecode(
                await File(
                  '${(await storage.appDataDirectory).path}/auto_stories/story.json',
                ).readAsString(),
              )
              as Map;
      expect(data['privacyRequired'], isTrue);
      expect(((data['actors'] as List).single as Map)['lockedSource'], isTrue);
    },
  );
}
