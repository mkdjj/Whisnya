import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_state.dart';
import 'package:whisnya/models/chat_message.dart';
import 'dart:convert';
import 'package:whisnya/services/story/character_state_prompt.dart';

void main() {
  test('refresh input bounds formal context and excludes private channels', () {
    final messages = [
      for (var i = 0; i < 15; i++)
        ChatMessage(
          id: 'm$i',
          role: 'assistant',
          content: 'FORMAL_$i ${'好' * 1500}',
          time: DateTime(2026),
          reasoningContent: 'PRIVATE_REASONING',
          innerVoice: 'PRIVATE_INNER',
        ),
    ];
    final input = buildCharacterStateInput(
      CharacterStateView.unknown('s', 'c'),
      messages,
      'fictional character',
    );
    expect(input, isNot(contains('PRIVATE_')));
    final rows =
        (jsonDecode(input) as Map<String, dynamic>)['messages']
            as List<dynamic>;
    expect(rows.length, 12);
    expect(
      (rows.first as Map<String, dynamic>)['content'],
      startsWith('FORMAL_3'),
    );
    expect(
      ((rows.last as Map<String, dynamic>)['content'] as String).runes.length,
      1200,
    );
  });
  test('strict response preserves absence and rejects a malformed field', () {
    expect(
      parseCharacterStateResponse(
        '```json\n{"emotion":" calm ","location":null,"locked":false}\n```',
      ),
      {'emotion': 'calm'},
    );
    expect(
      () => parseCharacterStateResponse('{"emotion":"ok","action":[]}'),
      throwsFormatException,
    );
    expect(
      () => parseCharacterStateResponse('x' * 16385),
      throwsFormatException,
    );
    expect(
      () => parseCharacterStateResponse('{"emotion":"${'x' * 61}"}'),
      throwsFormatException,
    );
  });
  test('state prompt is explicitly gated and bounded', () {
    final state = CharacterStateView.unknown('s', 'c').apply(
      StateEdit(
        expectedRevision: 0,
        values: {'location': '客厅'},
        locks: {'location': true},
      ),
      null,
      'manualEdit',
    );
    expect(
      buildCharacterStatePrompt(state, showCard: false, useInPrompt: true),
      isEmpty,
    );
    expect(
      buildCharacterStatePrompt(state, showCard: true, useInPrompt: false),
      isEmpty,
    );
    final prompt = buildCharacterStatePrompt(
      state,
      showCard: true,
      useInPrompt: true,
    );
    expect(prompt, contains('客厅'));
    expect(prompt, contains('用户设定'));
    expect(prompt.runes.length, lessThanOrEqualTo(500));
  });
}
