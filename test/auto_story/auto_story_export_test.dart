import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/auto_story/auto_story_export.dart';

void main() {
  test('default export excludes planning, private personas and reasoning', () {
    final text = formatAutoStoryText({
      'config': {
        'title': 'Story',
        'targetEnding': 'FUTURE SECRET',
        'plannedRounds': 10,
      },
      'actors': [
        {'actorId': 'A', 'name': 'Alpha', 'persona': 'PRIVATE'},
        {'actorId': 'B', 'name': 'Beta'},
      ],
      'status': 'paused',
      'turns': [
        {
          'turnId': 't0',
          'ordinal': 0,
          'speakerId': 'A',
          'source': 'ai',
          'content': 'Hello',
          'reasoningContent': 'HIDDEN',
        },
        {
          'turnId': 't1',
          'ordinal': 1,
          'speakerId': 'B',
          'source': 'manual',
          'content': 'Hi',
        },
      ],
      'events': [
        {
          'kind': 'sceneTransition',
          'content': 'Next morning',
          'effectiveAfterOrdinal': 1,
          'status': 'applied',
        },
      ],
      'plan': [
        {'title': 'Secret plan', 'objective': 'FUTURE SECRET'},
      ],
    });
    expect(text, contains('Alpha'));
    expect(text, contains('Beta（AI代演）'));
    expect(text, contains('本人接管'));
    expect(text, contains('Next morning'));
    expect(text, isNot(contains('FUTURE SECRET')));
    expect(text, isNot(contains('PRIVATE')));
    expect(text, isNot(contains('HIDDEN')));
  });
  test('future goals are exported only with explicit inclusion', () {
    final data = {
      'config': {'title': 'Story', 'targetEnding': 'Goal', 'plannedRounds': 10},
      'actors': <Map<String, dynamic>>[],
      'turns': <Map<String, dynamic>>[],
      'events': <Map<String, dynamic>>[],
      'status': 'draft',
      'plan': [
        {'title': 'Phase', 'objective': 'Objective'},
      ],
    };
    expect(formatAutoStoryText(data, includePlan: true), contains('Goal'));
    expect(formatAutoStoryText(data, includePlan: true), contains('Objective'));
  });
}
