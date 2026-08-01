import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_memory_entry.dart';

void main() {
  final now = DateTime.utc(2026, 7, 31);

  test('normalizes scope, keywords, priority, and required text', () {
    final entry = CharacterMemoryEntry(
      id: ' memory_1 ',
      characterId: ' character ',
      scope: MemoryScope.character,
      sessionId: 'ignored',
      title: ' Title ',
      content: ' Content ',
      keywords: const [' Foo ', 'foo', '', 'BAR', 'bar '],
      priority: 120,
      createdAt: now,
      updatedAt: now,
    );

    expect(entry.id, 'memory_1');
    expect(entry.characterId, 'character');
    expect(entry.sessionId, isNull);
    expect(entry.title, 'Title');
    expect(entry.content, 'Content');
    expect(entry.keywords, ['Foo', 'BAR']);
    expect(entry.priority, 100);
    expect(
      () => CharacterMemoryEntry(
        id: 'id',
        characterId: 'character',
        scope: MemoryScope.session,
        title: 'title',
        content: 'content',
        createdAt: now,
        updatedAt: now,
      ),
      throwsArgumentError,
    );
    expect(
      () => CharacterMemoryEntry(
        id: 'id',
        characterId: 'character',
        scope: MemoryScope.character,
        title: ' ',
        content: 'content',
        createdAt: now,
        updatedAt: now,
      ),
      throwsArgumentError,
    );
  });

  test('JSON round trip clamps priority and copyWith preserves invariants', () {
    final entry = CharacterMemoryEntry.fromJson({
      'id': 'memory_1',
      'characterId': 'character',
      'scope': 'session',
      'sessionId': 'session',
      'title': 'Title',
      'content': 'Content',
      'keywords': [' One ', 'ONE', 'Two'],
      'priority': -4,
      'enabled': false,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    expect(entry.priority, 0);
    expect(entry.keywords, ['One', 'Two']);
    expect(entry.enabled, isFalse);
    expect(
      CharacterMemoryEntry.fromJson(entry.toJson()).toJson(),
      entry.toJson(),
    );

    final shared = entry.copyWith(
      scope: MemoryScope.character,
      priority: 101,
      enabled: true,
    );
    expect(shared.sessionId, isNull);
    expect(shared.priority, 100);
    expect(shared.enabled, isTrue);
  });
}
