import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/services/chat/memory_context_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 31);

  CharacterMemoryEntry memory({
    required String id,
    required String content,
    MemoryScope scope = MemoryScope.character,
    String? sessionId,
    List<String> keywords = const [],
    int priority = 50,
    bool enabled = true,
    String characterId = 'character',
  }) => CharacterMemoryEntry(
    id: id,
    characterId: characterId,
    scope: scope,
    sessionId: sessionId,
    title: 'Title $id',
    content: content,
    keywords: keywords,
    priority: priority,
    enabled: enabled,
    createdAt: now,
    updatedAt: now,
  );

  ChatMessage message(String role, String content) =>
      ChatMessage(role: role, content: content, time: now);

  test(
    'activates matching scopes and keywords from only the latest 20 chats',
    () {
      final oldMessages = [
        message('user', 'ancient trigger'),
        for (var index = 0; index < 20; index++)
          message('assistant', 'filler $index'),
        message('system', 'system keyword'),
        message('user', 'We discussed ALPHA and 中文词 today'),
      ];
      final result = const MemoryContextService().build(
        entries: [
          memory(id: 'always', content: 'shared'),
          memory(id: 'english', content: 'english', keywords: const ['alpha']),
          memory(id: 'chinese', content: 'chinese', keywords: const ['中文词']),
          memory(id: 'old', content: 'old', keywords: const ['ancient']),
          memory(
            id: 'session',
            content: 'current',
            scope: MemoryScope.session,
            sessionId: 'session',
          ),
          memory(
            id: 'other-session',
            content: 'wrong session',
            scope: MemoryScope.session,
            sessionId: 'other',
          ),
          memory(id: 'disabled', content: 'off', enabled: false),
          memory(id: 'wrong-character', content: 'wrong', characterId: 'other'),
        ],
        characterId: 'character',
        sessionId: 'session',
        messages: oldMessages,
        maxCharacters: 4000,
      );

      expect(result.activeEntries.map((entry) => entry.id), [
        'always',
        'chinese',
        'english',
        'session',
      ]);
      expect(result.memoryPrompt, contains('【长期记忆】'));
      expect(result.memoryPrompt, contains('【当前对话记忆】'));
      expect(result.memoryPrompt, contains('【关键词触发世界书】'));
      expect(result.memoryPrompt, contains('触发词：alpha'));
      expect(result.memoryPrompt, contains('最近原始聊天优先于记忆'));
    },
  );

  test('reads only the tail needed for twenty eligible messages', () {
    final messages = _CountingMessages([
      for (var index = 0; index < 1000; index++)
        message('user', 'filler $index'),
      message('system', 'ignored'),
      message('assistant', 'TAIL-ONLY'),
    ]);
    final result = const MemoryContextService().build(
      entries: [
        memory(id: 'tail', content: 'match', keywords: const ['tail-only']),
      ],
      characterId: 'character',
      sessionId: 'session',
      messages: messages,
      maxCharacters: 4000,
    );

    expect(result.activeEntries.map((entry) => entry.id), ['tail']);
    expect(messages.readCount, lessThanOrEqualTo(25));
  });

  test('preserves newest-first matching with system gaps and Unicode', () {
    final result = const MemoryContextService().build(
      entries: [
        memory(id: 'reverse', content: 'reverse', keywords: const ['😀\n中文']),
        memory(id: 'forward', content: 'forward', keywords: const ['中文\n😀']),
        memory(id: 'system', content: 'system', keywords: const ['hidden']),
      ],
      characterId: 'character',
      sessionId: 'session',
      messages: [
        message('user', '中文'),
        message('system', 'hidden'),
        message('assistant', '😀'),
      ],
      maxCharacters: 4000,
    );

    expect(result.activeEntries.map((entry) => entry.id), ['reverse']);
  });

  test(
    'sorts stably, removes duplicate content, and safely truncates runes',
    () {
      final result = const MemoryContextService().build(
        entries: [
          memory(id: 'z', content: 'same', priority: 80),
          memory(id: 'a', content: 'same', priority: 80),
          memory(id: 'b', content: List.filled(600, '😀').join(), priority: 70),
          memory(id: 'c', content: 'low', priority: 1),
        ],
        characterId: 'character',
        sessionId: 'session',
        messages: const [],
        maxCharacters: 500,
      );

      expect(result.activeEntries.map((entry) => entry.id), ['a', 'b']);
      expect(result.memoryPrompt.runes.length, lessThanOrEqualTo(500));
      expect(result.memoryPrompt, startsWith('【长期记忆】'));
      expect(result.memoryPrompt, contains('Title a：same'));
      expect(result.memoryPrompt, isNot(contains('Title z')));
      expect(result.memoryPrompt, isNot(contains('Title c')));
      expect(
        String.fromCharCodes(result.memoryPrompt.runes),
        result.memoryPrompt,
        reason: 'truncation must not split a surrogate pair',
      );
    },
  );
}

class _CountingMessages extends ListBase<ChatMessage> {
  _CountingMessages(this._messages);

  final List<ChatMessage> _messages;
  int readCount = 0;

  @override
  int get length => _messages.length;

  @override
  set length(int value) => throw UnsupportedError('read-only test list');

  @override
  ChatMessage operator [](int index) {
    readCount++;
    return _messages[index];
  }

  @override
  void operator []=(int index, ChatMessage value) =>
      throw UnsupportedError('read-only test list');
}
