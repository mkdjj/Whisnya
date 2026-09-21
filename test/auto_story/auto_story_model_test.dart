import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';

AutoStoryDocument storyFixture({String id = 'story-1'}) => AutoStoryDocument(
  id: id,
  actors: [
    StoryActorSnapshot(
      actorId: 'A',
      name: 'Same',
      persona: 'private A',
      publicProfile: 'public A',
      endpointId: 'endpoint',
      model: 'model',
    ),
    StoryActorSnapshot(
      actorId: 'B',
      name: 'Same',
      persona: 'private B',
      publicProfile: 'public B',
      endpointId: 'endpoint',
      model: 'model',
    ),
  ],
  config: StoryConfig(
    title: 'Story',
    opening: 'Rain',
    targetEnding: 'Friends',
    plannedRounds: 10,
  ),
);

StoryTurn turnFixture(int ordinal, {String? requestId}) => StoryTurn(
  turnId: 'turn-$ordinal',
  ordinal: ordinal,
  speakerId: ordinal.isEven ? 'A' : 'B',
  content: 'Hello $ordinal',
  requestId: requestId,
);

void main() {
  test(
    'future outline edits retain their stage cursor without a new checkpoint',
    () {
      final base = storyFixture().copyWith(
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
      );
      final edited = AutoStoryDocument.fromJson({
        ...base.toJson(),
        'replanStageIndex': 2,
      });
      expect(edited.stageIndex, 2);
      expect(edited.replanStageIndex, 2);
      expect(
        () => AutoStoryDocument.fromJson({
          ...base.toJson(),
          'replanStageIndex': 3,
        }),
        throwsFormatException,
      );
      expect(
        () => AutoStoryDocument.fromJson({
          ...base.toJson(),
          'replanStageIndex': -1,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'replan metadata cannot claim future coverage or an unbounded summary',
    () {
      final raw = storyFixture().toJson();
      for (final patch in <Map<String, dynamic>>[
        {'replanStartRound': 1},
        {'replanCoveredThroughOrdinal': 0},
        {'replanSummary': 'x' * 4001},
        {'replanStartRound': '0'},
      ]) {
        expect(
          () => AutoStoryDocument.fromJson({...raw, ...patch}),
          throwsFormatException,
        );
      }
    },
  );
  test('actor media belongs to this story rather than another story', () {
    final base = storyFixture();
    expect(
      () => base.copyWith(
        actors: [
          base.actors.first.copyWith(
            avatarRelativePath: 'media/auto_stories/other/A.png',
          ),
          base.actors.last,
        ],
      ),
      throwsFormatException,
    );
  });
  test(
    'half-round replan excludes the old A turn from the new stage minimum',
    () {
      final raw = storyFixture().copyWith(turns: [turnFixture(0)]).toJson();
      final replan = AutoStoryDocument.fromJson({
        ...raw,
        'replanStartRound': 1,
      });
      expect(replan.replanStartRound, 1);
      expect(replan.completedRounds, 0);
      expect(replan.nextActor, 'B');
    },
  );
  test('half round resumes B, full round resumes A', () {
    final half = storyFixture().copyWith(turns: [turnFixture(0)]);
    expect(half.completedRounds, 0);
    expect(half.nextActor, 'B');
    final full = AutoStoryDocument.fromJson(
      half.copyWith(turns: [turnFixture(0), turnFixture(1)]).toJson(),
    );
    expect(full.completedRounds, 1);
    expect(full.nextActor, 'A');
  });
  test(
    'rejects cursor corruption, duplicate identity and invalid ordering',
    () {
      final raw = storyFixture().toJson();
      final rawActors = raw['actors'] as List<dynamic>;
      expect(
        () => AutoStoryDocument.fromJson({...raw, 'nextActor': 'B'}),
        throwsFormatException,
      );
      expect(
        () => AutoStoryDocument.fromJson({
          ...raw,
          'actors': [rawActors[0], rawActors[0]],
        }),
        throwsFormatException,
      );
      expect(
        () => storyFixture().copyWith(turns: [turnFixture(1)]),
        throwsFormatException,
      );
    },
  );
  test('unknown nested fields round trip and collections are immutable', () {
    final raw = storyFixture().toJson();
    raw['future'] = {
      'nested': [1, 2],
    };
    (raw['config'] as Map<String, dynamic>)['futureConfig'] = 'preserved';
    final doc = AutoStoryDocument.fromJson(raw);
    ((raw['future'] as Map<String, dynamic>)['nested'] as List<int>).add(3);
    expect((doc.toJson()['future'] as Map<String, dynamic>)['nested'], [1, 2]);
    expect(doc.config.toJson()['futureConfig'], 'preserved');
    expect(() => doc.turns.add(turnFixture(0)), throwsUnsupportedError);
  });
  test('bounds body by Unicode characters and rejects unsafe media paths', () {
    expect(
      () => StoryTurn(
        turnId: 'long',
        ordinal: 0,
        speakerId: 'A',
        content: 'x' * 4001,
      ),
      throwsFormatException,
    );
    expect(
      () => StoryActorSnapshot(
        actorId: 'A',
        name: 'A',
        avatarRelativePath: '../secret',
      ),
      throwsFormatException,
    );
    expect(
      () => StoryConfig(opening: 'x', targetEnding: 'y', plannedRounds: 301),
      throwsFormatException,
    );
  });
  test(
    'rejects unbounded imported snapshots and malformed checkpoint controls',
    () {
      final raw = storyFixture().toJson();
      expect(
        () => AutoStoryDocument.fromJson({
          ...raw,
          'worldBookSnapshots': [
            {'content': 'x' * 100001},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => DirectorCheckpoint(
          checkpointId: 'cp',
          coveredThroughOrdinal: -1,
          coveredTurnIdsHash: storyTurnsHash([]),
          planVersion: 1,
          stageStartedRound: 301,
        ),
        throwsFormatException,
      );
    },
  );
  test('fact evidence quotes must exist in covered body', () {
    final turn = turnFixture(0);
    final cp = DirectorCheckpoint(
      checkpointId: 'cp',
      coveredThroughOrdinal: 0,
      coveredTurnIdsHash: storyTurnsHash([turn]),
      planVersion: 1,
      confirmedFacts: [
        StoryFact(
          text: 'Invented',
          evidenceTurnIds: [turn.turnId],
          evidence: [
            StoryEvidence(turnId: turn.turnId, quote: 'never happened'),
          ],
        ),
      ],
    );
    expect(
      () => storyFixture().copyWith(
        turns: [turn],
        directorCheckpoints: [cp],
        currentCheckpointId: 'cp',
      ),
      throwsFormatException,
    );
  });
  test(
    'replanning preserves proven historical checkpoints from a longer plan',
    () {
      final turns = [turnFixture(0), turnFixture(1)];
      final cp = DirectorCheckpoint(
        checkpointId: 'old-final',
        coveredThroughOrdinal: 1,
        coveredTurnIdsHash: storyTurnsHash(turns),
        planVersion: 1,
        stageIndex: 5,
        summary: 'Already happened',
      );
      final prior = storyFixture().copyWith(
        turns: turns,
        plan: List.generate(
          6,
          (i) => StoryStage(
            id: 'old-$i',
            title: 'stage',
            objective: 'goal',
            minRounds: 1,
            targetRounds: i < 4 ? 2 : 1,
            acceptanceCriteria: ['condition'],
          ),
        ),
        directorCheckpoints: [cp],
        currentCheckpointId: cp.checkpointId,
      );
      final replanned = prior.copyWith(
        config: prior.config.copyWith(planVersion: 2),
        plan: List.generate(
          3,
          (i) => StoryStage(
            id: 'new-$i',
            title: 'stage',
            objective: 'goal',
            minRounds: 1,
            targetRounds: i == 0 ? 4 : 3,
            acceptanceCriteria: ['condition'],
          ),
        ),
        clearCurrentCheckpoint: true,
      );
      expect(replanned.directorCheckpoints.single.summary, 'Already happened');
      expect(replanned.currentCheckpoint, isNull);
      expect(replanned.turns.length, 2);
    },
  );
}
