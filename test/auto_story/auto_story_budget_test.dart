import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/services/auto_story/auto_story_budget.dart';
import 'auto_story_prompt_test.dart' show promptStory, promptTurn;

void main() {
  test(
    'entering a stage is progress, and waiting for its minimum is not stagnation',
    () {
      final base = promptStory(turns: List.generate(8, (i) => promptTurn(i)));
      final checkpoints = List.generate(
        4,
        (i) => DirectorCheckpoint(
          checkpointId: 'cp$i',
          coveredThroughOrdinal: i * 2 + 1,
          coveredTurnIdsHash: storyTurnsHash(
            base.turns.take(i * 2 + 2).toList(),
          ),
          planVersion: 1,
          stageIndex: 1,
        ),
      );
      expect(
        AutoStoryBudget.shouldPauseForStagnation(
          base.copyWith(
            directorCheckpoints: checkpoints.take(3).toList(),
            currentCheckpointId: 'cp2',
          ),
        ),
        isFalse,
      );
      expect(
        AutoStoryBudget.shouldPauseForStagnation(
          base.copyWith(
            directorCheckpoints: checkpoints,
            currentCheckpointId: 'cp3',
          ),
        ),
        isTrue,
      );
      final satisfied = DirectorCheckpoint.fromJson({
        ...checkpoints.last.toJson(),
        'stageSatisfied': true,
      });
      expect(
        AutoStoryBudget.shouldPauseForStagnation(
          base.copyWith(
            directorCheckpoints: [...checkpoints.take(3), satisfied],
            currentCheckpointId: 'cp3',
          ),
        ),
        isFalse,
      );
    },
  );
  test('80 rounds has 202 request default, not a 177 hard assumption', () {
    expect(AutoStoryBudget.defaultMaxRequests(80), 202);
  });
  test(
    'periodic and target triggers coalesce by persisted content-version check key',
    () {
      final base = promptStory(turns: List.generate(10, (i) => promptTurn(i)));
      final story = base.copyWith(
        plan: [
          StoryStage.fromJson({...base.plan[0].toJson(), 'targetRounds': 5}),
          StoryStage.fromJson({...base.plan[1].toJson(), 'targetRounds': 2}),
          StoryStage.fromJson({...base.plan[2].toJson(), 'targetRounds': 3}),
        ],
      );
      expect(AutoStoryBudget.shouldReview(story), isTrue);
      final checkpoint = DirectorCheckpoint(
        checkpointId: 'cp',
        coveredThroughOrdinal: 9,
        coveredTurnIdsHash: storyTurnsHash(story.turns),
        planVersion: 1,
        stageIndex: 0,
        checkKey: AutoStoryBudget.checkKey(story),
      );
      final checked = story.copyWith(
        directorCheckpoints: [checkpoint],
        currentCheckpointId: 'cp',
      );
      expect(AutoStoryBudget.shouldReview(checked), isFalse);
      final half = checked.copyWith(turns: [...checked.turns, promptTurn(10)]);
      expect(AutoStoryBudget.shouldReview(half), isFalse);
    },
  );
  test('last round must be reviewed even when it is not a stage boundary', () {
    final story = promptStory(turns: List.generate(20, (i) => promptTurn(i)));
    expect(AutoStoryBudget.shouldReview(story), isTrue);
  });
}
