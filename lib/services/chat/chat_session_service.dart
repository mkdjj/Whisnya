import 'dart:convert';
import 'dart:io';

import '../../models/chat_message.dart';
import '../../models/message_anchor.dart';
import '../../models/chat_session.dart';
import '../../models/chat_summary.dart';
import '../../models/character_memory_entry.dart';
import '../../models/world_book.dart';
import '../storage/json_file_store.dart';
import '../storage/storage_paths.dart';
import '../storage/session_operation_coordinator.dart';
import 'chat_summary_service.dart';
import '../story/character_state_storage.dart';

class ChatSessionService {
  ChatSessionService({required Directory root, JsonFileStore? jsonStore})
    : _paths = StoragePaths(root),
      _operations = SessionOperationCoordinator.forRoot(root),
      _store = jsonStore ?? JsonFileStore();

  final StoragePaths _paths;
  final JsonFileStore _store;
  final SessionOperationCoordinator _operations;
  int _lastIdMicros = 0;

  Future<List<ChatSession>> loadChatSessions(String characterId) async {
    _requireSafeId(characterId, 'characterId');
    await recoverPendingClears();
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

  /// Index-only recovery: callers supply mappings verified against file metadata.
  Future<void> restoreRecoveredChatSessions(List<ChatSession> recovered) {
    if (recovered.isEmpty) return Future<void>.value();
    for (final session in recovered) {
      _validateSession(session);
    }
    return _store.maintain(
      () => _store.synchronized(_paths.chatSessions, () async {
        final file = _paths.chatSessions;
        if (await _store.recoveryNeeded(file)) await _store.recover(file);
        dynamic decoded = <dynamic>[];
        if (await file.exists()) {
          try {
            decoded = jsonDecode(await file.readAsString());
            if (decoded is! List) {
              throw const FormatException('Invalid session index');
            }
          } on FormatException {
            // Preserve exact corrupt evidence before replacing with verified rows.
            final stamp = DateTime.now().microsecondsSinceEpoch;
            var suffix = 0;
            var evidence = File('${file.path}.corrupt.$stamp');
            while (await evidence.exists()) {
              evidence = File('${file.path}.corrupt.$stamp.${++suffix}');
            }
            await file.copy(evidence.path);
            decoded = <dynamic>[];
          }
        }
        // Recovery must not normalize unrelated rows or discard unknown fields.
        final rows = List<dynamic>.of(decoded as List<dynamic>);
        final ids = rows
            .whereType<Map<String, dynamic>>()
            .map((row) => row['id'])
            .toSet();
        var changed = false;
        for (final session in recovered) {
          if (ids.add(session.id)) {
            rows.add(session.toJson());
            changed = true;
          }
        }
        if (changed) await _store.writeNow(file, rows);
      }),
    );
  }

  Future<ChatSession> createChatSession(String characterId, {String? title}) =>
      _store.runOperation(() => _createChatSession(characterId, title: title));

  Future<ChatSession> _createChatSession(
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
      messageCount: 0,
    );
    await _writeEmptySessionData(session);
    await _updateSessions((sessions) => sessions..add(session));
    return session;
  }

  Future<void> saveChatSession(ChatSession session) async {
    _validateSession(session);
    return _run(session.id, () => _saveChatSession(session));
  }

  Future<void> _saveChatSession(ChatSession session) async {
    final normalized = session.copyWith(
      title: ChatSession.normalizedTitle(session.title),
    );
    await _updateSessions((sessions) {
      final index = sessions.indexWhere((item) => item.id == normalized.id);
      if (index < 0) throw StateError('对话不存在');
      final current = sessions[index];
      sessions[index] = current.copyWith(
        title: normalized.title,
        updatedAt: normalized.updatedAt.isAfter(current.updatedAt)
            ? normalized.updatedAt
            : current.updatedAt,
        lastUsedAt: normalized.lastUsedAt.isAfter(current.lastUsedAt)
            ? normalized.lastUsedAt
            : current.lastUsedAt,
        openingMessageInitialized:
            normalized.openingMessageInitialized ||
            sessions[index].openingMessageInitialized,
        allowSharedCharacterMemories: normalized.allowSharedCharacterMemories,
      );
      return sessions;
    });
  }

  Future<ChatSession> markOpeningMessageInitialized({
    required String sessionId,
    required String characterId,
  }) => _run(
    sessionId,
    () => _markOpeningMessageInitialized(
      sessionId: sessionId,
      characterId: characterId,
    ),
  );

  Future<ChatSession> _markOpeningMessageInitialized({
    required String sessionId,
    required String characterId,
  }) async {
    _requireSafeId(sessionId, 'sessionId');
    _requireSafeId(characterId, 'characterId');
    late ChatSession updated;
    await _updateSessions((sessions) {
      final index = sessions.indexWhere(
        (session) =>
            session.id == sessionId && session.characterId == characterId,
      );
      if (index < 0) throw StateError('对话不存在');
      updated = sessions[index].copyWith(
        openingMessageInitialized: true,
        updatedAt: DateTime.now(),
      );
      sessions[index] = updated;
      return sessions;
    });
    return updated;
  }

  Future<ChatSession> duplicateChatSession(ChatSession source) async {
    _validateSession(source);
    return _run(source.id, () => _duplicateChatSession(source));
  }

  Future<ChatSession> _duplicateChatSession(ChatSession source) async {
    final sessions = await _readSessions();
    final sourceIndex = sessions.indexWhere(
      (session) =>
          session.id == source.id && session.characterId == source.characterId,
    );
    if (sourceIndex < 0) throw StateError('对话不存在');
    final latestSource = sessions[sourceIndex];
    final messages = await loadChatBySession(latestSource);
    final now = DateTime.now();
    final copy = latestSource.copyWith(
      id: _newSessionId(),
      characterId: latestSource.characterId,
      title: '${ChatSession.normalizedTitle(latestSource.title)}（副本）',
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
      openingMessageInitialized:
          latestSource.openingMessageInitialized || messages.isNotEmpty,
      messageCount: messages.length,
    );
    final summary = await loadSummaryBySession(latestSource);
    await _writeChat(copy, messages);
    await _writeSummary(
      ChatSummary(
        characterId: copy.characterId,
        sessionId: copy.id,
        summary: summary.summary,
        updatedAt: summary.updatedAt,
        summarizedMessageCount: summary.summarizedMessageCount,
      ),
    );
    await duplicateSessionMemories(
      latestSource.characterId,
      latestSource.id,
      copy.id,
    );
    await cloneStateFile(
      _paths.root,
      _store,
      latestSource.id,
      copy.id,
      copy.characterId,
    );
    await _updateSessions((sessions) => sessions..add(copy));
    return copy;
  }

  Future<void> deleteChatSession(ChatSession session) async {
    _validateSession(session);
    _operations.invalidate(session.id);
    return _run(session.id, () => _deleteChatSession(session));
  }

  Future<void> _deleteChatSession(ChatSession session) async {
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
          messageCount: 0,
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
    await _deleteStateFiles(session.id);
    await deleteSessionMemories(session.characterId, session.id);
  }

  Future<void> archiveChatSession(ChatSession session) async {
    _validateSession(session);
    return _run(session.id, () => _archiveChatSession(session));
  }

  Future<void> _archiveChatSession(ChatSession session) async {
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
    await _run(
      session.id,
      () => _updateSessions((sessions) {
        final index = sessions.indexWhere((s) => s.id == session.id);
        if (index < 0) throw StateError('对话不存在');
        sessions[index] = sessions[index].copyWith(
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        return sessions;
      }),
    );
  }

  Future<List<ChatMessage>> loadChatBySession(ChatSession session) async {
    _validateSession(session);
    final file = _paths.chatBySession(session.id);
    // Normal reads retain the store's recovery/admission/instrumentation path.
    // Only legacy identity migration needs a locked re-read before patching.
    final snapshot = await _store.read(file, <String, dynamic>{
      'sessionId': session.id,
      'characterId': session.characterId,
      'messages': <dynamic>[],
    });
    if (snapshot is! Map<String, dynamic> || snapshot['messages'] is! List) {
      throw const FormatException('Invalid session messages');
    }
    final rows = snapshot['messages'] as List<dynamic>;
    bool stableIds(List<dynamic> values) {
      final seen = <String>{};
      for (final row in values.whereType<Map<String, dynamic>>()) {
        final id = row['id'];
        if (id is! String || id.isEmpty || !seen.add(id)) return false;
      }
      return true;
    }

    if (stableIds(rows) &&
        rows.whereType<Map<String, dynamic>>().every((row) {
          final variants = row['variants'];
          return variants is! List<dynamic> || stableIds(variants);
        })) {
      return rows
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    }
    return _store.synchronized(file, () async {
      if (await _store.recoveryNeeded(file)) await _store.recover(file);
      final decoded = await file.exists()
          ? jsonDecode(await file.readAsString())
          : {
              'sessionId': session.id,
              'characterId': session.characterId,
              'messages': <dynamic>[],
            };
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid session chat file');
      }
      final messages = decoded['messages'];
      if (messages is! List) {
        throw const FormatException('Invalid session messages');
      }
      // Patch raw rows rather than round-tripping models: unknown and damaged
      // candidate fields remain available for recovery and future versions.
      var changed = false;
      final ids = <String>{};
      for (final row in messages.whereType<Map<String, dynamic>>()) {
        final existing = row['id'];
        if (existing is! String || existing.isEmpty || !ids.add(existing)) {
          var id = newStoryId();
          while (!ids.add(id)) {
            id = newStoryId();
          }
          row['id'] = id;
          changed = true;
        }
        final candidates = row['variants'];
        if (candidates is! List) continue;
        final variantIds = <String>{};
        for (final variant in candidates.whereType<Map<String, dynamic>>()) {
          final existingVariant = variant['id'];
          if (existingVariant is String &&
              existingVariant.isNotEmpty &&
              variantIds.add(existingVariant)) {
            continue;
          }
          var id = newStoryId();
          while (!variantIds.add(id)) {
            id = newStoryId();
          }
          variant['id'] = id;
          changed = true;
        }
      }
      if (changed) await _store.writeNow(file, decoded, compact: true);
      return messages
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    });
  }

  Future<void> saveChatBySession(
    ChatSession session,
    List<ChatMessage> messages, {
    bool touchSession = true,
  }) async {
    _validateSession(session);
    if (!await saveChatBySessionIfExists(
      session,
      messages,
      touchSession: touchSession,
    )) {
      throw StateError('对话不存在或操作已失效');
    }
  }

  Future<bool> saveChatBySessionIfExists(
    ChatSession session,
    List<ChatMessage> messages, {
    SessionOperationToken? token,
    bool touchSession = true,
  }) async {
    _validateSession(session);
    messages = assignMessageIds(messages)
        .where((m) => !m.isAssistant || m.effectiveContent.trim().isNotEmpty)
        .toList();
    final captured = token ?? captureToken(session);
    return _run(session.id, () async {
      if (captured.sessionId != session.id || !isTokenCurrent(captured)) {
        return false;
      }
      return _store.synchronized(_paths.chatSessions, () async {
        final sessions = await _readSessionsNow();
        final index = sessions.indexWhere(
          (item) =>
              item.id == session.id && item.characterId == session.characterId,
        );
        if (index < 0) return false;

        await _store.write(_paths.chatBySession(session.id), {
          'sessionId': session.id,
          'characterId': session.characterId,
          'messages': messages.map((message) => message.toJson()).toList(),
        }, compact: true);
        final now = DateTime.now();
        sessions[index] = sessions[index].copyWith(
          updatedAt: now,
          lastUsedAt: touchSession ? now : sessions[index].lastUsedAt,
          messageCount: messages.length,
        );
        await _store.writeNow(
          _paths.chatSessions,
          sessions.map((item) => item.toJson()).toList(),
        );
        return true;
      });
    });
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

  Future<void> saveSummaryBySession(
    ChatSummary summary, {
    SessionOperationToken? token,
  }) async {
    _requireSafeId(summary.characterId, 'characterId');
    _requireSafeId(summary.sessionId, 'sessionId');
    final captured =
        token ??
        SessionOperationToken(
          summary.sessionId,
          _store.datasetEpoch,
          _operations.revision(summary.sessionId),
        );
    await _run(summary.sessionId, () async {
      if (captured.sessionId != summary.sessionId ||
          !isTokenCurrent(captured)) {
        throw StateError('操作已失效');
      }
      final sessions = await _readSessions();
      if (!sessions.any(
        (s) =>
            s.id == summary.sessionId && s.characterId == summary.characterId,
      )) {
        throw StateError('对话不存在');
      }
      await _writeSummary(summary);
    });
  }

  Future<void> _writeSummary(ChatSummary summary) async {
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
    return _parseWorldBooks(decoded);
  }

  Future<List<WorldBook>> _readWorldBooksNow() async {
    final file = _paths.worldBooks;
    if (await _store.recoveryNeeded(file)) {
      await _store.recover(file);
    }
    if (!await file.exists()) return <WorldBook>[];
    return _parseWorldBooks(jsonDecode(await file.readAsString()));
  }

  List<WorldBook> _parseWorldBooks(dynamic decoded) {
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
      throw ArgumentError.value(
        worldBook.name,
        'worldBook.name',
        'must not be empty',
      );
    }
    await _store.synchronized(_paths.worldBooks, () async {
      final books = await _readWorldBooksNow();
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
    final entriesFile = _paths.worldBookEntries(worldBookId);
    await _store.synchronized(_paths.worldBooks, () async {
      await _store.synchronized(entriesFile, () async {
        final books = await _readWorldBooksNow()
          ..removeWhere((book) => book.id == worldBookId);
        await _store.writeNow(
          _paths.worldBooks,
          books.map((book) => book.toJson()).toList(),
        );
        await _deleteIfExists(entriesFile);
      });
    });
  }

  Future<List<WorldBookEntry>> loadWorldBookEntries(String worldBookId) async {
    _requireSafeId(worldBookId, 'worldBookId');
    final decoded = await _store.read(
      _paths.worldBookEntries(worldBookId),
      <dynamic>[],
    );
    return _parseWorldBookEntries(decoded, worldBookId);
  }

  Future<List<WorldBookEntry>> _readWorldBookEntriesNow(
    String worldBookId,
  ) async {
    _requireSafeId(worldBookId, 'worldBookId');
    final file = _paths.worldBookEntries(worldBookId);
    if (await _store.recoveryNeeded(file)) {
      await _store.recover(file);
    }
    if (!await file.exists()) return <WorldBookEntry>[];
    return _parseWorldBookEntries(
      jsonDecode(await file.readAsString()),
      worldBookId,
    );
  }

  List<WorldBookEntry> _parseWorldBookEntries(
    dynamic decoded,
    String worldBookId,
  ) {
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
    await _store.synchronized(_paths.worldBooks, () async {
      final books = await _readWorldBooksNow();
      if (!books.any((book) => book.id == entry.worldBookId)) {
        throw StateError('世界书不存在');
      }
      await _store.synchronized(file, () async {
        final entries = await _readWorldBookEntriesNow(entry.worldBookId);
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
    });
  }

  Future<void> deleteWorldBookEntry(String worldBookId, String entryId) async {
    _requireSafeId(worldBookId, 'worldBookId');
    _requireSafeId(entryId, 'entryId');
    final file = _paths.worldBookEntries(worldBookId);
    await _store.synchronized(file, () async {
      final entries = await _readWorldBookEntriesNow(worldBookId)
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
    return _store.maintain(() => _deleteCharacterSessions(characterId));
  }

  Future<void> _deleteCharacterSessions(String characterId) async {
    late List<ChatSession> removed;
    await _updateSessions((sessions) {
      removed = sessions
          .where((session) => session.characterId == characterId)
          .toList();
      sessions.removeWhere((session) => session.characterId == characterId);
      return sessions;
    });
    for (final session in removed) {
      _operations.invalidate(session.id);
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
      final decodedChat = hasLegacyChat
          ? await _store.read(legacyChat, <String, dynamic>{})
          : <String, dynamic>{'messages': <dynamic>[]};
      final isBareLegacyList = decodedChat is List;
      final chatJson = isBareLegacyList
          ? <String, dynamic>{'messages': decodedChat}
          : decodedChat;
      if (chatJson is! Map<String, dynamic> || chatJson['messages'] is! List) {
        throw const FormatException('Invalid legacy chat file');
      }
      final legacyMessages = chatJson['messages'] as List<dynamic>;
      final session = ChatSession(
        id: hasLegacyChat || hasLegacySummary
            ? 'legacy_session_${_safeLegacyId(characterId)}'
            : _newSessionId(),
        characterId: characterId,
        title: '默认对话',
        createdAt: now,
        updatedAt: now,
        lastUsedAt: now,
        openingMessageInitialized: legacyMessages.isNotEmpty,
        messageCount: legacyMessages.length,
      );

      final summaryJson = hasLegacySummary
          ? await _readObject(legacySummary)
          : ChatSummary.empty(characterId, session.id).toJson();
      await _store.write(_paths.chatBySession(session.id), {
        ...chatJson,
        'sessionId': session.id,
        'characterId': characterId,
        'messages': legacyMessages,
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

      if (hasLegacyChat) {
        if (isBareLegacyList) {
          // Retain original evidence for this recovered legacy representation.
          final stamp = DateTime.now().microsecondsSinceEpoch;
          var suffix = 0;
          var evidence = File('${legacyChat.path}.migrated.$stamp');
          while (await evidence.exists()) {
            evidence = File('${legacyChat.path}.migrated.$stamp.${++suffix}');
          }
          await legacyChat.rename(evidence.path);
        } else {
          await legacyChat.delete();
        }
      }
      if (hasLegacySummary) await legacySummary.delete();
    });
  }

  Future<List<ChatSession>> _readSessions() async {
    final decoded = await _store.read(_paths.chatSessions, <dynamic>[]);
    return _parseSessions(decoded);
  }

  Future<List<ChatSession>> _readSessionsNow() async {
    if (await _store.recoveryNeeded(_paths.chatSessions)) {
      await _store.recover(_paths.chatSessions);
    }
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
    await _writeChat(session, const []);
    await _writeSummary(ChatSummary.empty(session.characterId, session.id));
  }

  Future<void> _writeChat(ChatSession session, List<ChatMessage> messages) =>
      _store.write(_paths.chatBySession(session.id), {
        'sessionId': session.id,
        'characterId': session.characterId,
        'messages': messages.map((message) => message.toJson()).toList(),
      }, compact: true);

  SessionOperationToken captureToken(ChatSession session) =>
      SessionOperationToken(
        session.id,
        _store.datasetEpoch,
        _operations.revision(session.id),
      );
  bool isTokenCurrent(SessionOperationToken token) =>
      token.epoch == _store.datasetEpoch &&
      token.revision == _operations.revision(token.sessionId);
  Future<T> _run<T>(String id, Future<T> Function() action) =>
      _store.runOperation(
        () => _operations.run(id, () async {
          await _recoverClear(id);
          return action();
        }),
        expectedEpoch: _store.datasetEpoch,
      );

  File _clearJournal(String id) =>
      File('${_paths.root.path}/transactions/clear_$id.json');

  Future<ChatSummary> clearChatPreservingSummary(ChatSession session) async {
    _validateSession(session);
    _operations.invalidate(session.id);
    return _run(session.id, () async {
      final sessions = await _readSessions();
      final current = sessions
          .where(
            (s) => s.id == session.id && s.characterId == session.characterId,
          )
          .firstOrNull;
      if (current == null) throw StateError('对话不存在');
      final summary = await loadSummaryBySession(current);
      final rawChat = await _store.read(_paths.chatBySession(current.id), {
        'sessionId': current.id,
        'characterId': current.characterId,
        'messages': <dynamic>[],
      });
      final rawSummary = await _store.read(
        _paths.summaryBySession(current.id),
        summary.toJson(),
      );
      final rawState = await _store.read(
        _paths.characterState(current.id),
        null,
      );
      _validateStateOwnership(current, rawState);
      if (rawChat is! Map<String, dynamic> ||
          rawChat['messages'] is! List ||
          rawSummary is! Map<String, dynamic>) {
        throw const FormatException('Invalid clear source');
      }
      _validateClearSnapshot(current, rawChat, rawSummary);
      final journal = _clearJournal(current.id);
      await _store.write(journal, {
        'session': current.toJson(),
        'chat': rawChat,
        'summary': rawSummary,
        'state': rawState,
      });
      final next = summaryAfterChatClear(summary, DateTime.now());
      try {
        await _writeSummary(next);
        await _writeChat(current, const []);
        await _deleteStateFiles(current.id);
        await _updateSessions((latest) {
          final index = latest.indexWhere((s) => s.id == current.id);
          if (index < 0) throw StateError('对话不存在');
          latest[index] = latest[index].copyWith(messageCount: 0);
          return latest;
        });
        await journal.delete();
        return next;
      } catch (_) {
        // A failed rollback deliberately leaves the journal for startup recovery.
        await _recoverClear(current.id);
        rethrow;
      }
    });
  }

  Future<void> recoverPendingClears({bool pruneOrphanState = false}) async {
    final directory = _clearJournal('placeholder').parent;
    final ids = <String>{};
    if (await directory.exists()) {
      await for (final entry in directory.list()) {
        final name = entry.uri.pathSegments.last;
        final match = RegExp(
          r'^clear_([A-Za-z0-9_-]+)\.json(?:\.(?:bak|tmp))?$',
        ).firstMatch(name);
        if (match != null) ids.add(match[1]!);
      }
    }
    for (final id in ids) {
      await _run(id, () async {});
    }
    if (pruneOrphanState) await _pruneOrphanState();
  }

  Future<void> _recoverClear(String id) async {
    final journal = _clearJournal(id);
    if (!await journal.exists() &&
        !await File('${journal.path}.bak').exists() &&
        !await File('${journal.path}.tmp').exists()) {
      return;
    }
    final value = await _store.read(journal, null);
    if (value == null) return;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid clear transaction');
    }
    final session = ChatSession.fromJson(
      value['session'] as Map<String, dynamic>,
    );
    _validateSession(session);
    if (session.id != id) {
      throw const FormatException('Clear transaction target mismatch');
    }
    final chat = value['chat'];
    final summary = value['summary'];
    if (value.containsKey('state')) {
      _validateStateOwnership(session, value['state']);
    }
    if (chat is! Map<String, dynamic> || summary is! Map<String, dynamic>) {
      throw const FormatException('Invalid clear transaction snapshot');
    }
    _validateClearSnapshot(session, chat, summary);
    // Validate every target before any rollback writes, preserving raw JSON rows.
    final indexed = (await _readSessions())
        .where((s) => s.id == id && s.characterId == session.characterId)
        .firstOrNull;
    if (indexed == null) throw StateError('Clear transaction target missing');
    await _store.write(_paths.summaryBySession(id), summary);
    await _store.write(_paths.chatBySession(id), chat, compact: true);
    if (value.containsKey('state')) {
      final state = value['state'];
      if (state == null) {
        await _deleteStateFiles(id);
      } else {
        await _store.write(_paths.characterState(id), state);
      }
    }
    await _updateSessions((sessions) {
      final index = sessions.indexWhere((s) => s.id == id);
      if (index < 0) throw StateError('Clear transaction target missing');
      sessions[index] = ChatSession.fromJson({
        ...sessions[index].toJson(),
        'messageCount': session.messageCount,
      });
      return sessions;
    });
    await journal.delete();
  }

  void _validateStateOwnership(ChatSession session, dynamic state) {
    if (state != null &&
        (state is! Map<String, dynamic> ||
            state['sessionId'] != session.id ||
            state['characterId'] != session.characterId)) {
      throw const FormatException('Clear state ownership mismatch');
    }
  }

  Future<void> _deleteStateFiles(String id) async {
    final file = _paths.characterState(id);
    // Remove recovery candidates too; a later read must not resurrect cleared state.
    for (final path in [file.path, '${file.path}.bak', '${file.path}.tmp']) {
      await _deleteIfExists(File(path));
    }
  }

  Future<void> _pruneOrphanState() => _store.maintain(() async {
    if (!await _paths.chatSessions.exists()) return;
    final raw = await _store.read(_paths.chatSessions, null);
    if (raw is! List ||
        raw.any(
          (r) =>
              r is! Map<String, dynamic> ||
              r['id'] is! String ||
              !_isSafeId(r['id'] as String),
        )) {
      return; // An unreadable index is not evidence that a session was deleted.
    }
    final indexed = raw
        .cast<Map<String, dynamic>>()
        .map((r) => r['id'])
        .toSet();
    final directory = _paths.characterState('placeholder').parent;
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final match = RegExp(
        r'^([A-Za-z0-9_-]+)\.json(?:\.(?:bak|tmp))?$',
      ).firstMatch(entry.uri.pathSegments.last);
      if (match == null || indexed.contains(match[1])) continue;
      // Quarantine instead of destroying a potentially recoverable old orphan.
      var target = '${entry.path}.orphan';
      var suffix = 0;
      while (await File(target).exists()) {
        target = '${entry.path}.orphan.${++suffix}';
      }
      await entry.rename(target);
    }
  });

  void _validateClearSnapshot(
    ChatSession session,
    Map<String, dynamic> chat,
    Map<String, dynamic> summary,
  ) {
    bool mismatch(Map<String, dynamic> value, String key, String expected) =>
        value[key] != null && value[key] != '' && value[key] != expected;
    if (chat['messages'] is! List ||
        summary['summary'] is! String ||
        mismatch(chat, 'sessionId', session.id) ||
        mismatch(summary, 'sessionId', session.id) ||
        mismatch(chat, 'characterId', session.characterId) ||
        mismatch(summary, 'characterId', session.characterId)) {
      throw const FormatException('Invalid clear transaction snapshot');
    }
  }

  Future<void> backfillMessageCounts(
    List<ChatSession> sessions, {
    void Function(ChatSession)? onUpdated,
    void Function(String, Object)? onError,
  }) async {
    final pending = sessions.where((s) => s.messageCount == null).toList();
    final epoch = _store.datasetEpoch;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length) {
        final session = pending[cursor++];
        try {
          await _run(session.id, () async {
            if (epoch != _store.datasetEpoch) return;
            final latest = (await _readSessions())
                .where(
                  (s) =>
                      s.id == session.id &&
                      s.characterId == session.characterId,
                )
                .firstOrNull;
            if (latest == null) return;
            if (latest.messageCount != null) {
              onUpdated?.call(latest);
              return;
            }
            final file = _paths.chatBySession(latest.id);
            if (await _store.recoveryNeeded(file)) await _store.recover(file);
            if (!await file.exists()) {
              throw FileSystemException('会话聊天文件缺失', file.path);
            }
            final messages = await loadChatBySession(latest);
            late ChatSession updated;
            await _updateSessions((index) {
              final position = index.indexWhere((s) => s.id == latest.id);
              if (position < 0) throw StateError('对话不存在');
              updated = index[position].copyWith(messageCount: messages.length);
              index[position] = updated;
              return index;
            });
            onUpdated?.call(updated);
          });
        } catch (error) {
          onError?.call(session.id, error);
        }
      }
    }

    await Future.wait([worker(), worker()]);
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
