import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/services/auto_story/auto_story_budget.dart';
import 'package:whisnya/services/auto_story/auto_story_prompt_builder.dart';
import 'auto_story_prompt_test.dart' show promptStory, promptTurn;

class CountingStory extends AutoStoryDocument {
  CountingStory(super.json) : super.fromJson();

  int serializations = 0;

  @override
  Map<String, dynamic> toJson() {
    serializations++;
    return super.toJson();
  }
}

void main() {
  test('actor prompt reads summary without copying the story', () {
    for (final summary in <String?>[null, '', '既有事实']) {
      final story = CountingStory({
        ...promptStory().toJson(),
        'replanSummary': ?summary,
      });
      final messages = AutoStoryPromptBuilder.buildActor(story, actorId: 'A');
      expect(
        messages[1]['content'],
        contains('已发生事实摘要：${summary ?? '尚无摘要，以正式正文为准。'}\n'),
      );
      expect(story.serializations, 0);
    }
  });

  test(
    'planning and budget checks read replan fields without serialization',
    () {
      final story = CountingStory({
        ...promptStory(turns: [promptTurn(0), promptTurn(1)]).toJson(),
        'replanSummary': '此前事实',
        'replanCoveredThroughOrdinal': 0,
        'replanStartRound': 0,
      });
      final plan = AutoStoryPromptBuilder.buildPlan(story);
      expect(plan.last['content'], contains('此前事实'));
      expect(plan.last['content'], contains('正文1'));
      expect(plan.last['content'], isNot(contains('正文0')));
      expect(AutoStoryBudget.shouldReview(story), isFalse);
      expect(story.serializations, 0);
    },
  );

  test('usage totals are reused per immutable story, not across copies', () {
    final story = promptStory().copyWith(
      requestLedger: [
        StoryRequestRecord(
          requestId: 'request-1',
          purpose: RequestPurpose.plan,
          inputTokens: 7,
          outputTokens: 3,
        ),
      ],
    );
    final totals = story.usageTotals;
    expect(totals.attempts, 1);
    expect(totals.totalTokens, 10);
    expect(totals.hasUnknown, isFalse);
    expect(story.usageTotals, same(totals));
    final changed = story.copyWith(requestLedger: []);
    expect(changed.usageTotals.totalTokens, 0);
    expect(changed.usageTotals.attempts, 0);
    expect(story.usageTotals.totalTokens, 10);
  });
}
