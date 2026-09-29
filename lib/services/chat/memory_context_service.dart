import '../../models/character_memory_entry.dart';
import '../../models/chat_message.dart';
import '../../models/world_book.dart';

class MemoryContextResult {
  const MemoryContextResult({
    required this.activeEntries,
    required this.activeMemoryEntries,
    required this.activeWorldBookEntries,
    required this.memoryPrompt,
  });

  // Kept as an alias for callers from the pre-world-book implementation.
  final List<CharacterMemoryEntry> activeEntries;
  final List<CharacterMemoryEntry> activeMemoryEntries;
  final List<WorldBookEntry> activeWorldBookEntries;
  final String memoryPrompt;
}

class MemoryContextService {
  const MemoryContextService();

  MemoryContextResult build({
    required Iterable<CharacterMemoryEntry> entries,
    required String characterId,
    required String sessionId,
    required List<ChatMessage> messages,
    required int maxCharacters,
    bool allowSharedCharacterMemories = true,
    Iterable<WorldBook>? worldBooks,
    Iterable<WorldBookEntry>? worldBookEntries,
    Iterable<String>? worldBookIds,
  }) {
    if (!allowSharedCharacterMemories) {
      entries = entries.where(
        (entry) =>
            entry.scope == MemoryScope.session && entry.sessionId == sessionId,
      );
    }
    final recentText = messages.reversed
        .where((message) => message.isUser || message.isAssistant)
        .take(20)
        .map((message) => message.effectiveContent)
        .join('\n')
        .toLowerCase();
    final memoryEntries = entries.where((entry) {
      if (!entry.enabled || entry.characterId != characterId) {
        return false;
      }
      if (entry.scope == MemoryScope.session && entry.sessionId != sessionId) {
        return false;
      }
      return entry.title.trim().isNotEmpty &&
          entry.content.trim().isNotEmpty &&
          entry.keywords.isEmpty;
    }).toList();

    final useWorldBookContext =
        worldBooks != null || worldBookEntries != null || worldBookIds != null;
    if (!useWorldBookContext) {
      // Old callers and old tests can still render legacy keyword entries until
      // their storage is migrated. Production requests always pass the new
      // world-book arguments and therefore never use this branch.
      final legacyEntries = entries.where((entry) {
        if (!entry.enabled || entry.characterId != characterId) {
          return false;
        }
        if (entry.scope == MemoryScope.session &&
            entry.sessionId != sessionId) {
          return false;
        }
        return entry.title.trim().isNotEmpty &&
            entry.content.trim().isNotEmpty &&
            (entry.keywords.isEmpty ||
                entry.keywords.any(
                  (keyword) => recentText.contains(keyword.toLowerCase()),
                ));
      }).toList();
      legacyEntries.sort(_compareMemoryEntries);
      final seenContent = <String>{};
      final uniqueLegacyEntries = legacyEntries
          .where((entry) => seenContent.add(entry.content))
          .toList();
      final selected = _selectMemoryEntries(uniqueLegacyEntries, maxCharacters);
      return MemoryContextResult(
        activeEntries: List.unmodifiable(
          selected.map((item) => item.item.memory!),
        ),
        activeMemoryEntries: List.unmodifiable(
          selected.map((item) => item.item.memory!),
        ),
        activeWorldBookEntries: const [],
        memoryPrompt: selected.isEmpty ? '' : _formatLegacy(selected),
      );
    }

    final booksById = {
      for (final book in worldBooks ?? const <WorldBook>[]) book.id: book,
    };
    final referencedIds = (worldBookIds ?? const <String>[]).toSet();
    final activeWorldEntries =
        (worldBookEntries ?? const <WorldBookEntry>[]).where((entry) {
          final book = booksById[entry.worldBookId];
          return book != null &&
              referencedIds.contains(entry.worldBookId) &&
              book.enabled &&
              entry.enabled &&
              entry.title.trim().isNotEmpty &&
              entry.content.trim().isNotEmpty &&
              entry.keywords.isNotEmpty &&
              entry.keywords.any(
                (keyword) => recentText.contains(keyword.toLowerCase()),
              );
        }).toList()..sort((a, b) {
          final priority = b.priority.compareTo(a.priority);
          if (priority != 0) return priority;
          final book = a.worldBookId.compareTo(b.worldBookId);
          return book == 0 ? a.id.compareTo(b.id) : book;
        });

    final sessionMemories =
        memoryEntries
            .where((entry) => entry.scope == MemoryScope.session)
            .toList()
          ..sort(_compareMemoryEntries);
    final characterMemories =
        memoryEntries
            .where((entry) => entry.scope == MemoryScope.character)
            .toList()
          ..sort(_compareMemoryEntries);
    final candidates = <_ContextItem>[
      for (final entry in sessionMemories) _ContextItem.memory(entry),
      for (final entry in activeWorldEntries)
        _ContextItem.world(entry, booksById[entry.worldBookId]!.name),
      for (final entry in characterMemories) _ContextItem.memory(entry),
    ];
    final seenContent = <String>{};
    final unique = candidates
        .where((item) => seenContent.add(item.content))
        .toList();
    final selected = _selectContextItems(unique, maxCharacters);
    final activeMemories = selected
        .where((item) => item.item.memory != null)
        .map((item) => item.item.memory!)
        .toList();
    final selectedWorldEntries = selected
        .where((item) => item.item.worldBookEntry != null)
        .map((item) => item.item.worldBookEntry!)
        .toList();
    return MemoryContextResult(
      activeEntries: List.unmodifiable(activeMemories),
      activeMemoryEntries: List.unmodifiable(activeMemories),
      activeWorldBookEntries: List.unmodifiable(selectedWorldEntries),
      memoryPrompt: selected.isEmpty ? '' : _format(selected),
    );
  }
}

class _ContextItem {
  const _ContextItem._({this.memory, this.worldBookEntry, this.worldBookName});

  factory _ContextItem.memory(CharacterMemoryEntry entry) =>
      _ContextItem._(memory: entry);

  factory _ContextItem.world(WorldBookEntry entry, String name) =>
      _ContextItem._(worldBookEntry: entry, worldBookName: name);

  final CharacterMemoryEntry? memory;
  final WorldBookEntry? worldBookEntry;
  final String? worldBookName;

  int get priority => memory?.priority ?? worldBookEntry!.priority;
  String get id => memory?.id ?? worldBookEntry!.id;
  String get content => memory?.content ?? worldBookEntry!.content;
  String get title => memory?.title ?? worldBookEntry!.title;
}

class _PromptEntry {
  const _PromptEntry(this.item, this.content);

  final _ContextItem item;
  final String content;
}

List<_PromptEntry> _selectMemoryEntries(
  List<CharacterMemoryEntry> entries,
  int maxCharacters,
) => _selectContextItems([
  for (final entry in entries) _ContextItem.memory(entry),
], maxCharacters);

List<_PromptEntry> _selectContextItems(
  List<_ContextItem> candidates,
  int maxCharacters,
) {
  final selected = <_PromptEntry>[];
  final limit = maxCharacters.clamp(0, 12000).toInt();
  var used = _runeLength(_rules);
  var hasWorld = false;
  var hasLongTerm = false;
  var hasSession = false;
  final worldGroupNames = <String>{};
  for (final item in candidates) {
    late final int fixedCost;
    if (item.worldBookEntry != null) {
      final name = item.worldBookName!;
      final newGroup = !worldGroupNames.contains(name);
      fixedCost =
          (hasWorld ? 0 : 2 + _runeLength(_worldSectionHeader)) +
          (newGroup ? _runeLength(_worldGroupHeader(name)) + 1 : 0) +
          (hasWorld ? 1 : 0) +
          _runeLength(_worldLinePrefix(item.worldBookEntry!));
    } else {
      final isSession = item.memory!.scope == MemoryScope.session;
      final hasSection = isSession ? hasSession : hasLongTerm;
      final header = isSession ? _sessionSectionHeader : _longTermSectionHeader;
      fixedCost =
          (hasSection ? 1 : 2 + _runeLength(header)) +
          _runeLength(_memoryLinePrefix(item.title));
    }

    final contentLength = _runeLength(item.content);
    if (used + fixedCost + contentLength <= limit) {
      selected.add(_PromptEntry(item, item.content));
      used += fixedCost + contentLength;
      if (item.worldBookEntry != null) {
        hasWorld = true;
        worldGroupNames.add(item.worldBookName!);
      } else if (item.memory!.scope == MemoryScope.session) {
        hasSession = true;
      } else {
        hasLongTerm = true;
      }
      continue;
    }
    final fittingLength = limit - used - fixedCost;
    if (fittingLength > 0) {
      selected.add(
        _PromptEntry(
          item,
          String.fromCharCodes(item.content.runes.take(fittingLength)),
        ),
      );
    }
    break;
  }
  return selected;
}

int _compareMemoryEntries(CharacterMemoryEntry a, CharacterMemoryEntry b) {
  final priority = b.priority.compareTo(a.priority);
  return priority == 0 ? a.id.compareTo(b.id) : priority;
}

String _formatLegacy(List<_PromptEntry> items) {
  final sections = <String>[];
  final worldItems = items.where(
    (item) => item.item.memory!.keywords.isNotEmpty,
  );
  final longTerm = items.where(
    (item) =>
        item.item.memory!.keywords.isEmpty &&
        item.item.memory!.scope == MemoryScope.character,
  );
  final session = items.where(
    (item) =>
        item.item.memory!.keywords.isEmpty &&
        item.item.memory!.scope == MemoryScope.session,
  );
  if (worldItems.isNotEmpty) {
    sections.add(
      '【关键词触发世界书】\n${worldItems.map((item) {
        final entry = item.item.memory!;
        return '- ${entry.title}（触发词：${entry.keywords.join('、')}）：${item.content}';
      }).join('\n')}',
    );
  }
  if (longTerm.isNotEmpty) {
    sections.add(
      '【长期记忆】\n${longTerm.map((item) => '- ${item.item.title}：${item.content}').join('\n')}',
    );
  }
  if (session.isNotEmpty) {
    sections.add(
      '【当前对话记忆】\n${session.map((item) => '- ${item.item.title}：${item.content}').join('\n')}',
    );
  }
  return [...sections, _rules].join('\n\n');
}

String _format(List<_PromptEntry> items) {
  final worldLines = <String>[];
  final worldGroups = <String, List<_PromptEntry>>{};
  for (final item in items.where((item) => item.item.worldBookEntry != null)) {
    worldGroups.putIfAbsent(item.item.worldBookName!, () => []).add(item);
  }
  for (final group in worldGroups.entries) {
    worldLines.add(_worldGroupHeader(group.key));
    worldLines.addAll(
      group.value.map((item) {
        final entry = item.item.worldBookEntry!;
        return '${_worldLinePrefix(entry)}${item.content}';
      }),
    );
  }

  final longTerm = items.where(
    (item) => item.item.memory?.scope == MemoryScope.character,
  );
  final session = items.where(
    (item) => item.item.memory?.scope == MemoryScope.session,
  );
  final sections = <String>[];
  if (worldLines.isNotEmpty) {
    sections.add('$_worldSectionHeader${worldLines.join('\n')}');
  }
  if (longTerm.isNotEmpty) {
    sections.add(
      '$_longTermSectionHeader${longTerm.map((item) => '${_memoryLinePrefix(item.item.title)}${item.content}').join('\n')}',
    );
  }
  if (session.isNotEmpty) {
    sections.add(
      '$_sessionSectionHeader${session.map((item) => '${_memoryLinePrefix(item.item.title)}${item.content}').join('\n')}',
    );
  }
  return [...sections, _rules].join('\n\n');
}

const _worldSectionHeader = '【关键词世界书】\n';
const _longTermSectionHeader = '【长期记忆】\n';
const _sessionSectionHeader = '【当前对话记忆】\n';

String _worldGroupHeader(String name) => '【世界书：$name】';
String _worldLinePrefix(WorldBookEntry entry) =>
    '- ${entry.title}（触发词：${entry.keywords.join('、')}）：';
String _memoryLinePrefix(String title) => '- $title：';

const _rules = '''【记忆使用规则】
1. 世界书描述世界背景、地点、组织和客观规则。
2. 长期记忆描述跨会话稳定存在的事实。
3. 当前对话记忆只描述当前剧情状态。
4. 最近原始聊天优先于记忆、世界书和历史总结。
5. 不要主动复述全部内容。
6. 只有与当前话题有关时自然使用。''';

int _runeLength(String value) => value.runes.length;
