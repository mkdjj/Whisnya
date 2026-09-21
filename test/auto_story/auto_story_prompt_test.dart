import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/services/auto_story/auto_story_prompt_builder.dart';

AutoStoryDocument promptStory({List<StoryTurn> turns = const []}) =>
    AutoStoryDocument.fromJson({
      'schemaVersion': 1,
      'id': 'story',
      'revision': 0,
      'runGeneration': 0,
      'status': 'ready',
      'actors': [
        {
          'actorId': 'A',
          'name': '糖璃',
          'persona': 'A_PRIVATE',
          'publicProfile': 'A_PUBLIC',
          'endpointId': 'e',
          'model': 'm',
        },
        {
          'actorId': 'B',
          'name': '小雨',
          'persona': 'B_PRIVATE',
          'publicProfile': 'B_PUBLIC',
          'endpointId': 'e',
          'model': 'm',
        },
      ],
      'config': {
        'title': 'test',
        'opening': '雨天咖啡店',
        'targetEnding': 'TOP_SECRET_FUTURE',
        'style': '慢热',
        'plannedRounds': 10,
        'replyLengthPreset': 'standard',
        'interTurnDelayMs': 0,
        'maxRequests': 40,
        'planVersion': 1,
      },
      'plan': [
        for (var i = 0; i < 3; i++)
          {
            'id': 's$i',
            'title': '阶段$i',
            'objective': i == 0 ? 'CURRENT_OBJECTIVE' : 'FUTURE_OBJECTIVE',
            'minRounds': 1,
            'targetRounds': i == 2 ? 4 : 3,
            'acceptanceCriteria': ['condition'],
            'permittedDevelopments': ['交流'],
            'prematureDevelopments': <String>[],
          },
      ],
      'turns': turns.map((t) => t.toJson()).toList(),
      'nextActor': turns.length.isEven ? 'A' : 'B',
      'completedRounds': turns.length ~/ 2,
      'createdAt': '2026-01-01T00:00:00.000',
      'updatedAt': '2026-01-01T00:00:00.000',
    });

StoryTurn promptTurn(int n, {String? content}) => StoryTurn.fromJson({
  'turnId': 't$n',
  'ordinal': n,
  'roundNumber': n ~/ 2 + 1,
  'speakerId': n.isEven ? 'A' : 'B',
  'content': content ?? '正文$n',
  'reasoningContent': 'SECRET_REASONING',
  'source': 'ai',
  'endpointId': 'e',
  'model': 'm',
  'createdAt': '2026-01-01T00:00:00.000',
});

void main() {
  test(
    'actors receive only applied current scene transitions, not pending suggestions',
    () {
      final story = promptStory(turns: [promptTurn(0), promptTurn(1)]).copyWith(
        events: [
          StoryEvent(
            eventId: 'scene',
            kind: 'sceneTransition',
            content: 'CURRENT_BOOKSHOP_SCENE',
            effectiveAfterOrdinal: 1,
            status: 'applied',
          ),
          StoryEvent(
            eventId: 'proposal',
            kind: 'sceneTransition',
            content: 'FUTURE_MOON_SCENE',
            effectiveAfterOrdinal: 1,
            status: 'pending',
          ),
        ],
      );
      for (final actor in ['A', 'B']) {
        final request = AutoStoryPromptBuilder.buildActor(
          story,
          actorId: actor,
        ).toString();
        expect(request, contains('CURRENT_BOOKSHOP_SCENE'));
        expect(request, isNot(contains('FUTURE_MOON_SCENE')));
      }
    },
  );
  test(
    'pinned facts remain explicit shared factual context even outside the summary',
    () {
      final turn = promptTurn(0, content: '撑起同一把伞');
      final fact = StoryFact(
        text: '双方此时共享一把伞',
        evidenceTurnIds: ['t0'],
        evidence: [StoryEvidence(turnId: 't0', quote: '同一把伞')],
      );
      final story = promptStory(turns: [turn]).copyWith(lockedFacts: [fact]);
      expect(
        AutoStoryPromptBuilder.buildActor(story, actorId: 'A').toString(),
        contains('双方此时共享一把伞'),
      );
      expect(
        AutoStoryPromptBuilder.buildActor(story, actorId: 'B').toString(),
        contains('双方此时共享一把伞'),
      );
    },
  );
  test(
    'replan includes every unsummarized turn, never only the recent twelve',
    () {
      final story = promptStory(turns: List.generate(16, (i) => promptTurn(i)));
      final request = AutoStoryPromptBuilder.buildPlan(story).toString();
      expect(request, contains('正文0'));
      expect(request, contains('正文15'));
    },
  );
  test(
    'actors get only own private persona and other public profile, never future ending',
    () {
      final story = promptStory();
      for (final actor in ['A', 'B']) {
        final request = AutoStoryPromptBuilder.buildActor(
          story,
          actorId: actor,
        );
        final text = request.map((m) => m['content']).join('\n');
        expect(text, contains('${actor}_PRIVATE'));
        expect(text, contains('${actor == 'A' ? 'B' : 'A'}_PUBLIC'));
        expect(text, isNot(contains('${actor == 'A' ? 'B' : 'A'}_PRIVATE')));
        expect(text, isNot(contains('TOP_SECRET_FUTURE')));
        expect(text, isNot(contains('FUTURE_OBJECTIVE')));
        expect(text, contains('CURRENT_OBJECTIVE'));
      }
      expect(
        AutoStoryPromptBuilder.buildPlan(story).toString(),
        contains('TOP_SECRET_FUTURE'),
      );
    },
  );
  test(
    'recent twelve complete turns map perspective and exclude reasoning',
    () {
      final request = AutoStoryPromptBuilder.buildActor(
        promptStory(turns: List.generate(16, (i) => promptTurn(i))),
        actorId: 'B',
      );
      final history = request
          .where((e) => RegExp(r'正文\d+').hasMatch(e['content']!))
          .toList();
      expect(history.length, 12);
      expect(history.first['role'], 'user');
      expect(history.first['content'], contains('正文4'));
      expect(history[1]['role'], 'assistant');
      expect(request.toString(), isNot(contains('SECRET_REASONING')));
    },
  );
  test(
    'review batch preserves complete contiguous turns and its exact coverage',
    () {
      final batch = AutoStoryPromptBuilder.reviewBatch(
        promptStory(
          turns: List.generate(8, (i) => promptTurn(i, content: '字' * 3000)),
        ),
        maxCharacters: 9000,
      );
      expect(batch.turns.map((t) => t.ordinal), [0, 1]);
      expect(batch.coveredThroughOrdinal, 1);
    },
  );
  test(
    'world snapshots trigger only from visible content and shared background does not leak private memories',
    () {
      final story = AutoStoryDocument.fromJson({
        ...promptStory().toJson(),
        'actors': [
          {...promptStory().actors.first.toJson(), 'sourceId': 'original'},
          promptStory().actors.last.toJson(),
        ],
        'worldBookSnapshots': [
          {
            'id': 'book',
            'name': 'book',
            'entries': [
              {
                'id': 'entry',
                'worldBookId': 'book',
                'title': '店铺',
                'content': 'MATCHED_WORLD',
                'keywords': ['咖啡店'],
              },
              {
                'id': 'private-trigger',
                'worldBookId': 'book',
                'title': '暗号',
                'content': 'UNTRIGGERED_WORLD',
                'keywords': ['SECRET_REASONING'],
              },
            ],
          },
        ],
        'importedMemorySnapshots': [
          {
            'id': 'memory',
            'characterId': 'original',
            'scope': 'character',
            'title': '秘密',
            'content': 'PRIVATE_MEMORY',
          },
        ],
      });
      final a = AutoStoryPromptBuilder.buildActor(
        story,
        actorId: 'A',
      ).toString();
      final b = AutoStoryPromptBuilder.buildActor(
        story,
        actorId: 'B',
      ).toString();
      expect(a, contains('MATCHED_WORLD'));
      expect(b, contains('MATCHED_WORLD'));
      expect(a, contains('PRIVATE_MEMORY'));
      expect(b, isNot(contains('PRIVATE_MEMORY')));
      expect(a, isNot(contains('UNTRIGGERED_WORLD')));
    },
  );
  test(
    'round instructions remain visible to both actors and expire next round',
    () {
      final instruction = StoryEvent(
        eventId: 'event',
        kind: 'directorInstruction',
        content: '下一轮下雨',
        effectiveAfterOrdinal: -1,
        scope: 'round',
        status: 'pending',
      );
      expect(
        AutoStoryPromptBuilder.activeInstructions(
          promptStory().copyWith(events: [instruction]),
        ).length,
        1,
      );
      expect(
        AutoStoryPromptBuilder.activeInstructions(
          promptStory(turns: [promptTurn(0)]).copyWith(events: [instruction]),
        ).length,
        1,
      );
      expect(
        AutoStoryPromptBuilder.activeInstructions(
          promptStory(
            turns: [promptTurn(0), promptTurn(1)],
          ).copyWith(events: [instruction]),
        ),
        isEmpty,
      );
    },
  );
}
