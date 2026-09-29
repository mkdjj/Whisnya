import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/services/auto_story/auto_story_store.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';
import 'auto_story_model_test.dart' show storyFixture, turnFixture;

class FailingStoryJsonStore extends JsonFileStore {
  bool failStory = false;
  bool failIndex = false;
  final Set<String> storyLockPaths = {};
  @override
  Future<T> synchronized<T>(File file, FutureOr<T> Function() action) {
    if (file.path.contains('story-1.json')) storyLockPaths.add(file.path);
    return super.synchronized(file, action);
  }

  @override
  Future<void> writeNow(File file, dynamic data, {bool compact = false}) {
    if ((failStory && file.path.contains('auto_stories')) ||
        (failIndex && file.path.endsWith('auto_story_index.json'))) {
      throw const FileSystemException('injected failure');
    }
    return super.writeNow(file, data, compact: compact);
  }
}

void main() {
  late Directory dir;
  late FailingStoryJsonStore json;
  late AutoStoryStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('auto-story-test-');
    json = FailingStoryJsonStore();
    store = AutoStoryStore(
      LocalStorageService(appDataDirectory: dir, jsonStore: json),
    );
    await store.createStory(storyFixture());
    await store.mutateStory(
      'story-1',
      (d) => d.copyWith(status: StoryStatus.ready),
    );
    await store.beginRun('story-1');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<StoryFact> prepareVerifiedFact() async {
    final a = await store.reserveRequest('story-1', RequestPurpose.actorA);
    await store.commitTurn(a, turnFixture(0, requestId: a.requestId));
    final b = await store.reserveRequest('story-1', RequestPurpose.actorB);
    await store.commitTurn(b, turnFixture(1, requestId: b.requestId));
    final doc = await store.loadStory('story-1');
    final fact = StoryFact(
      text: 'A greeted B',
      evidenceTurnIds: ['turn-0'],
      evidence: [StoryEvidence(turnId: 'turn-0', quote: 'Hello 0')],
    );
    final review = await store.reserveRequest('story-1', RequestPurpose.review);
    await store.commitDirector(
      review,
      DirectorResult(
        checkpoint: DirectorCheckpoint(
          checkpointId: 'pin-fence',
          coveredThroughOrdinal: 1,
          coveredTurnIdsHash: storyTurnsHash(doc.turns),
          planVersion: doc.config.planVersion,
          confirmedFacts: [fact],
        ),
      ),
    );
    await store.stopImmediately('story-1', StoryPauseReason.userStop);
    return fact;
  }

  test(
    'fact pin rejects a paused pending regeneration without changing data',
    () async {
      final fact = await prepareVerifiedFact();
      await store.reserveRequest(
        'story-1',
        RequestPurpose.regenerate,
        replaceLast: true,
      );
      final before = await store.loadStory('story-1');
      await expectLater(
        store.setFactPinned('story-1', fact, pinned: true),
        throwsStateError,
      );
      final after = await store.loadStory('story-1');
      expect(after.toJson(), before.toJson());
    },
  );

  test(
    'fact pin changes fence old prompt generations but repeated state is a no-op',
    () async {
      final fact = await prepareVerifiedFact();
      final before = await store.loadStory('story-1');
      final pinned = await store.setFactPinned('story-1', fact, pinned: true);
      expect(pinned.runGeneration, before.runGeneration + 1);
      expect(pinned.lockedFacts.single.text, 'A greeted B');
      final pinnedAgain = await store.setFactPinned(
        'story-1',
        fact,
        pinned: true,
      );
      expect(pinnedAgain.runGeneration, pinned.runGeneration);
      final unpinned = await store.setFactPinned(
        'story-1',
        fact,
        pinned: false,
      );
      expect(unpinned.runGeneration, pinned.runGeneration + 1);
      expect(unpinned.lockedFacts, isEmpty);
      final unpinnedAgain = await store.setFactPinned(
        'story-1',
        fact,
        pinned: false,
      );
      expect(unpinnedAgain.runGeneration, unpinned.runGeneration);
    },
  );

  test(
    'replacement after future outline edit cannot rewind before its saved stage boundary',
    () async {
      final a = await store.reserveRequest('story-1', RequestPurpose.actorA);
      await store.commitTurn(a, turnFixture(0, requestId: a.requestId));
      final b = await store.reserveRequest('story-1', RequestPurpose.actorB);
      await store.commitTurn(b, turnFixture(1, requestId: b.requestId));
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      await store.mutateStory(
        'story-1',
        (d) => AutoStoryDocument.fromJson({
          ...d
              .copyWith(
                plan: List.generate(
                  3,
                  (i) => StoryStage(
                    id: 'stage-$i',
                    title: 'Stage',
                    objective: 'Objective',
                    minRounds: 1,
                    targetRounds: i == 0 ? 4 : 3,
                    acceptanceCriteria: ['Evidence'],
                  ),
                ),
              )
              .toJson(),
          'replanStageIndex': 2,
        }),
      );
      final edit = await store.loadStory('story-1');
      expect(edit.stageIndex, 2);
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.regenerate,
        replaceLast: true,
      );
      await store.commitTurn(
        token,
        StoryTurn(
          turnId: 'new-at-boundary',
          ordinal: 1,
          speakerId: 'B',
          content: 'replacement',
          requestId: token.requestId,
          replacesTurnId: 'turn-1',
        ),
      );
      final replaced = await store.loadStory('story-1');
      expect(replaced.currentCheckpoint, isNull);
      expect(replaced.stageIndex, 2);
      expect(replaced.replanStageIndex, 2);
    },
  );
  test(
    'metadata rename keeps generation and the current facts checkpoint',
    () async {
      final before = await store.loadStory('story-1');
      final renamed = await store.mutateStory(
        'story-1',
        (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Renamed')),
      );
      expect(renamed.config.title, 'Renamed');
      expect(renamed.config.planVersion, before.config.planVersion);
      expect(renamed.runGeneration, before.runGeneration);
      expect(renamed.status, StoryStatus.running);
    },
  );
  test(
    'editor replan preserves historical scenes and body but replacement invalidates fallback facts',
    () async {
      final a = await store.reserveRequest('story-1', RequestPurpose.actorA);
      await store.commitTurn(a, turnFixture(0, requestId: a.requestId));
      final b = await store.reserveRequest('story-1', RequestPurpose.actorB);
      await store.commitTurn(b, turnFixture(1, requestId: b.requestId));
      final doc = await store.loadStory('story-1');
      final cp = DirectorCheckpoint(
        checkpointId: 'old',
        coveredThroughOrdinal: 1,
        coveredTurnIdsHash: storyTurnsHash(doc.turns),
        planVersion: doc.config.planVersion,
        summary: 'Original event',
      );
      final review = await store.reserveRequest(
        'story-1',
        RequestPurpose.review,
      );
      await store.commitDirector(
        review,
        DirectorResult(
          checkpoint: cp,
          events: [
            StoryEvent(
              eventId: 'scene',
              kind: 'sceneTransition',
              effectiveAfterOrdinal: 1,
              content: 'Next morning',
              sourceCheckpointId: 'old',
            ),
          ],
        ),
      );
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      final edited = await store.mutateStory('story-1', (latest) {
        final changed = latest.copyWith(
          config: latest.config.copyWith(
            targetEnding: 'New ending',
            planVersion: latest.config.planVersion + 1,
          ),
          plan: [],
          clearCurrentCheckpoint: true,
        );
        return AutoStoryDocument.fromJson({
          ...changed.toJson(),
          'replanSummary': latest.currentCheckpoint!.summary,
          'replanCoveredThroughOrdinal': 1,
          'replanStartRound': 1,
        });
      });
      expect(edited.turns.map((t) => t.content).toList(), [
        'Hello 0',
        'Hello 1',
      ]);
      expect(edited.events.single.content, 'Next morning');
      expect(edited.directorCheckpoints.single.summary, 'Original event');
      expect(edited.currentCheckpoint, isNull);
      expect(
        (await store.loadStory('story-1')).toJson()['replanStartRound'],
        1,
      );
      final replacement = await store.reserveRequest(
        'story-1',
        RequestPurpose.regenerate,
        replaceLast: true,
      );
      await store.commitTurn(
        replacement,
        StoryTurn(
          turnId: 'changed',
          ordinal: 1,
          speakerId: 'B',
          content: 'Different event',
          requestId: replacement.requestId,
          replacesTurnId: 'turn-1',
        ),
      );
      final finalDoc = await store.loadStory('story-1');
      expect(finalDoc.toJson()['replanSummary'], '');
      expect(finalDoc.toJson()['replanCoveredThroughOrdinal'], -1);
      expect(finalDoc.events, isEmpty);
      expect(finalDoc.toJson()['replanStartRound'], 1);
    },
  );
  test('privacy requirement cannot be downgraded through an edit', () async {
    await store.stopImmediately('story-1', StoryPauseReason.userStop);
    await store.mutateStory(
      'story-1',
      (d) => d.copyWith(privacyRequired: true),
    );
    final edited = await store.mutateStory(
      'story-1',
      (d) => d.copyWith(privacyRequired: false),
    );
    expect(edited.privacyRequired, true);
    expect((await store.listStories()).single.privacyRequired, true);
  });
  test(
    'replacement may reuse old factual summary but not old plan stage cursor',
    () async {
      final a = await store.reserveRequest('story-1', RequestPurpose.actorA);
      await store.commitTurn(a, turnFixture(0, requestId: a.requestId));
      final b = await store.reserveRequest('story-1', RequestPurpose.actorB);
      await store.commitTurn(b, turnFixture(1, requestId: b.requestId));
      final doc = await store.loadStory('story-1');
      final review = await store.reserveRequest(
        'story-1',
        RequestPurpose.review,
      );
      final cp = DirectorCheckpoint(
        checkpointId: 'earlier',
        coveredThroughOrdinal: 0,
        coveredTurnIdsHash: storyTurnsHash(doc.turns.take(1).toList()),
        planVersion: doc.config.planVersion,
        summary: 'A spoke',
      );
      await store.commitDirector(review, DirectorResult(checkpoint: cp));
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      await store.mutateStory(
        'story-1',
        (d) => d.copyWith(
          config: d.config.copyWith(targetEnding: 'New goal'),
          clearCurrentCheckpoint: true,
        ),
      );
      final replacement = await store.reserveRequest(
        'story-1',
        RequestPurpose.regenerate,
        replaceLast: true,
      );
      await store.commitTurn(
        replacement,
        StoryTurn(
          turnId: 'new-b',
          ordinal: 1,
          speakerId: 'B',
          content: 'Changed',
          requestId: replacement.requestId,
          replacesTurnId: 'turn-1',
        ),
      );
      final replaced = await store.loadStory('story-1');
      expect(replaced.directorCheckpoints.single.summary, 'A spoke');
      expect(replaced.currentCheckpoint, isNull);
    },
  );
  test(
    'provider total-only usage enforces token budget without inventing breakdown',
    () async {
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      await store.mutateStory(
        'story-1',
        (d) => d.copyWith(config: d.config.copyWith(tokenLimit: 25)),
      );
      await store.beginRun('story-1');
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.actorA,
      );
      await store.recordUsage(token, totalTokens: 30);
      await store.recordUsage(token, totalTokens: 30);
      await store.finishFailedAttempt(token);
      final doc = await store.loadStory('story-1');
      expect(doc.usageTotals.totalTokens, 30);
      expect(doc.usageTotals.hasUnknown, false);
      expect(doc.requestLedger.single.inputTokens, isNull);
      expect(doc.requestLedger.single.outputTokens, isNull);
      await expectLater(
        store.reserveRequest('story-1', RequestPurpose.repair),
        throwsA(
          isA<StoryBudgetException>().having(
            (e) => e.reason,
            'reason',
            StoryPauseReason.tokenLimit,
          ),
        ),
      );
    },
  );
  test(
    'verified fact pin survives reviews, rejects invention and invalidates replaced evidence',
    () async {
      final a = await store.reserveRequest('story-1', RequestPurpose.actorA);
      await store.commitTurn(a, turnFixture(0, requestId: a.requestId));
      final b = await store.reserveRequest('story-1', RequestPurpose.actorB);
      await store.commitTurn(b, turnFixture(1, requestId: b.requestId));
      var doc = await store.loadStory('story-1');
      final fact = StoryFact(
        text: 'B greeted A',
        evidenceTurnIds: ['turn-1'],
        evidence: [StoryEvidence(turnId: 'turn-1', quote: 'Hello 1')],
      );
      final cp = DirectorCheckpoint(
        checkpointId: 'facts',
        coveredThroughOrdinal: 1,
        coveredTurnIdsHash: storyTurnsHash(doc.turns),
        planVersion: doc.config.planVersion,
        confirmedFacts: [fact],
      );
      final review = await store.reserveRequest(
        'story-1',
        RequestPurpose.review,
      );
      await store.commitDirector(review, DirectorResult(checkpoint: cp));
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      doc = await store.setFactPinned('story-1', fact, pinned: true);
      expect(doc.lockedFacts.single.text, 'B greeted A');
      await expectLater(
        store.setFactPinned(
          'story-1',
          StoryFact(
            text: 'Invented marriage',
            evidenceTurnIds: ['turn-1'],
            evidence: [StoryEvidence(turnId: 'turn-1', quote: 'Hello 1')],
          ),
          pinned: true,
        ),
        throwsStateError,
      );
      await store.beginRun('story-1');
      final review2 = await store.reserveRequest(
        'story-1',
        RequestPurpose.review,
      );
      await store.commitDirector(
        review2,
        DirectorResult(
          checkpoint: DirectorCheckpoint(
            checkpointId: 'forgotten',
            coveredThroughOrdinal: 1,
            coveredTurnIdsHash: storyTurnsHash(doc.turns),
            planVersion: doc.config.planVersion,
          ),
        ),
      );
      expect(
        (await store.loadStory('story-1')).lockedFacts.single.text,
        'B greeted A',
      );
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      final unpinned = await store.setFactPinned(
        'story-1',
        fact,
        pinned: false,
      );
      expect(unpinned.lockedFacts, isEmpty);
      // Restore a valid old fact checkpoint and pin it again before replacement.
      await store.mutateStory(
        'story-1',
        (d) => d.copyWith(currentCheckpointId: 'facts'),
      );
      await store.setFactPinned('story-1', fact, pinned: true);
      final replacement = await store.reserveRequest(
        'story-1',
        RequestPurpose.regenerate,
        replaceLast: true,
      );
      await store.commitTurn(
        replacement,
        StoryTurn(
          turnId: 'new-evidence',
          ordinal: 1,
          speakerId: 'B',
          content: 'No greeting',
          requestId: replacement.requestId,
          replacesTurnId: 'turn-1',
        ),
      );
      expect((await store.loadStory('story-1')).lockedFacts, isEmpty);
    },
  );
  test(
    'same request commits once and soft pause preserves A half turn',
    () async {
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.actorA,
      );
      await store.requestPause('story-1');
      expect(
        await store.commitTurn(
          token,
          turnFixture(0, requestId: token.requestId),
        ),
        CommitResult.applied,
      );
      expect(
        await store.commitTurn(
          token,
          turnFixture(0, requestId: token.requestId),
        ),
        CommitResult.alreadyCommitted,
      );
      final doc = await store.loadStory('story-1');
      expect(doc.turns.length, 1);
      expect(doc.nextActor, 'B');
      expect(doc.status, StoryStatus.paused);
    },
  );
  test('deleted story cannot be resurrected by late commit', () async {
    final token = await store.reserveRequest('story-1', RequestPurpose.actorA);
    await store.deleteStory('story-1');
    expect(
      await store.commitTurn(token, turnFixture(0, requestId: token.requestId)),
      CommitResult.missing,
    );
    expect(await File('${dir.path}/auto_stories/story-1.json').exists(), false);
  });
  test(
    'body write failure preserves body and cursor; index failure does not undo commit',
    () async {
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.actorA,
      );
      json.failStory = true;
      await expectLater(
        store.commitTurn(token, turnFixture(0, requestId: token.requestId)),
        throwsA(isA<StoryStorageException>()),
      );
      expect((await store.loadStory('story-1')).nextActor, 'A');
      json.failStory = false;
      json.failIndex = true;
      expect(
        await store.commitTurn(
          token,
          turnFixture(0, requestId: token.requestId),
        ),
        CommitResult.applied,
      );
      expect((await store.listStories()).single.completedRounds, 0);
      expect((await store.loadStory('story-1')).nextActor, 'B');
    },
  );
  test('generation and dataset fences reject old writes', () async {
    final token = await store.reserveRequest('story-1', RequestPurpose.actorA);
    await store.stopImmediately('story-1', StoryPauseReason.userStop);
    expect(
      await store.commitTurn(token, turnFixture(0, requestId: token.requestId)),
      CommitResult.stale,
    );
    await store.beginRun('story-1');
    final newer = await store.reserveRequest('story-1', RequestPurpose.actorA);
    await json.maintain(() {}, advanceEpoch: true);
    expect(
      await store.commitTurn(newer, turnFixture(0, requestId: newer.requestId)),
      CommitResult.stale,
    );
  });
  test('duplicate reservation and usage callbacks are idempotent', () async {
    final token = await store.reserveRequest(
      'story-1',
      RequestPurpose.actorA,
      requestId: 'request-same',
    );
    await store.reserveRequest(
      'story-1',
      RequestPurpose.actorA,
      requestId: 'request-same',
    );
    await store.recordUsage(token, inputTokens: 11, outputTokens: 7);
    await store.recordUsage(token, inputTokens: 11, outputTokens: 7);
    final doc = await store.loadStory('story-1');
    expect(doc.requestLedger.length, 1);
    expect(doc.usageTotals.totalTokens, 18);
  });
  test(
    'ordinary load never pauses live run; explicit recovery does once',
    () async {
      expect((await store.loadStory('story-1')).status, StoryStatus.running);
      await store.recoverInterruptedStories();
      expect(
        (await store.loadStory('story-1')).pauseReason,
        StoryPauseReason.interruptedRestart,
      );
      await store.beginRun('story-1');
      await store.recoverInterruptedStories();
      expect((await store.loadStory('story-1')).status, StoryStatus.running);
    },
  );
  test('manual B only at B cursor and no request charged', () async {
    await store.stopImmediately('story-1', StoryPauseReason.userStop);
    await expectLater(
      store.addManualTurn('story-1', 'manual'),
      throwsStateError,
    );
    await store.beginRun('story-1');
    final token = await store.reserveRequest('story-1', RequestPurpose.actorA);
    await store.commitTurn(token, turnFixture(0, requestId: token.requestId));
    await store.stopImmediately('story-1', StoryPauseReason.userStop);
    final doc = await store.addManualTurn('story-1', 'manual');
    expect(doc.completedRounds, 1);
    expect(doc.turns.last.source, StoryTurnSource.manual);
    expect(doc.requestLedger.length, 1);
  });
  test('known zero usage is known rather than missing', () async {
    final token = await store.reserveRequest('story-1', RequestPurpose.actorA);
    await store.recordUsage(token, inputTokens: 0, outputTokens: 0);
    final doc = await store.loadStory('story-1');
    expect(doc.usageTotals.hasUnknown, false);
    expect(doc.usageTotals.totalTokens, 0);
  });
  test('budget counts failure and refuses extra repair requests', () async {
    await store.stopImmediately('story-1', StoryPauseReason.userStop);
    await store.mutateStory(
      'story-1',
      (d) => d.copyWith(config: d.config.copyWith(maxRequests: 1)),
    );
    await store.beginRun('story-1');
    final token = await store.reserveRequest('story-1', RequestPurpose.actorA);
    await store.failRequest(token, errorCode: 'network');
    await expectLater(
      store.reserveRequest('story-1', RequestPurpose.repair),
      throwsA(
        isA<StoryBudgetException>().having(
          (e) => e.reason,
          'reason',
          StoryPauseReason.requestLimit,
        ),
      ),
    );
    expect(
      (await store.loadStory('story-1')).requestLedger.single.status,
      'failed',
    );
  });
  test(
    'revision gate prevents lost edits and config edits fence reserved plan',
    () async {
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      final prior = await store.loadStory('story-1');
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.replan,
      );
      await store.mutateStory(
        'story-1',
        (d) => d.copyWith(config: d.config.copyWith(targetEnding: 'different')),
      );
      expect(
        await store.commitDirector(token, DirectorResult()),
        CommitResult.stale,
      );
      await expectLater(
        store.mutateStory(
          'story-1',
          (d) => d.copyWith(config: d.config.copyWith(title: 'lost update')),
          expectedRevision: prior.revision,
        ),
        throwsStateError,
      );
      expect(
        (await store.loadStory('story-1')).config.targetEnding,
        'different',
      );
    },
  );
  test(
    'replacement failure preserves original and success invalidates dependent checkpoints',
    () async {
      final a = await store.reserveRequest('story-1', RequestPurpose.actorA);
      await store.commitTurn(a, turnFixture(0, requestId: a.requestId));
      final b = await store.reserveRequest('story-1', RequestPurpose.actorB);
      await store.commitTurn(b, turnFixture(1, requestId: b.requestId));
      final doc = await store.loadStory('story-1');
      final review = await store.reserveRequest(
        'story-1',
        RequestPurpose.review,
      );
      final checkpoint = DirectorCheckpoint(
        checkpointId: 'dependent',
        coveredThroughOrdinal: 1,
        coveredTurnIdsHash: storyTurnsHash(doc.turns),
        planVersion: doc.config.planVersion,
      );
      await store.commitDirector(
        review,
        DirectorResult(
          checkpoint: checkpoint,
          events: [
            StoryEvent(
              eventId: 'scene',
              kind: 'sceneTransition',
              effectiveAfterOrdinal: 1,
              content: 'Later',
              sourceCheckpointId: 'dependent',
            ),
          ],
        ),
      );
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      final replacement = await store.reserveRequest(
        'story-1',
        RequestPurpose.regenerate,
        replaceLast: true,
      );
      final newTurn = StoryTurn(
        turnId: 'replacement',
        ordinal: 1,
        speakerId: 'B',
        content: 'Changed',
        requestId: replacement.requestId,
        replacesTurnId: 'turn-1',
      );
      json.failStory = true;
      await expectLater(
        store.commitTurn(replacement, newTurn),
        throwsA(isA<StoryStorageException>()),
      );
      final retained = await store.loadStory('story-1');
      expect(retained.turns.last.content, 'Hello 1');
      expect(retained.currentCheckpointId, 'dependent');
      json.failStory = false;
      expect(
        await store.commitTurn(replacement, newTurn),
        CommitResult.applied,
      );
      final changed = await store.loadStory('story-1');
      expect(changed.turns.last.ordinal, 1);
      expect(changed.turns.last.content, 'Changed');
      expect(changed.directorCheckpoints, isEmpty);
      expect(changed.events, isEmpty);
      expect(changed.completedRounds, 1);
    },
  );
  test('new store rebuilds index after index write failure', () async {
    final token = await store.reserveRequest('story-1', RequestPurpose.actorA);
    json.failIndex = true;
    expect(
      await store.commitTurn(token, turnFixture(0, requestId: token.requestId)),
      CommitResult.applied,
    );
    expect(store.indexNeedsRepair, true);
    json.failIndex = false;
    final fresh = AutoStoryStore(
      LocalStorageService(appDataDirectory: dir, jsonStore: json),
    );
    expect((await fresh.listStories()).single.id, 'story-1');
    expect((await fresh.loadStory('story-1')).nextActor, 'B');
  });
  test(
    'failed format attempt preserves running for one budgeted repair',
    () async {
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.actorA,
      );
      await store.finishFailedAttempt(token, errorCode: 'format');
      final doc = await store.loadStory('story-1');
      expect(doc.status, StoryStatus.running);
      expect(doc.requestLedger.single.status, 'failed');
      final repair = await store.reserveRequest(
        'story-1',
        RequestPurpose.repair,
      );
      expect(repair.expectedNextOrdinal, 0);
      expect((await store.loadStory('story-1')).requestLedger.length, 2);
    },
  );
  test(
    'pending-save pause retries same body without another charged request',
    () async {
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.actorA,
      );
      await store.pauseForPendingSave(token);
      expect(
        (await store.loadStory('story-1')).pauseReason,
        StoryPauseReason.storageError,
      );
      expect(
        await store.commitTurn(
          token,
          turnFixture(0, requestId: token.requestId),
        ),
        CommitResult.applied,
      );
      final doc = await store.loadStory('story-1');
      expect(doc.status, StoryStatus.paused);
      expect(doc.nextActor, 'B');
      expect(doc.requestLedger.length, 1);
    },
  );
  test(
    'startup finds interrupted atomic backup and preserves corrupt evidence visibly',
    () async {
      final main = File('${dir.path}/auto_stories/story-1.json');
      await main.rename('${main.path}.bak');
      final fresh = AutoStoryStore(
        LocalStorageService(appDataDirectory: dir, jsonStore: json),
      );
      await fresh.recoverInterruptedStories();
      expect((await fresh.listStories()).single.id, 'story-1');
      expect((await fresh.loadStory('story-1')).status, StoryStatus.paused);
      final damaged = File('${dir.path}/auto_stories/damaged.json');
      await json.write(damaged, {'schemaVersion': 999, 'id': 'damaged'});
      await fresh.repairIndex();
      expect(fresh.unreadableStories.keys, contains('damaged'));
      expect(await damaged.exists(), true);
    },
  );
  test(
    'two store instances cannot reserve concurrent calls for one story',
    () async {
      final second = AutoStoryStore(
        LocalStorageService(appDataDirectory: dir, jsonStore: json),
      );
      final results = await Future.wait([
        store
            .reserveRequest('story-1', RequestPurpose.actorA)
            .then<Object>((v) => v, onError: (Object e) => e),
        second
            .reserveRequest('story-1', RequestPurpose.actorA)
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<StoryOperationToken>().length, 1);
      expect(results.whereType<StateError>().length, 1);
      expect((await store.loadStory('story-1')).usageTotals.attempts, 1);
    },
  );
  test('repair and commits share exactly the same native path lock', () async {
    await store.repairIndex();
    await store.loadStory('story-1');
    expect(json.storyLockPaths.length, 1);
  });
  test(
    'editing manual B replaces identity without spending requests',
    () async {
      final token = await store.reserveRequest(
        'story-1',
        RequestPurpose.actorA,
      );
      await store.commitTurn(token, turnFixture(0, requestId: token.requestId));
      await store.stopImmediately('story-1', StoryPauseReason.userStop);
      final original = await store.addManualTurn('story-1', 'Original');
      final edited = await store.editLastManualTurn('story-1', 'Edited');
      expect(edited.turns.last.content, 'Edited');
      expect(edited.turns.last.ordinal, 1);
      expect(edited.turns.last.replacesTurnId, original.turns.last.turnId);
      expect(edited.turns.last.turnId, isNot(original.turns.last.turnId));
      expect(edited.requestLedger.length, 1);
      expect(edited.turns.last.source, StoryTurnSource.manual);
    },
  );
  for (final manual in [false, true]) {
    test(
      'last-turn replacement preserves earlier evidence (manual=$manual)',
      () async {
        final turns = List.generate(
          4,
          (i) => StoryTurn.fromJson({
            ...turnFixture(i).toJson(),
            if (manual && i == 3) 'source': 'manual',
          }),
        );
        StoryFact fact(int ordinal) => StoryFact(
          text: 'Fact $ordinal',
          evidenceTurnIds: ['turn-$ordinal'],
          evidence: [
            StoryEvidence(turnId: 'turn-$ordinal', quote: 'Hello $ordinal'),
          ],
        );
        final earlier = fact(0), replaced = fact(3);
        await store.mutateStory(
          'story-1',
          (doc) => AutoStoryDocument.fromJson({
            ...doc
                .copyWith(
                  status: StoryStatus.paused,
                  turns: turns,
                  directorCheckpoints: [
                    for (final ordinal in [1, 3])
                      DirectorCheckpoint(
                        checkpointId: 'cp-$ordinal',
                        coveredThroughOrdinal: ordinal,
                        coveredTurnIdsHash: storyTurnsHash(
                          turns.take(ordinal + 1).toList(),
                        ),
                        planVersion: 1,
                        summary: 'Summary $ordinal',
                        confirmedFacts: [ordinal == 1 ? earlier : replaced],
                      ),
                  ],
                  currentCheckpointId: 'cp-3',
                  lockedFacts: [earlier, replaced],
                  events: [
                    for (final ordinal in [1, 3])
                      StoryEvent(
                        eventId: 'scene-$ordinal',
                        kind: 'sceneTransition',
                        effectiveAfterOrdinal: ordinal,
                        content: 'Scene $ordinal',
                        sourceCheckpointId: 'cp-$ordinal',
                        status: 'applied',
                      ),
                    StoryEvent(
                      eventId: 'instruction',
                      kind: 'directorInstruction',
                      effectiveAfterOrdinal: 3,
                      content: 'Keep the pace',
                    ),
                  ],
                )
                .toJson(),
            'replanSummary': 'Summary 3',
            'replanCoveredThroughOrdinal': 3,
          }),
        );
        final before = await store.loadStory('story-1');
        if (manual) {
          await store.editLastManualTurn('story-1', 'Changed');
        } else {
          final token = await store.reserveRequest(
            'story-1',
            RequestPurpose.regenerate,
            replaceLast: true,
          );
          await store.commitTurn(
            token,
            StoryTurn(
              turnId: 'replacement',
              ordinal: 3,
              speakerId: 'B',
              content: 'Changed',
              requestId: token.requestId,
              replacesTurnId: 'turn-3',
            ),
          );
        }
        final after = await store.loadStory('story-1');
        expect(after.turns.map((t) => t.content), [
          'Hello 0',
          'Hello 1',
          'Hello 2',
          'Changed',
        ]);
        expect(after.turns.last.replacesTurnId, 'turn-3');
        expect(
          after.turns.last.source,
          manual ? StoryTurnSource.manual : StoryTurnSource.ai,
        );
        expect(after.currentCheckpointId, 'cp-1');
        expect(after.directorCheckpoints.map((c) => c.checkpointId), ['cp-1']);
        expect(after.lockedFacts.map((f) => f.text), ['Fact 0']);
        expect(after.events.map((e) => e.eventId), ['scene-1', 'instruction']);
        expect(after.replanSummary, 'Summary 1');
        expect(after.replanCoveredThroughOrdinal, 1);
        expect(after.status, StoryStatus.paused);
        expect(after.goalStatus, 'pending');
        expect(after.runGeneration, before.runGeneration + 1);
        expect(after.usageTotals.attempts, manual ? 0 : 1);
      },
    );
  }
}
