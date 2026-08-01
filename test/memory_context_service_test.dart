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
