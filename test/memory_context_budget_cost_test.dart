import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/services/chat/memory_context_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26);
  final message = ChatMessage(role: 'user', content: 'trigger', time: now);

  CharacterMemoryEntry memory(
    String id,
    String content, {
    MemoryScope scope = MemoryScope.character,
  }) => CharacterMemoryEntry(
    id: id,
    characterId: 'character',
    scope: scope,
    sessionId: scope == MemoryScope.session ? 'session' : null,
    title: 'x',
    content: content,
    createdAt: now,
    updatedAt: now,
  );

  WorldBookEntry worldEntry(String id, String bookId, String content) =>
      WorldBookEntry(
        id: id,
        worldBookId: bookId,
        title: 'x',
        content: content,
        keywords: const ['trigger'],
        createdAt: now,
        updatedAt: now,
      );

  test('selects many fitting entries within the cap', () {
    final entries = [
      for (var index = 0; index < 1200; index++) memory('m$index', 'v$index'),
    ];
    final result = const MemoryContextService().build(
      entries: entries,
      characterId: 'character',
      sessionId: 'session',
      messages: const [],
      maxCharacters: 12000,
      worldBooks: const [],
      worldBookEntries: const [],
      worldBookIds: const [],
    );
    expect(result.activeMemoryEntries.length, greaterThan(1000));
    expect(result.memoryPrompt.runes.length, lessThanOrEqualTo(12000));
  });

  test(
    'same-name world books share one header and retain Unicode truncation',
    () {
      final books = [
        for (final id in ['a', 'b'])
          WorldBook(id: id, name: '共同', createdAt: now, updatedAt: now),
      ];
      final entries = [
        worldEntry('a', 'a', '😀甲'),
        worldEntry('b', 'b', '乙😀'),
      ];
      MemoryContextResult build(int budget) =>
          const MemoryContextService().build(
            entries: [
              memory('session', '前', scope: MemoryScope.session),
              memory('character', '后😀'),
            ],
            characterId: 'character',
            sessionId: 'session',
            messages: [message],
            maxCharacters: budget,
            worldBooks: books,
            worldBookEntries: entries,
            worldBookIds: const ['a', 'b'],
          );

      final full = build(12000);
      expect(full.activeMemoryEntries.map((entry) => entry.id), [
        'session',
        'character',
      ]);
      expect(full.activeWorldBookEntries.map((entry) => entry.id), ['a', 'b']);
      expect('【世界书：共同】'.allMatches(full.memoryPrompt).length, 1);
      expect(full.memoryPrompt, contains('😀甲\n- x（触发词：trigger）：乙😀'));

      final oneRuneShort = build(full.memoryPrompt.runes.length - 1);
      expect(oneRuneShort.activeWorldBookEntries.map((entry) => entry.id), [
        'a',
        'b',
      ]);
      expect(oneRuneShort.activeMemoryEntries.map((entry) => entry.id), [
        'session',
        'character',
      ]);
      expect(oneRuneShort.memoryPrompt, contains('😀甲\n- x（触发词：trigger）：乙😀'));
      expect(oneRuneShort.memoryPrompt, contains('【长期记忆】\n- x：'));
      expect(oneRuneShort.memoryPrompt, isNot(contains('【长期记忆】\n- x：后😀')));
      expect(
        oneRuneShort.memoryPrompt.runes.length,
        full.memoryPrompt.runes.length - 1,
      );
      expect(build(0).activeEntries, isEmpty);
    },
  );

  test('matches the prior formatter budget at world-book boundaries', () {
    final books = [
      for (final id in ['a', 'b'])
        WorldBook(id: id, name: '共同', createdAt: now, updatedAt: now),
    ];
    final worlds = [worldEntry('a', 'a', '😀甲'), worldEntry('b', 'b', '乙😀')];
    final memories = [
      memory('session', '前', scope: MemoryScope.session),
      memory('character', '后😀'),
    ];
    const candidates = [
      _BudgetCandidate('session', '前'),
      _BudgetCandidate('a', '😀甲'),
      _BudgetCandidate('b', '乙😀'),
      _BudgetCandidate('character', '后😀'),
    ];
    for (var budget = 0; budget <= 260; budget++) {
      final reference = _oldSelection(candidates, budget);
      final actual = const MemoryContextService().build(
        entries: memories,
        characterId: 'character',
        sessionId: 'session',
        messages: [message],
        maxCharacters: budget,
        worldBooks: books,
        worldBookEntries: worlds,
        worldBookIds: const ['a', 'b'],
      );
      expect(
        actual.memoryPrompt,
        reference.isEmpty ? '' : _worldPrompt(reference),
        reason: 'budget $budget',
      );
      expect(
        actual.activeMemoryEntries.map((entry) => entry.id),
        reference
            .where((item) => item.id == 'session' || item.id == 'character')
            .map((item) => item.id),
        reason: 'memory ids at budget $budget',
      );
      expect(
        actual.activeWorldBookEntries.map((entry) => entry.id),
        reference
            .where((item) => item.id == 'a' || item.id == 'b')
            .map((item) => item.id),
        reason: 'world ids at budget $budget',
      );
    }
  });
}

class _BudgetCandidate {
  const _BudgetCandidate(this.id, this.content);

  final String id;
  final String content;
}

List<_BudgetCandidate> _oldSelection(
  List<_BudgetCandidate> candidates,
  int budget,
) {
  final selected = <_BudgetCandidate>[];
  for (final item in candidates) {
    final full = [...selected, item];
    if (_worldPrompt(full).runes.length <= budget) {
      selected.add(item);
      continue;
    }
    final runes = item.content.runes.toList();
    for (var length = runes.length - 1; length >= 1; length--) {
      final partial = _BudgetCandidate(
        item.id,
        String.fromCharCodes(runes.take(length)),
      );
      if (_worldPrompt([...selected, partial]).runes.length <= budget) {
        selected.add(partial);
        break;
      }
    }
    break;
  }
  return selected;
}

String _worldPrompt(List<_BudgetCandidate> selected) {
  final byId = {for (final item in selected) item.id: item.content};
  final sections = <String>[];
  if (byId.containsKey('a') || byId.containsKey('b')) {
    final worldLines = ['【世界书：共同】'];
    if (byId.containsKey('a')) worldLines.add('- x（触发词：trigger）：${byId['a']}');
    if (byId.containsKey('b')) worldLines.add('- x（触发词：trigger）：${byId['b']}');
    sections.add('【关键词世界书】\n${worldLines.join('\n')}');
  }
  if (byId.containsKey('character')) {
    sections.add('【长期记忆】\n- x：${byId['character']}');
  }
  if (byId.containsKey('session')) {
    sections.add('【当前对话记忆】\n- x：${byId['session']}');
  }
  return [...sections, _referenceRules].join('\n\n');
}

const _referenceRules = '''【记忆使用规则】
1. 世界书描述世界背景、地点、组织和客观规则。
2. 长期记忆描述跨会话稳定存在的事实。
3. 当前对话记忆只描述当前剧情状态。
4. 最近原始聊天优先于记忆、世界书和历史总结。
5. 不要主动复述全部内容。
6. 只有与当前话题有关时自然使用。''';
