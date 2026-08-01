import 'dart:convert';
import 'dart:io';

import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/chat_summary.dart';
import '../../models/character_memory_entry.dart';
import '../../models/world_book.dart';
import '../storage/json_file_store.dart';
import '../storage/storage_paths.dart';

class ChatSessionService {
  ChatSessionService({required Directory root, JsonFileStore? jsonStore})
    : _paths = StoragePaths(root),
      _store = jsonStore ?? JsonFileStore();

  final StoragePaths _paths;
  final JsonFileStore _store;
  int _lastIdMicros = 0;

  Future<List<ChatSession>> loadChatSessions(String characterId) async {
    _requireSafeId(characterId, 'characterId');
    var sessions = await _readSessions();
    if (!sessions.any((session) => session.characterId == characterId)) {
      await _migrateOrCreateDefault(characterId);
      sessions = await _readSessions();
    }
    return sessions
        .where((session) => session.characterId == characterId)
        .toList()
      ..sort(ChatSession.compare);
  }

  Future<ChatSession> getOrCreateRecentChatSession(String characterId) async {
    final sessions = await loadChatSessions(characterId);
    final active = sessions.where((session) => !session.isArchived);
    final session = active.isEmpty
        ? await createChatSession(characterId)
        : active.first;
    final now = DateTime.now();
    final used = session.copyWith(updatedAt: now, lastUsedAt: now);
    await saveChatSession(used);
    return used;
  }

  Future<ChatSession> createChatSession(
    String characterId, {
    String? title,
  }) async {
    _requireSafeId(characterId, 'characterId');
    final now = DateTime.now();
    final session = ChatSession(
      id: _newSessionId(),
      characterId: characterId,
      title: ChatSession.normalizedTitle(title ?? '默认对话'),
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
    await _writeEmptySessionData(session);
    await saveChatSession(session);
    return session;
  }

  Future<void> saveChatSession(ChatSession session) async {
    _validateSession(session);
    final normalized = session.copyWith(
      title: ChatSession.normalizedTitle(session.title),
    );
    await _updateSessions((sessions) {
      final index = sessions.indexWhere((item) => item.id == normalized.id);
      index < 0 ? sessions.add(normalized) : sessions[index] = normalized;
      return sessions;
    });
  }

  Future<ChatSession> duplicateChatSession(ChatSession source) async {
    _validateSession(source);
    final now = DateTime.now();
    final copy = ChatSession(
      id: _newSessionId(),
      characterId: source.characterId,
      title: '${ChatSession.normalizedTitle(source.title)}（副本）',
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
    final messages = await loadChatBySession(source);
    final summary = await loadSummaryBySession(source);
    await saveChatBySession(copy, messages, touchSession: false);
    await saveSummaryBySession(
      ChatSummary(
        characterId: copy.characterId,
        sessionId: copy.id,
        summary: summary.summary,
        updatedAt: summary.updatedAt,
        summarizedMessageCount: summary.summarizedMessageCount,
      ),
    );
    await duplicateSessionMemories(source.characterId, source.id, copy.id);
    await saveChatSession(copy);
    return copy;
  }

  Future<void> deleteChatSession(ChatSession session) async {
    _validateSession(session);
    await _store.synchronized(_paths.chatSessions, () async {
      final sessions = await _readSessionsNow();
      final currentIndex = sessions.indexWhere((item) => item.id == session.id);
      if (currentIndex < 0) return;
      final current = sessions[currentIndex];
      if (!current.isArchived &&
          sessions
                  .where(
                    (item) =>
                        item.characterId == current.characterId &&
                        !item.isArchived,
                  )
                  .length ==
              1) {
        final now = DateTime.now();
        final replacement = ChatSession(
          id: _newSessionId(),
          characterId: current.characterId,
          title: '默认对话',
          createdAt: now,
          updatedAt: now,
          lastUsedAt: now,
        );
        await _writeEmptySessionData(replacement);
        sessions.add(replacement);
      }
      sessions.removeAt(currentIndex);
      await _store.writeNow(
        _paths.chatSessions,
        sessions.map((item) => item.toJson()).toList(),
      );
    });
    await _deleteIfExists(_paths.chatBySession(session.id));
    await _deleteIfExists(_paths.summaryBySession(session.id));
    await deleteSessionMemories(session.characterId, session.id);
  }

  Future<void> archiveChatSession(ChatSession session) async {
    _validateSession(session);
    await _updateSessions((sessions) {
      final index = sessions.indexWhere((item) => item.id == session.id);
      if (index < 0) throw StateError('对话不存在');
      final current = sessions[index];
      if (!current.isArchived &&
          sessions
                  .where(
                    (item) =>
                        item.characterId == current.characterId &&
                        !item.isArchived,
                  )
                  .length ==
              1) {
        throw StateError('至少保留一个未归档对话');
      }
      sessions[index] = current.copyWith(
        isArchived: true,
        updatedAt: DateTime.now(),
      );
      return sessions;
    });
  }

  Future<void> unarchiveChatSession(ChatSession session) async {
    _validateSession(session);
    await saveChatSession(
      session.copyWith(isArchived: false, updatedAt: DateTime.now()),
    );
  }

  Future<List<ChatMessage>> loadChatBySession(ChatSession session) async {
    _validateSession(session);
    final decoded = await _store.read(_paths.chatBySession(session.id), {
      'sessionId': session.id,
      'characterId': session.characterId,
      'messages': <dynamic>[],
    });
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid session chat file');
    }
    final messages = decoded['messages'];
    return messages is List
        ? messages
              .whereType<Map<String, dynamic>>()
              .map(ChatMessage.fromJson)
              .toList()
        : const [];
  }

  Future<void> saveChatBySession(
    ChatSession session,
    List<ChatMessage> messages, {
    bool touchSession = true,
  }) async {
    _validateSession(session);
    await _store.write(_paths.chatBySession(session.id), {
      'sessionId': session.id,
      'characterId': session.characterId,
      'messages': messages.map((message) => message.toJson()).toList(),
    }, compact: true);
    if (touchSession) {
      final now = DateTime.now();
      await saveChatSession(session.copyWith(updatedAt: now, lastUsedAt: now));
    }
  }

  Future<ChatSummary> loadSummaryBySession(ChatSession session) async {
    _validateSession(session);
    final decoded = await _store.read(
      _paths.summaryBySession(session.id),
      ChatSummary.empty(session.characterId, session.id).toJson(),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid session summary file');
    }
    final summary = ChatSummary.fromJson(decoded);
    return ChatSummary(
      characterId: session.characterId,
      sessionId: session.id,
      summary: summary.summary,
      updatedAt: summary.updatedAt,
      summarizedMessageCount: summary.summarizedMessageCount,
    );
  }

  Future<void> saveSummaryBySession(ChatSummary summary) async {
    _requireSafeId(summary.characterId, 'characterId');
    _requireSafeId(summary.sessionId, 'sessionId');
    await _store.write(
      _paths.summaryBySession(summary.sessionId),
      summary.toJson(),
    );
  }

  Future<List<CharacterMemoryEntry>> loadCharacterMemories(
    String characterId,
  ) async {
    _requireSafeId(characterId, 'characterId');
    final decoded = await _store.read(
      _paths.characterMemories(characterId),
      <dynamic>[],
    );
    return _parseMemories(decoded, characterId);
  }

  Future<List<WorldBook>> loadWorldBooks() async {
    final decoded = await _store.read(_paths.worldBooks, <dynamic>[]);
    if (decoded is! List) {
      throw const FormatException('Invalid world books file');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((value) {
          try {
            return WorldBook.fromJson(value);
          } on Object {
            return null;
          }
        })
        .whereType<WorldBook>()
        .where((book) => _isSafeId(book.id) && book.name.trim().isNotEmpty)
        .toList();
  }

  Future<void> saveWorldBook(WorldBook worldBook) async {
    _requireSafeId(worldBook.id, 'worldBook.id');
    final normalized = worldBook.copyWith(name: worldBook.name);
    if (normalized.name.isEmpty) {
      throw ArgumentError.value(worldBook.name, 'worldBook.name', 'must not be empty');
    }
    await _store.synchronized(_paths.worldBooks, () async {
      final books = await loadWorldBooks();
      final index = books.indexWhere((book) => book.id == normalized.id);
      if (index < 0) {
        books.add(normalized);
      } else {
        books[index] = normalized;
      }
      await _store.writeNow(
        _paths.worldBooks,
        books.map((book) => book.toJson()).toList(),
      );
    });
  }

  Future<void> deleteWorldBook(String worldBookId) async {
    _requireSafeId(worldBookId, 'worldBookId');
    await _store.synchronized(_paths.worldBooks, () async {
      final books = await loadWorldBooks()
        ..removeWhere((book) => book.id == worldBookId);
      await _store.writeNow(
        _paths.worldBooks,
        books.map((book) => book.toJson()).toList(),
      );
    });
    await _deleteIfExists(_paths.worldBookEntries(worldBookId));
  }

  Future<List<WorldBookEntry>> loadWorldBookEntries(String worldBookId) async {
    _requireSafeId(worldBookId, 'worldBookId');
    final decoded = await _store.read(
      _paths.worldBookEntries(worldBookId),
      <dynamic>[],
    );
    if (decoded is! List) {
      throw const FormatException('Invalid world book entries file');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((value) {
          try {
            return WorldBookEntry.fromJson(value);
          } on Object {
            return null;
          }
        })
        .whereType<WorldBookEntry>()
        .where(
          (entry) => entry.worldBookId == worldBookId && _isSafeId(entry.id),
        )
        .toList();
  }

  Future<void> saveWorldBookEntry(WorldBookEntry entry) async {
    _requireSafeId(entry.worldBookId, 'entry.worldBookId');
    _requireSafeId(entry.id, 'entry.id');
    final file = _paths.worldBookEntries(entry.worldBookId);
    await _store.synchronized(file, () async {
      final entries = await loadWorldBookEntries(entry.worldBookId);
      final index = entries.indexWhere((item) => item.id == entry.id);
      if (index < 0) {
        entries.add(entry);
      } else {
        entries[index] = entry;
      }
      await _store.writeNow(
        file,
        entries.map((item) => item.toJson()).toList(),
      );
    });
  }

  Future<void> deleteWorldBookEntry(String worldBookId, String entryId) async {
    _requireSafeId(worldBookId, 'worldBookId');
    _requireSafeId(entryId, 'entryId');
    final file = _paths.worldBookEntries(worldBookId);
    await _store.synchronized(file, () async {
      final entries = await loadWorldBookEntries(worldBookId)
        ..removeWhere((entry) => entry.id == entryId);
      await _store.writeNow(
        file,
        entries.map((entry) => entry.toJson()).toList(),
      );
    });
  }

  Future<void> saveCharacterMemory(CharacterMemoryEntry entry) async {
    _requireSafeId(entry.characterId, 'entry.characterId');
    final file = _paths.characterMemories(entry.characterId);
    await _store.synchronized(file, () async {
      final memories = await _readMemoriesNow(file, entry.characterId);
      final index = memories.indexWhere((item) => item.id == entry.id);
      index < 0 ? memories.add(entry) : memories[index] = entry;
      await _writeMemories(file, memories);
    });
  }

  Future<void> deleteCharacterMemory(
    String characterId,
    String memoryId,
  ) async {
    _requireSafeId(characterId, 'characterId');
    final file = _paths.characterMemories(characterId);
    await _store.synchronized(file, () async {
      final memories = await _readMemoriesNow(file, characterId)
        ..removeWhere((memory) => memory.id == memoryId);
      await _writeMemories(file, memories);
    });
  }

  Future<void> deleteSessionMemories(
    String characterId,
    String sessionId,
  ) async {
    _requireSafeId(characterId, 'characterId');
    _requireSafeId(sessionId, 'sessionId');
    final file = _paths.characterMemories(characterId);
    await _store.synchronized(file, () async {
      if (!await file.exists()) return;
      final memories = await _readMemoriesNow(file, characterId)
        ..removeWhere(
          (memory) =>
              memory.scope == MemoryScope.session &&
              memory.sessionId == sessionId,
        );
      await _writeMemories(file, memories);
    });
  }

  Future<List<CharacterMemoryEntry>> duplicateSessionMemories(
    String characterId,
    String sourceSessionId,
    String targetSessionId,
  ) async {
    _requireSafeId(characterId, 'characterId');
    _requireSafeId(sourceSessionId, 'sourceSessionId');
    _requireSafeId(targetSessionId, 'targetSessionId');
    final file = _paths.characterMemories(characterId);
    return _store.synchronized(file, () async {
      if (!await file.exists()) return const [];
      final memories = await _readMemoriesNow(file, characterId);
      final now = DateTime.now();
      var suffix = 0;
      final copies = [
        for (final memory in memories)
          if (memory.scope == MemoryScope.session &&
              memory.sessionId == sourceSessionId)
            memory.copyWith(
              id: 'memory_${now.microsecondsSinceEpoch}_${suffix++}',
              sessionId: targetSessionId,
              createdAt: now,
              updatedAt: now,
            ),
      ];
      if (copies.isNotEmpty) {
        await _writeMemories(file, [...memories, ...copies]);
      }
      return copies;
    });
  }

  Future<void> deleteCharacterSessions(String characterId) async {
    _requireSafeId(characterId, 'characterId');
    late List<ChatSession> removed;
    await _updateSessions((sessions) {
      removed = sessions
          .where((session) => session.characterId == characterId)
          .toList();
      sessions.removeWhere((session) => session.characterId == characterId);
      return sessions;
    });
    for (final session in removed) {
      await _deleteIfExists(_paths.chatBySession(session.id));
      await _deleteIfExists(_paths.summaryBySession(session.id));
    }
    await _deleteIfExists(_paths.characterMemories(characterId));
    await _deleteIfExists(_paths.chat(characterId));
    await _deleteIfExists(_paths.summary(characterId));
  }

  Future<void> _migrateOrCreateDefault(String characterId) async {
    await _store.synchronized(_paths.chatSessions, () async {
      final sessions = await _readSessionsNow();
      if (sessions.any((session) => session.characterId == characterId)) return;

      final legacyChat = _paths.chat(characterId);
      final legacySummary = _paths.summary(characterId);
      final hasLegacyChat = await legacyChat.exists();
      final hasLegacySummary = await legacySummary.exists();
      final now = DateTime.now();
      final session = ChatSession(
        id: hasLegacyChat || hasLegacySummary
            ? 'legacy_session_${_safeLegacyId(characterId)}'
            : _newSessionId(),
        characterId: characterId,
        title: '默认对话',
        createdAt: now,
        updatedAt: now,
        lastUsedAt: now,
      );

      final chatJson = hasLegacyChat
          ? await _readObject(legacyChat)
          : <String, dynamic>{'messages': <dynamic>[]};
      final summaryJson = hasLegacySummary
          ? await _readObject(legacySummary)
          : ChatSummary.empty(characterId, session.id).toJson();
      await _store.write(_paths.chatBySession(session.id), {
        'sessionId': session.id,
        'characterId': characterId,
        'messages': chatJson['messages'] is List
            ? chatJson['messages']
            : <dynamic>[],
      }, compact: true);
      final migratedSummary = ChatSummary.fromJson(summaryJson);
      await _store.write(_paths.summaryBySession(session.id), {
        ...migratedSummary.toJson(),
        'characterId': characterId,
        'sessionId': session.id,
      });
      sessions.add(session);
      await _store.writeNow(
        _paths.chatSessions,
        sessions.map((item) => item.toJson()).toList(),
      );

      if (hasLegacyChat) await legacyChat.delete();
      if (hasLegacySummary) await legacySummary.delete();
    });
  }

  Future<List<ChatSession>> _readSessions() async {
    final decoded = await _store.read(_paths.chatSessions, <dynamic>[]);
    return _parseSessions(decoded);
  }

  Future<List<ChatSession>> _readSessionsNow() async {
    if (!await _paths.chatSessions.exists()) return [];
    return _parseSessions(jsonDecode(await _paths.chatSessions.readAsString()));
  }

  List<ChatSession> _parseSessions(dynamic decoded) {
    if (decoded is! List) throw const FormatException('Invalid session index');
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ChatSession.fromJson)
        .where(
          (session) => _isSafeId(session.id) && _isSafeId(session.characterId),
        )
        .toList();
  }

  Future<void> _updateSessions(
    List<ChatSession> Function(List<ChatSession>) update,
  ) {
    return _store.synchronized(_paths.chatSessions, () async {
      final sessions = update(await _readSessionsNow());
      await _store.writeNow(
        _paths.chatSessions,
        sessions.map((session) => session.toJson()).toList(),
      );
    });
  }

  Future<void> _writeEmptySessionData(ChatSession session) async {
    await saveChatBySession(session, const [], touchSession: false);
    await saveSummaryBySession(
      ChatSummary.empty(session.characterId, session.id),
    );
  }

  Future<Map<String, dynamic>> _readObject(File file) async {
    final decoded = await _store.read(file, <String, dynamic>{});
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid legacy file');
    }
    return decoded;
  }

  Future<List<CharacterMemoryEntry>> _readMemoriesNow(
    File file,
    String characterId,
  ) async {
    if (!await file.exists()) return [];
    return _parseMemories(jsonDecode(await file.readAsString()), characterId);
  }

  List<CharacterMemoryEntry> _parseMemories(
    dynamic decoded,
    String characterId,
  ) {
    if (decoded is! List) throw const FormatException('Invalid memories file');
    final result = <CharacterMemoryEntry>[];
    for (final value in decoded.whereType<Map<String, dynamic>>()) {
      try {
        final memory = CharacterMemoryEntry.fromJson(value);
        if (memory.characterId == characterId) result.add(memory);
      } on Object {
        // Skip damaged entries while preserving the remaining memory file.
      }
    }
    return result;
  }

  Future<void> _writeMemories(File file, List<CharacterMemoryEntry> memories) =>
      _store.writeNow(file, memories.map((memory) => memory.toJson()).toList());

  String _newSessionId() {
    var micros = DateTime.now().microsecondsSinceEpoch;
    if (micros <= _lastIdMicros) micros = _lastIdMicros + 1;
    _lastIdMicros = micros;
    return 'chat_session_$micros';
  }

  static String _safeLegacyId(String id) {
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)
        ? id
        : base64Url.encode(utf8.encode(id)).replaceAll('=', '');
  }

  static bool _isSafeId(String id) =>
      id.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  static void _requireSafeId(String id, String name) {
    if (!_isSafeId(id)) throw ArgumentError.value(id, name, 'unsafe ID');
  }

  static void _validateSession(ChatSession session) {
    _requireSafeId(session.id, 'session.id');
    _requireSafeId(session.characterId, 'session.characterId');
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}
