import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../models/character_state.dart';
import '../../models/chat_message.dart';
import '../../models/message_anchor.dart';
import '../ai/ai_conversation_runner.dart';
import '../local_storage_service.dart';
import '../storage/storage_paths.dart';
import 'character_state_prompt.dart';

class StateRefreshContext {
  StateRefreshContext({
    required this.sessionId,
    required this.characterId,
    required List<ChatMessage> messages,
    required this.loadMessages,
    required this.isCurrent,
    required this.generate,
    this.characterContext = '',
  }) : messages = List.unmodifiable(messages);
  final String sessionId, characterId, characterContext;
  final List<ChatMessage> messages;
  final Future<List<ChatMessage>> Function() loadMessages;
  final bool Function() isCurrent;
  final Future<String> Function(String system, String user, AiCancelToken token)
  generate;
}

class CharacterStateService {
  CharacterStateService(this.storage);
  final LocalStorageService storage;
  static bool _globalBusy = false;
  static final Map<(CharacterStateService, String), _StateJob> _pending = {};
  final Map<String, int> _generations = {};
  final Map<String, AiCancelToken> _tokens = {};
  Future<File> _file(String sessionId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(sessionId)) {
      throw const FormatException('invalidSessionId');
    }
    return File(
      '${(await storage.appDataDirectory).path}/story/states/$sessionId.json',
    );
  }

  Future<List<CharacterStateView>> _read(File file, String s, String c) async {
    if (await storage.jsonStore.recoveryNeeded(file)) {
      await storage.jsonStore.recover(file);
    }
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString());
    validateCharacterStateFile(data, sessionId: s, characterId: c);
    final map = data as Map<String, dynamic>;
    return [
      for (final v in map['history'] as List)
        CharacterStateView.fromJson(Map<String, dynamic>.from(v as Map)),
    ];
  }

  CharacterStateView _resolve(
    List<CharacterStateView> history,
    String s,
    String c,
    List<ChatMessage> messages,
  ) {
    var selected = CharacterStateView.unknown(s, c);
    for (final record in history) {
      if (record.anchor == null || record.anchor!.matches(messages)) {
        selected = record;
      }
    }
    // Revision is the file's monotonic sequence, even when the visible path rolls back.
    return CharacterStateView.fromJson({
      ...selected.toJson(),
      'stateRevision': history.isEmpty ? 0 : history.last.revision,
    });
  }

  Future<CharacterStateView> loadCurrentState(
    String sessionId,
    String characterId,
    List<ChatMessage> messages,
  ) async {
    final file = await _file(sessionId);
    return storage.jsonStore.synchronized(
      file,
      () async => _resolve(
        await _read(file, sessionId, characterId),
        sessionId,
        characterId,
        messages,
      ),
    );
  }

  Future<CharacterStateView> editState(
    String sessionId,
    String characterId,
    List<ChatMessage> messages,
    StateEdit edit,
  ) => _edit(sessionId, characterId, messages, edit, 'manualEdit');
  Future<CharacterStateView> _edit(
    String s,
    String c,
    List<ChatMessage> messages,
    StateEdit edit,
    String reason, {
    bool Function()? guard,
    int? epoch,
  }) async {
    final capturedEpoch = epoch ?? storage.datasetEpoch;
    final file = await _file(s);
    return storage.jsonStore.maintain(() async {
      if (capturedEpoch != storage.datasetEpoch) {
        throw StateError('stateCancelled');
      }
      final paths = StoragePaths(await storage.appDataDirectory);
      final sessions = await storage.jsonStore.read(
        paths.chatSessions,
        <dynamic>[],
      );
      if (sessions is! List ||
          !sessions.whereType<Map<String, dynamic>>().any(
            (r) => r['id'] == s && r['characterId'] == c,
          )) {
        throw StateError('stateCancelled');
      }
      final envelope = await storage.jsonStore.read(
        paths.chatBySession(s),
        <String, dynamic>{},
      );
      if (envelope is! Map<String, dynamic> ||
          envelope['sessionId'] != s ||
          envelope['characterId'] != c ||
          envelope['messages'] is! List) {
        throw StateError('stateCancelled');
      }
      final stored = envelope['messages'] as List<dynamic>;
      final live = [
        for (final r in stored)
          ChatMessage.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
      if (live.length != messages.length ||
          (messages.isNotEmpty &&
              !MessageAnchor.capture(
                s,
                messages,
                messages.length - 1,
              ).matches(live))) {
        throw StateError('stateCancelled');
      }
      return storage.jsonStore.synchronized(file, () async {
        final history = await _read(file, s, c);
        if (guard != null && !guard()) throw StateError('stateCancelled');
        final current = _resolve(history, s, c, messages);
        final next = current.apply(
          edit,
          messages.isEmpty
              ? null
              : MessageAnchor.capture(s, messages, messages.length - 1),
          reason,
        );
        history.add(next);
        // Preserve the initial baseline, never use a future record for a missing old prefix.
        while (history.length > 1000) {
          history.removeAt(history.first.anchor == null ? 1 : 0);
        }
        await storage.jsonStore.writeNow(file, {
          'schemaVersion': 1,
          'sessionId': s,
          'characterId': c,
          'stateRevision': next.revision,
          'history': [for (final r in history) r.toJson()],
        });
        return next;
      });
    });
  }

  Future<CharacterStateView> resetState(
    String s,
    String c,
    List<ChatMessage> messages,
  ) async {
    cancelStateRefresh(s);
    final current = await loadCurrentState(s, c, messages);
    return _edit(
      s,
      c,
      messages,
      StateEdit(
        expectedRevision: current.revision,
        values: {for (final k in characterStateLimits.keys) k: null},
        locks: {for (final k in characterStateLimits.keys) k: false},
      ),
      'reset',
    );
  }

  Future<void> clearState(String s) async {
    cancelStateRefresh(s);
    final file = await _file(s);
    await storage.jsonStore.synchronized(file, () async {
      if (await file.exists()) await file.delete();
    });
  }

  Future<void> initializeState(
    String s,
    String c,
    CharacterStateView source,
  ) async {
    final file = await _file(s);
    final value = {
      ...source.toJson(),
      'sessionId': s,
      'characterId': c,
      'anchor': null,
      'stateRevision': 1,
      'reason': 'branchInitial',
    };
    await storage.jsonStore.write(file, {
      'schemaVersion': 1,
      'sessionId': s,
      'characterId': c,
      'stateRevision': 1,
      'history': [value],
    });
  }

  void cancelStateRefresh(String sessionId) {
    _generations[sessionId] = (_generations[sessionId] ?? 0) + 1;
    _tokens.remove(sessionId)?.cancel();
    _pending.remove((this, sessionId))?.done.complete();
  }

  static Future<void> _drain() async {
    if (_globalBusy) return;
    _globalBusy = true;
    try {
      while (_pending.isNotEmpty) {
        final job = _pending.remove(_pending.keys.first)!;
        try {
          await job.run();
          job.done.complete();
        } catch (e, stack) {
          job.done.completeError(e, stack);
        }
      }
    } finally {
      _globalBusy = false;
    }
  }

  Future<void> requestStateRefresh(StateRefreshContext context) {
    final s = context.sessionId;
    final generation = (_generations[s] ?? 0) + 1;
    _generations[s] = generation;
    final epoch = storage.datasetEpoch;
    bool valid() =>
        _generations[s] == generation &&
        storage.datasetEpoch == epoch &&
        context.isCurrent();
    final job = _StateJob(() async {
      if (!valid() || context.messages.isEmpty) return;
      final anchor = MessageAnchor.capture(
        s,
        context.messages,
        context.messages.length - 1,
      );
      final current = await loadCurrentState(
        s,
        context.characterId,
        context.messages,
      );
      if (!valid()) return;
      final token = AiCancelToken();
      _tokens[s] = token;
      try {
        final response = await context.generate(
          characterStateSystemPrompt,
          buildCharacterStateInput(
            current,
            context.messages,
            context.characterContext,
          ),
          token,
        );
        if (!valid()) return;
        final values = parseCharacterStateResponse(response);
        final latest = await context.loadMessages();
        if (!valid() ||
            latest.length != context.messages.length ||
            !anchor.matches(latest)) {
          return;
        }
        if (values.isEmpty) return;
        await _edit(
          s,
          context.characterId,
          latest,
          StateEdit(expectedRevision: current.revision, values: values),
          'aiRefresh',
          guard: valid,
          epoch: epoch,
        );
      } on StateError catch (e) {
        if (e.message != 'stateCancelled' && valid()) {
          rethrow;
        }
      } catch (_) {
        if (valid()) rethrow;
      } finally {
        if (identical(_tokens[s], token)) _tokens.remove(s);
      }
    });
    _pending.remove((this, s))?.done.complete();
    _pending[(this, s)] = job;
    unawaited(_drain());
    return job.done.future;
  }
}

class _StateJob {
  _StateJob(this.run);
  final Future<void> Function() run;
  final Completer<void> done = Completer<void>();
}

void validateCharacterStateFile(
  dynamic data, {
  String? sessionId,
  String? characterId,
}) {
  if (data is! Map ||
      data['schemaVersion'] != 1 ||
      data['history'] is! List ||
      (data['history'] as List).length > 1000 ||
      data['stateRevision'] is! int ||
      data['sessionId'] is! String ||
      data['characterId'] is! String) {
    throw const FormatException('invalidStateFile');
  }
  if ((sessionId != null && data['sessionId'] != sessionId) ||
      (characterId != null && data['characterId'] != characterId)) {
    throw const FormatException('stateIdentityMismatch');
  }
  var revision = 0;
  for (final json in data['history'] as List) {
    final state = CharacterStateView.fromJson(
      Map<String, dynamic>.from(json as Map),
    );
    if (state.sessionId != data['sessionId'] ||
        state.characterId != data['characterId'] ||
        state.revision <= revision ||
        (state.anchor != null && state.anchor!.sessionId != state.sessionId)) {
      throw const FormatException('invalidStateHistory');
    }
    revision = state.revision;
  }
  if (revision != data['stateRevision']) {
    throw const FormatException('invalidStateRevision');
  }
}
