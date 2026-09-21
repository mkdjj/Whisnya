import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/auto_story/auto_story_director_service.dart';
import 'package:whisnya/models/auto_story.dart';
import 'auto_story_prompt_test.dart' show promptStory, promptTurn;

Map<String, dynamic> stage(int weight, {int minimum = 1}) => {
  'id': 'untrusted-id',
  'title': '发现线索',
  'objective': '找到下一条线索',
  'minRounds': minimum,
  'targetRounds': weight,
  'acceptanceCriteria': ['发现证物'],
  'permittedDevelopments': ['调查'],
  'prematureDevelopments': ['直接破案'],
};

void main() {
  test(
    'plan allocates minima then largest remainders deterministically and replaces model IDs',
    () {
      final plan = AutoStoryDirectorService.parsePlan(
        jsonEncode({
          'stages': [stage(1), stage(2), stage(3)],
        }),
        plannedRounds: 10,
        idPrefix: 'plan_2',
      );
      expect(plan.map((s) => s.targetRounds), [2, 3, 5]);
      expect(plan.map((s) => s.id), [
        'plan_2_stage_0',
        'plan_2_stage_1',
        'plan_2_stage_2',
      ]);
    },
  );
  test('plan rejects minimum overflow, stage count and fractional rounds', () {
    for (final values in [
      [stage(3, minimum: 4), stage(3, minimum: 4), stage(3, minimum: 4)],
      [stage(1), stage(1)],
      [
        stage(1),
        stage(1),
        {...stage(1), 'minRounds': 1.2},
      ],
    ]) {
      expect(
        () => AutoStoryDirectorService.parsePlan(
          jsonEncode({'stages': values}),
          plannedRounds: 10,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'review rejects invented, cropped dream and future evidence and wrong coverage',
    () {
      for (final content in ['我梦见我们结婚了。', '我们计划以后结婚了再旅行。']) {
        final story = promptStory(
          turns: [
            promptTurn(0, content: content),
            promptTurn(1),
          ],
        );
        expect(
          () => AutoStoryDirectorService.parseReview(
            jsonEncode(review(quote: '结婚了')),
            story: story,
            coveredThroughOrdinal: 1,
          ),
          throwsFormatException,
        );
      }
      final story = promptStory(
        turns: [
          promptTurn(0, content: '我们交换了戒指。'),
          promptTurn(1),
        ],
      );
      expect(
        () => AutoStoryDirectorService.parseReview(
          jsonEncode(review(turnId: 'imaginary')),
          story: story,
          coveredThroughOrdinal: 1,
        ),
        throwsFormatException,
      );
      expect(
        () => AutoStoryDirectorService.parseReview(
          jsonEncode({...review(), 'coveredThroughOrdinal': 3}),
          story: story,
          coveredThroughOrdinal: 1,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'review advances at most one local stage and never accepts model stageIndex',
    () {
      final story = promptStory(
        turns: [
          promptTurn(0, content: '我们交换了戒指。'),
          promptTurn(1),
        ],
      );
      final result = AutoStoryDirectorService.parseReview(
        jsonEncode({...review(), 'stageIndex': 99}),
        story: story,
        coveredThroughOrdinal: 1,
      );
      expect(result.checkpoint!.stageIndex, 1);
      expect(result.checkpoint!.stageStartedRound, 1);
      expect(result.goalReached, isFalse);
    },
  );
  test(
    'minimum rounds preserves satisfaction without advancing and goal requires final stage',
    () {
      final base = promptStory(
        turns: [
          promptTurn(0, content: '我们交换了戒指。'),
          promptTurn(1),
        ],
      );
      final stage = StoryStage.fromJson({
        ...base.plan.first.toJson(),
        'minRounds': 3,
      });
      final story = base.copyWith(plan: [stage, ...base.plan.skip(1)]);
      final result = AutoStoryDirectorService.parseReview(
        jsonEncode(review()),
        story: story,
        coveredThroughOrdinal: 1,
      );
      expect(result.checkpoint!.stageIndex, 0);
      expect(result.checkpoint!.stageSatisfied, isTrue);
      expect(
        () => AutoStoryDirectorService.parseReview(
          jsonEncode({
            ...review(),
            'goalReached': true,
            'goalEvidence': [
              {'turnId': 't0', 'quote': '交换了戒指', 'eventType': 'actual'},
            ],
          }),
          story: story,
          coveredThroughOrdinal: 1,
        ),
        throwsFormatException,
      );
    },
  );
}

Map<String, dynamic> review({String quote = '交换了戒指', String turnId = 't0'}) => {
  'coveredThroughOrdinal': 1,
  'summary': '双方交换戒指。',
  'facts': [
    {
      'text': '交换戒指',
      'evidence': [
        {'turnId': turnId, 'quote': quote},
      ],
    },
  ],
  'stageSatisfied': true,
  'criteriaEvidence': [
    {
      'criterionIndex': 0,
      'turnId': turnId,
      'quote': quote,
      'eventType': 'actual',
    },
  ],
  'nextBeat': '交谈',
  'pacing': 'normal',
  'sceneTransition': null,
  'goalReached': false,
  'goalEvidence': <Map<String, dynamic>>[],
};
