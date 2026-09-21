import '../../models/auto_story.dart';

class AutoStoryBudget {
  static bool shouldPauseForStagnation(AutoStoryDocument story) {
    if (story.status == StoryStatus.completed) return false;
    final byRound = <int, DirectorCheckpoint>{};
    for (final checkpoint in story.directorCheckpoints) {
      if (checkpoint.planVersion == story.config.planVersion &&
          !checkpoint.checkKey.contains(':batch:')) {
        byRound[(checkpoint.coveredThroughOrdinal + 1) ~/ 2] = checkpoint;
      }
    }
    final ordered = byRound.values.toList()
      ..sort(
        (a, b) => a.coveredThroughOrdinal.compareTo(b.coveredThroughOrdinal),
      );
    var previousStage = story.replanStageIndex;
    var stalled = 0;
    for (final checkpoint in ordered) {
      if (checkpoint.stageIndex != previousStage || checkpoint.stageSatisfied) {
        stalled = 0;
      } else {
        stalled++;
      }
      previousStage = checkpoint.stageIndex;
    }
    return stalled >= 3;
  }

  static int defaultMaxRequests(int rounds) =>
      2 * rounds + 2 * ((rounds + 4) ~/ 5) + 10;
  static String checkKey(AutoStoryDocument story) =>
      '${story.config.planVersion}:${story.completedRounds}:${storyTurnsHash(story.turns)}';
  static bool shouldReview(AutoStoryDocument story) {
    if (story.turns.isEmpty || story.turns.length.isOdd || story.plan.isEmpty) {
      return false;
    }
    final key = checkKey(story);
    if (story.directorCheckpoints.any((c) => c.checkKey == key)) return false;
    final checkpoint = story.currentCheckpoint;
    final stage = story.plan[story.stageIndex];
    final used =
        story.completedRounds -
        (checkpoint?.stageStartedRound ??
            (story.toJson()['replanStartRound'] as int? ?? 0));
    return story.completedRounds % 5 == 0 ||
        story.completedRounds >= story.config.plannedRounds ||
        used == stage.targetRounds ||
        (checkpoint?.stageSatisfied == true && used >= stage.minRounds) ||
        (checkpoint == null && story.config.planVersion > 1) ||
        (checkpoint?.checkKey.startsWith('$key:batch:') ?? false);
  }
}
