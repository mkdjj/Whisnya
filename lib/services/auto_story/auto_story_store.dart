import 'dart:convert';
import 'dart:io';
import '../../models/auto_story.dart';
import '../local_storage_service.dart';

class StoryStorageException implements Exception {
  const StoryStorageException(this.cause);
  final Object cause;
  @override
  String toString() => 'StoryStorageException: $cause';
}

class StoryMissingException implements Exception {
  const StoryMissingException(this.storyId);
  final String storyId;
  @override
  String toString() => 'Story missing: $storyId';
}

class StoryBudgetException implements Exception {
  const StoryBudgetException(this.reason);
  final StoryPauseReason reason;
  @override
  String toString() => 'Story budget exhausted: ${reason.name}';
}

/// All authority lives in a story document. The index is only a derived cache.
class AutoStoryStore {
  AutoStoryStore(this.storage);
  final LocalStorageService storage;
  int? _recoveredEpoch;
  int? _headersEpoch;
  List<AutoStoryHeader>? _headers;
  final Map<String, String> _unreadableStories = {};
  Map<String, String> get unreadableStories =>
      Map.unmodifiable(_unreadableStories);
  bool indexNeedsRepair = false;
  int get datasetEpoch => storage.jsonStore.datasetEpoch;

  Future<File> _file(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Unsafe story identifier');
    }
    return File.fromUri(
      (await storage.appDataDirectory).uri.resolve('auto_stories/$id.json'),
    );
  }

  Future<AutoStoryDocument?> _readNow(File file) async {
    // Called under this file's lock, never use public read() (which waits on it).
    if (await storage.jsonStore.recoveryNeeded(file)) {
      await storage.jsonStore.recover(file);
    }
    if (!await file.exists()) return null;
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Story must be an object');
    }
    final doc = AutoStoryDocument.fromJson(raw);
    if (!file.path.replaceAll('\\', '/').endsWith('/${doc.id}.json')) {
      throw const FormatException('Story filename does not match identity');
    }
    return doc;
  }

  Future<void> _writeNow(File file, AutoStoryDocument doc) async {
    try {
      await storage.jsonStore.writeNow(file, doc.toJson());
    } on FileSystemException catch (e) {
      throw StoryStorageException(e);
    }
  }

  Future<T> _locked<T>(
    String id,
    Future<T> Function(File, AutoStoryDocument?) action, {
    int? expectedEpoch,
  }) => storage.jsonStore.runOperation(() async {
    final file = await _file(id);
    return storage.jsonStore.synchronized(
      file,
      () async => action(file, await _readNow(file)),
    );
  }, expectedEpoch: expectedEpoch);

  Future<AutoStoryDocument> loadStory(String storyId) => _locked(
    storyId,
    (_, doc) async => doc ?? (throw StoryMissingException(storyId)),
  );

  Future<AutoStoryDocument> createStory(AutoStoryDocument draft) async {
    final result = await _locked(draft.id, (file, existing) async {
      if (existing != null) throw StateError('Story already exists');
      if (draft.status != StoryStatus.draft ||
          draft.turns.isNotEmpty ||
          draft.requestLedger.isNotEmpty) {
        throw StateError('Create requires a new draft');
      }
      final doc = draft.copyWith(
        revision: 1,
        privacyRequired: draft.privacyRequired,
        updatedAt: DateTime.now(),
      );
      await _writeNow(file, doc);
      return doc;
    });
    await _refreshIndexBestEffort(storyId: draft.id);
    return result;
  }

  Future<AutoStoryDocument> mutateStory(
    String storyId,
    AutoStoryDocument Function(AutoStoryDocument) mutation, {
    int? expectedRevision,
  }) async {
    final result = await _locked(storyId, (file, doc) async {
      if (doc == null) throw StoryMissingException(storyId);
      if (expectedRevision != null && expectedRevision != doc.revision) {
        throw StateError('Story changed; reload before editing');
      }
      var next = mutation(doc);
      if (next.id != doc.id ||
          next.actors.map((a) => a.actorId).join() !=
              doc.actors.map((a) => a.actorId).join()) {
        throw StateError('Actor identity is fixed');
      }
      final changedConfig =
          jsonEncode(next.config.toJson()..remove('title')) !=
              jsonEncode(doc.config.toJson()..remove('title')) ||
          jsonEncode(next.actors.map((a) => a.toJson()).toList()) !=
              jsonEncode(doc.actors.map((a) => a.toJson()).toList()) ||
          jsonEncode(next.plan.map((a) => a.toJson()).toList()) !=
              jsonEncode(doc.plan.map((a) => a.toJson()).toList());
      if (changedConfig) {
        if (doc.status == StoryStatus.running) {
          throw StateError('Pause before editing');
        }
        for (var i = 0; i < 2; i++) {
          if (doc.turns.isNotEmpty &&
              (next.actors[i].sourceId != doc.actors[i].sourceId ||
                  next.actors[i].persona != doc.actors[i].persona)) {
            throw StateError('Started actor snapshots are fixed');
          }
        }
        next = next.copyWith(
          runGeneration: doc.runGeneration + 1,
          config: next.config.copyWith(planVersion: doc.config.planVersion + 1),
          goalStatus: 'pending',
          status: next.status == StoryStatus.completed
              ? StoryStatus.paused
              : next.status,
          clearCurrentCheckpoint: true,
          pauseAfterCurrent: false,
          requestLedger: _cancelPending(next.requestLedger),
        );
      }
      next = next.copyWith(
        revision: doc.revision + 1,
        privacyRequired: doc.privacyRequired || next.privacyRequired,
        updatedAt: DateTime.now(),
      );
      await _writeNow(file, next);
      return next;
    });
    await _refreshIndexBestEffort(storyId: storyId);
    return result;
  }

  Future<AutoStoryDocument> beginRun(String storyId) => mutateStory(storyId, (
    doc,
  ) {
    if (doc.status != StoryStatus.ready && doc.status != StoryStatus.paused) {
      throw StateError('Story is not ready to run');
    }
    return doc.copyWith(
      status: StoryStatus.running,
      runGeneration: doc.runGeneration + 1,
      pauseAfterCurrent: false,
      clearPauseReason: true,
      requestLedger: _cancelPending(doc.requestLedger),
    );
  });

  List<StoryRequestRecord> _cancelPending(
    List<StoryRequestRecord> records, {
    String status = 'cancelled',
  }) => records
      .map((r) => r.status == 'pending' ? r.copyWith(status: status) : r)
      .toList();

  Future<StoryOperationToken> reserveRequest(
    String storyId,
    RequestPurpose purpose, {
    String? requestId,
    bool replaceLast = false,
  }) async {
    final result = await _locked(storyId, (file, doc) async {
      if (doc == null) throw StoryMissingException(storyId);
      final id = requestId ?? newStoryId();
      for (final r in doc.requestLedger) {
        if (r.requestId == id) {
          if (r.purpose != purpose ||
              r.replaceLast != replaceLast ||
              r.runGeneration != doc.runGeneration ||
              r.planVersion != doc.config.planVersion) {
            throw StateError('Request ID already belongs to another operation');
          }
          return _token(doc.id, r);
        }
      }
      if (doc.pauseAfterCurrent) throw StateError('Pause requested');
      if (doc.requestLedger.any(
        (r) => r.status == 'pending' && r.runGeneration == doc.runGeneration,
      )) {
        throw StateError('A story request is already in flight');
      }
      if (doc.usageTotals.attempts >= doc.config.maxRequests) {
        throw const StoryBudgetException(StoryPauseReason.requestLimit);
      }
      if (doc.config.tokenLimit != null &&
          doc.usageTotals.totalTokens >= doc.config.tokenLimit!) {
        throw const StoryBudgetException(StoryPauseReason.tokenLimit);
      }
      final actorRequest =
          purpose == RequestPurpose.actorA || purpose == RequestPurpose.actorB;
      if (actorRequest && !replaceLast) {
        if (doc.status != StoryStatus.running) {
          throw StateError('Actor request requires running');
        }
        if (doc.turns.length >= doc.config.plannedRounds * 2) {
          throw const StoryBudgetException(StoryPauseReason.lengthLimit);
        }
        if ((purpose == RequestPurpose.actorA ? 'A' : 'B') != doc.nextActor) {
          throw StateError('Actor cursor mismatch');
        }
      }
      if (replaceLast &&
          (doc.turns.isEmpty ||
              doc.turns.last.source != StoryTurnSource.ai ||
              (doc.status != StoryStatus.paused &&
                  doc.status != StoryStatus.completed))) {
        throw StateError(
          'Only the last AI turn can be regenerated while paused',
        );
      }
      final ordinal = replaceLast ? doc.turns.length - 1 : doc.turns.length;
      final record = StoryRequestRecord(
        requestId: id,
        purpose: purpose,
        runGeneration: doc.runGeneration,
        expectedNextOrdinal: ordinal,
        expectedSpeaker: ordinal.isEven ? 'A' : 'B',
        planVersion: doc.config.planVersion,
        replaceLast: replaceLast,
      );
      await _writeNow(
        file,
        doc.copyWith(
          requestLedger: [...doc.requestLedger, record],
          revision: doc.revision + 1,
          updatedAt: DateTime.now(),
        ),
      );
      return _token(doc.id, record);
    });
    await _refreshIndexBestEffort(storyId: storyId);
    return result;
  }

  StoryOperationToken _token(String id, StoryRequestRecord r) =>
      StoryOperationToken(
        storyId: id,
        datasetEpoch: datasetEpoch,
        runGeneration: r.runGeneration,
        expectedNextOrdinal: r.expectedNextOrdinal,
        expectedSpeaker: r.expectedSpeaker,
        requestId: r.requestId,
        planVersion: r.planVersion,
        replaceLast: r.replaceLast,
      );

  CommitResult? _fence(AutoStoryDocument? doc, StoryOperationToken token) {
    if (doc == null) return CommitResult.missing;
    if (token.datasetEpoch != datasetEpoch) return CommitResult.stale;
    final matching = doc.requestLedger
        .where((r) => r.requestId == token.requestId)
        .toList();
    if (matching.isEmpty) return CommitResult.stale;
    final request = matching.single;
    if (request.status == 'committed') return CommitResult.alreadyCommitted;
    if (request.status != 'pending' ||
        doc.runGeneration != token.runGeneration ||
        doc.config.planVersion != token.planVersion ||
        request.runGeneration != token.runGeneration ||
        request.expectedNextOrdinal != token.expectedNextOrdinal ||
        request.expectedSpeaker != token.expectedSpeaker ||
        request.replaceLast != token.replaceLast) {
      return CommitResult.stale;
    }
    final ordinal = token.replaceLast ? doc.turns.length - 1 : doc.turns.length;
    if (ordinal != token.expectedNextOrdinal ||
        (ordinal.isEven ? 'A' : 'B') != token.expectedSpeaker) {
      return CommitResult.stale;
    }
    return null;
  }

  Future<CommitResult> _commit(
    StoryOperationToken token,
    AutoStoryDocument Function(AutoStoryDocument) patch,
  ) async {
    if (token.datasetEpoch != datasetEpoch) return CommitResult.stale;
    try {
      final result = await _locked(token.storyId, (file, doc) async {
        final rejected = _fence(doc, token);
        if (rejected != null) return rejected;
        final current = doc!;
        var next = patch(current);
        next = next.copyWith(
          requestLedger: next.requestLedger
              .map(
                (r) => r.requestId == token.requestId
                    ? r.copyWith(status: 'committed')
                    : r,
              )
              .toList(),
          revision: current.revision + 1,
          updatedAt: DateTime.now(),
        );
        if (current.pauseAfterCurrent && next.status != StoryStatus.completed) {
          next = next.copyWith(
            status: StoryStatus.paused,
            pauseReason: current.pauseReason ?? StoryPauseReason.userPause,
            pauseAfterCurrent: false,
          );
        }
        await _writeNow(file, next);
        return CommitResult.applied;
      }, expectedEpoch: token.datasetEpoch);
      if (result == CommitResult.applied) {
        await _refreshIndexBestEffort(storyId: token.storyId);
      }
      return result;
    } on StateError {
      if (token.datasetEpoch != datasetEpoch) return CommitResult.stale;
      rethrow;
    }
  }

  Future<CommitResult> commitTurn(StoryOperationToken token, StoryTurn turn) =>
      _commit(token, (doc) {
        if (turn.ordinal != token.expectedNextOrdinal ||
            turn.speakerId != token.expectedSpeaker ||
            turn.requestId != token.requestId ||
            turn.source != StoryTurnSource.ai) {
          throw StateError('Turn does not match its reservation');
        }
        final record = doc.requestLedger.firstWhere(
          (r) => r.requestId == token.requestId,
        );
        if (![
          RequestPurpose.actorA,
          RequestPurpose.actorB,
          RequestPurpose.regenerate,
          RequestPurpose.repair,
        ].contains(record.purpose)) {
          throw StateError('Not an actor request');
        }
        if (token.replaceLast) {
          final previous = doc.turns.last;
          if (turn.turnId == previous.turnId ||
              turn.replacesTurnId != previous.turnId) {
            throw StateError(
              'Replacement must carry new identity and replaced ID',
            );
          }
          return _replaceLastTurn(doc, turn);
        }
        return doc.copyWith(turns: [...doc.turns, turn]);
      });

  Future<CommitResult> commitDirector(
    StoryOperationToken token,
    DirectorResult result,
  ) => _commit(token, (doc) {
    if (token.replaceLast) throw StateError('Director cannot replace actor');
    final request = doc.requestLedger.firstWhere(
      (r) => r.requestId == token.requestId,
    );
    if (![
      RequestPurpose.plan,
      RequestPurpose.review,
      RequestPurpose.replan,
      RequestPurpose.repair,
    ].contains(request.purpose)) {
      throw StateError('Not a director request');
    }
    final cp = result.checkpoint;
    if (cp != null &&
        (cp.planVersion != doc.config.planVersion ||
            cp.stageIndex > doc.stageIndex + 1 ||
            doc.turns.length.isOdd)) {
      throw StateError('Director cannot skip stage or review half round');
    }
    if (cp != null &&
        cp.checkKey.isNotEmpty &&
        doc.directorCheckpoints.any((c) => c.checkKey == cp.checkKey)) {
      return doc;
    }
    if (result.goalReached &&
        (cp == null ||
            cp.coveredThroughOrdinal != doc.turns.length - 1 ||
            cp.goalEvidence.isEmpty)) {
      throw StateError('Goal requires complete current evidence');
    }
    return doc.copyWith(
      plan: result.plan,
      directorCheckpoints: cp == null ? null : [...doc.directorCheckpoints, cp],
      currentCheckpointId: cp?.checkpointId,
      events: [...doc.events, ...result.events],
      goalStatus: result.goalReached ? 'reached' : null,
      status: result.goalReached
          ? StoryStatus.completed
          : (result.plan != null && doc.status == StoryStatus.draft
                ? StoryStatus.ready
                : doc.status),
      pauseAfterCurrent: result.goalReached ? false : null,
    );
  });

  Future<void> requestPause(String storyId) async {
    await mutateStory(storyId, (doc) {
      if (doc.status != StoryStatus.running) return doc;
      final pending = doc.requestLedger.any(
        (r) => r.status == 'pending' && r.runGeneration == doc.runGeneration,
      );
      return doc.copyWith(
        pauseAfterCurrent: pending,
        status: pending ? StoryStatus.running : StoryStatus.paused,
        pauseReason: StoryPauseReason.userPause,
      );
    });
  }

  Future<void> stopImmediately(String storyId, StoryPauseReason reason) async {
    try {
      await mutateStory(
        storyId,
        (doc) => doc.copyWith(
          status: doc.status == StoryStatus.completed
              ? StoryStatus.completed
              : StoryStatus.paused,
          pauseReason: reason,
          pauseAfterCurrent: false,
          runGeneration: doc.runGeneration + 1,
          requestLedger: _cancelPending(doc.requestLedger),
        ),
      );
    } on StoryMissingException {
      /* Already deleted is already stopped. */
    }
  }

  Future<void> failRequest(
    StoryOperationToken token, {
    StoryPauseReason reason = StoryPauseReason.requestError,
    String? errorCode,
  }) async {
    if (token.datasetEpoch != datasetEpoch) return;
    await _locked(token.storyId, (file, doc) async {
      if (doc == null ||
          doc.runGeneration != token.runGeneration ||
          doc.config.planVersion != token.planVersion) {
        return;
      }
      final matches = doc.requestLedger.where(
        (r) => r.requestId == token.requestId,
      );
      if (matches.isEmpty || matches.first.status != 'pending') return;
      await _writeNow(
        file,
        doc.copyWith(
          status: StoryStatus.paused,
          pauseReason: reason,
          pauseAfterCurrent: false,
          requestLedger: doc.requestLedger
              .map(
                (r) => r.requestId == token.requestId
                    ? r.copyWith(status: 'failed', errorCode: errorCode)
                    : r,
              )
              .toList(),
          revision: doc.revision + 1,
          updatedAt: DateTime.now(),
        ),
      );
    }, expectedEpoch: token.datasetEpoch);
    await _refreshIndexBestEffort(storyId: token.storyId);
  }

  Future<void> recordUsage(
    StoryOperationToken token, {
    int? inputTokens,
    int? outputTokens,
    int? totalTokens,
  }) async {
    if (token.datasetEpoch != datasetEpoch) return;
    var wrote = false;
    try {
      await _locked(token.storyId, (file, doc) async {
        if (doc == null) return;
        final records = doc.requestLedger
            .where((r) => r.requestId == token.requestId)
            .toList();
        if (records.isEmpty) return;
        final old = records.single;
        // Usage values are cumulative per request, never added more than once.
        final next = old.copyWith(
          totalTokens: totalTokens == null
              ? null
              : (old.providerTotalTokens == null ||
                        totalTokens > old.providerTotalTokens!
                    ? totalTokens
                    : old.providerTotalTokens),
          inputTokens: inputTokens == null
              ? null
              : (old.inputTokens == null || inputTokens > old.inputTokens!
                    ? inputTokens
                    : old.inputTokens),
          outputTokens: outputTokens == null
              ? null
              : (old.outputTokens == null || outputTokens > old.outputTokens!
                    ? outputTokens
                    : old.outputTokens),
        );
        await _writeNow(
          file,
          doc.copyWith(
            requestLedger: doc.requestLedger
                .map((r) => r.requestId == token.requestId ? next : r)
                .toList(),
            revision: doc.revision + 1,
            updatedAt: DateTime.now(),
          ),
        );
        wrote = true;
      }, expectedEpoch: token.datasetEpoch);
    } on StateError {
      if (token.datasetEpoch == datasetEpoch) rethrow;
    }
    if (wrote && token.datasetEpoch == datasetEpoch) {
      await _refreshIndexBestEffort(storyId: token.storyId);
    }
  }

  /// Ends a failed format attempt without changing scheduling state. Its single
  /// correction must reserve a new request and therefore consume fresh budget.
  Future<void> finishFailedAttempt(
    StoryOperationToken token, {
    String? errorCode,
  }) => _patchPending(
    token,
    (doc) => doc.copyWith(
      requestLedger: doc.requestLedger
          .map(
            (r) => r.requestId == token.requestId
                ? r.copyWith(status: 'failed', errorCode: errorCode)
                : r,
          )
          .toList(),
    ),
  );

  /// Keeps the reservation alive so an in-memory result can be saved again.
  Future<void> pauseForPendingSave(StoryOperationToken token) => _patchPending(
    token,
    (doc) => doc.copyWith(
      status: StoryStatus.paused,
      pauseReason: StoryPauseReason.storageError,
      pauseAfterCurrent: true,
    ),
  );

  Future<void> _patchPending(
    StoryOperationToken token,
    AutoStoryDocument Function(AutoStoryDocument) patch,
  ) async {
    if (token.datasetEpoch != datasetEpoch) return;
    try {
      await _locked(token.storyId, (file, doc) async {
        if (_fence(doc, token) != null) return;
        final next = patch(
          doc!,
        ).copyWith(revision: doc.revision + 1, updatedAt: DateTime.now());
        await _writeNow(file, next);
      }, expectedEpoch: token.datasetEpoch);
    } on StateError {
      if (token.datasetEpoch == datasetEpoch) rethrow;
    }
    await _refreshIndexBestEffort(storyId: token.storyId);
  }

  Future<AutoStoryDocument> addManualTurn(String storyId, String content) =>
      mutateStory(storyId, (doc) {
        if (doc.status != StoryStatus.paused ||
            doc.nextActor != 'B' ||
            doc.pauseAfterCurrent ||
            doc.requestLedger.any((r) => r.status == 'pending')) {
          throw StateError('Manual takeover requires paused B cursor');
        }
        final turn = StoryTurn(
          turnId: newStoryId(),
          ordinal: doc.turns.length,
          speakerId: 'B',
          content: content,
          source: StoryTurnSource.manual,
        );
        return doc.copyWith(
          turns: [...doc.turns, turn],
          runGeneration: doc.runGeneration + 1,
        );
      });

  Future<void> deleteStory(String storyId) async {
    await _locked(storyId, (file, doc) async {
      for (final path in [file.path, '${file.path}.tmp', '${file.path}.bak']) {
        final target = File(path);
        if (await target.exists()) await target.delete();
      }
    });
    await _refreshIndexBestEffort(storyId: storyId);
  }

  Future<AutoStoryDocument> editLastManualTurn(
    String storyId,
    String content,
  ) => mutateStory(storyId, (doc) {
    if ((doc.status != StoryStatus.paused &&
            doc.status != StoryStatus.completed) ||
        doc.turns.isEmpty ||
        doc.turns.last.source != StoryTurnSource.manual ||
        doc.turns.last.speakerId != 'B' ||
        doc.requestLedger.any((r) => r.status == 'pending')) {
      throw StateError(
        'Only the final manual B turn can be edited while paused',
      );
    }
    final old = doc.turns.last;
    final turn = StoryTurn(
      turnId: newStoryId(),
      ordinal: old.ordinal,
      speakerId: 'B',
      content: content,
      source: StoryTurnSource.manual,
      replacesTurnId: old.turnId,
    );
    return _replaceLastTurn(doc, turn);
  });

  // Both callers validate their own source and operation before replacing.
  AutoStoryDocument _replaceLastTurn(AutoStoryDocument doc, StoryTurn turn) {
    final old = doc.turns.last;
    final checkpoints = doc.directorCheckpoints
        .where((c) => c.coveredThroughOrdinal < old.ordinal)
        .toList();
    final retained = checkpoints.map((c) => c.checkpointId).toSet();
    final current = checkpoints
        .where((c) => c.planVersion == doc.config.planVersion)
        .lastOrNull;
    return _invalidateReplanSummary(
      doc.copyWith(
        turns: [...doc.turns.take(doc.turns.length - 1), turn],
        directorCheckpoints: checkpoints,
        currentCheckpointId: current?.checkpointId,
        clearCurrentCheckpoint: current == null,
        lockedFacts: doc.lockedFacts
            .where(
              (f) =>
                  !f.evidenceTurnIds.contains(old.turnId) &&
                  !f.evidence.any((e) => e.turnId == old.turnId),
            )
            .toList(),
        events: doc.events
            .where(
              (e) =>
                  e.sourceCheckpointId == null ||
                  retained.contains(e.sourceCheckpointId),
            )
            .toList(),
        status: StoryStatus.paused,
        goalStatus: 'pending',
        pauseAfterCurrent: false,
        runGeneration: doc.runGeneration + 1,
      ),
      turn.ordinal,
    );
  }

  AutoStoryDocument _invalidateReplanSummary(
    AutoStoryDocument doc,
    int replacedOrdinal,
  ) {
    if (doc.replanCoveredThroughOrdinal < replacedOrdinal) return doc;
    final checkpoint = doc.directorCheckpoints.lastOrNull;
    return AutoStoryDocument.fromJson({
      ...doc.toJson(),
      'replanSummary': checkpoint?.summary ?? '',
      'replanCoveredThroughOrdinal': checkpoint?.coveredThroughOrdinal ?? -1,
    });
  }

  Future<AutoStoryDocument> setFactPinned(
    String storyId,
    StoryFact fact, {
    required bool pinned,
  }) => mutateStory(storyId, (doc) {
    if (doc.status != StoryStatus.paused &&
        doc.status != StoryStatus.completed) {
      throw StateError('Pause before changing factual locks');
    }
    if (doc.requestLedger.any((request) => request.status == 'pending')) {
      throw StateError(
        'Finish or cancel pending requests before changing factual locks',
      );
    }
    final key = jsonEncode(fact.toJson());
    final alreadyPinned = doc.lockedFacts.any(
      (f) => jsonEncode(f.toJson()) == key,
    );
    if (alreadyPinned == pinned) return doc;
    final remaining = doc.lockedFacts
        .where((f) => jsonEncode(f.toJson()) != key)
        .toList();
    if (!pinned) {
      return doc.copyWith(
        lockedFacts: remaining,
        runGeneration: doc.runGeneration + 1,
      );
    }
    if (!(doc.currentCheckpoint?.confirmedFacts.any(
          (f) => jsonEncode(f.toJson()) == key,
        ) ??
        false)) {
      throw StateError('Only an existing verified fact can be pinned');
    }
    if (fact.evidence.isEmpty ||
        !fact.evidence
            .map((e) => e.turnId)
            .toSet()
            .containsAll(fact.evidenceTurnIds)) {
      throw StateError(
        'Pinning requires quoted evidence for every referenced turn',
      );
    }
    return doc.copyWith(
      lockedFacts: [...remaining, fact],
      runGeneration: doc.runGeneration + 1,
    );
  });

  Future<List<File>> _storyFiles() async {
    final directory = Directory(
      '${(await storage.appDataDirectory).path}/auto_stories',
    );
    if (!await directory.exists()) return [];
    final files = <String, File>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          RegExp(
            r'[/\\][A-Za-z0-9_-]{1,128}\.json(?:\.bak|\.tmp)?$',
          ).hasMatch(entity.path)) {
        final mainPath = entity.path.replaceFirst(RegExp(r'\.(bak|tmp)$'), '');
        files[mainPath] = File.fromUri(File(mainPath).uri);
      }
    }
    return files.values.toList();
  }

  Future<List<AutoStoryHeader>> listStories() async {
    if (_headers == null || _headersEpoch != datasetEpoch || indexNeedsRepair) {
      await _refreshIndexBestEffort();
    }
    return List.unmodifiable(_headers ?? []);
  }

  Future<void> repairIndex() => storage.jsonStore.runOperation(() async {
    final index = File(
      '${(await storage.appDataDirectory).path}/auto_story_index.json',
    );
    // Index first, then story locks. Incremental updates use the same order.
    await storage.jsonStore.synchronized(index, () async {
      final headers = <AutoStoryHeader>[];
      _unreadableStories.clear();
      for (final file in await _storyFiles()) {
        try {
          final doc = await storage.jsonStore.synchronized(
            file,
            () => _readNow(file),
          );
          if (doc != null) headers.add(AutoStoryHeader(doc));
        } on FormatException catch (error) {
          final name = file.path.replaceAll('\\', '/').split('/').last;
          _unreadableStories[name.substring(0, name.length - 5)] =
              error.message;
        }
      }
      headers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _headers = List.unmodifiable(headers);
      _headersEpoch = datasetEpoch;
      await storage.jsonStore.writeNow(
        index,
        headers.map((h) => h.toJson()).toList(),
      );
      indexNeedsRepair = false;
    });
  });

  Future<bool> _updateIndex(
    String storyId,
    int epoch,
  ) => storage.jsonStore.runOperation(() async {
    final index = File(
      '${(await storage.appDataDirectory).path}/auto_story_index.json',
    );
    return storage.jsonStore.synchronized(index, () async {
      if (!await index.exists()) return false;
      final dynamic decoded;
      try {
        decoded = jsonDecode(await index.readAsString());
      } on FormatException {
        return false;
      }
      if (decoded is! List) return false;
      final rows = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (final row in decoded) {
        if (row is! Map<String, dynamic> ||
            row['id'] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(row['id'] as String) ||
            !ids.add(row['id'] as String) ||
            row['title'] is! String ||
            row['actors'] is! List ||
            (row['actors'] as List).length != 2 ||
            !(row['actors'] as List).every(
              (actor) =>
                  actor is Map<String, dynamic> &&
                  (actor['actorId'] == 'A' || actor['actorId'] == 'B') &&
                  actor['name'] is String &&
                  (actor['sourceId'] == null || actor['sourceId'] is String) &&
                  (actor['avatarRelativePath'] == null ||
                      actor['avatarRelativePath'] is String) &&
                  actor['lockedSource'] is bool,
            ) ||
            row['status'] is! String ||
            !StoryStatus.values.any((s) => s.name == row['status']) ||
            (row['pauseReason'] != null &&
                !StoryPauseReason.values.any(
                  (r) => r.name == row['pauseReason'],
                )) ||
            row['completedRounds'] is! int ||
            row['plannedRounds'] is! int ||
            row['stageIndex'] is! int ||
            row['privacyRequired'] is! bool ||
            row['updatedAt'] is! String ||
            DateTime.tryParse(row['updatedAt'] as String) == null) {
          return false;
        }
        rows.add(row);
      }
      final file = await _file(storyId);
      final AutoStoryDocument? doc;
      try {
        doc = await storage.jsonStore.synchronized(file, () => _readNow(file));
      } on FormatException {
        return false;
      }
      rows.removeWhere((row) => row['id'] == storyId);
      if (doc != null) rows.add(AutoStoryHeader(doc).toJson());
      rows.sort(
        (a, b) => DateTime.parse(
          b['updatedAt'] as String,
        ).compareTo(DateTime.parse(a['updatedAt'] as String)),
      );
      await storage.jsonStore.writeNow(index, rows);
      if (_headers != null && _headersEpoch == epoch) {
        final peers = _headers!.where((h) => h.id != storyId).toList();
        final cachedPeers = {for (final header in peers) header.id: header};
        final diskPeers = rows.where((row) => row['id'] != storyId).toList();
        if (cachedPeers.length != diskPeers.length ||
            diskPeers.any(
              (row) =>
                  cachedPeers[row['id']] == null ||
                  jsonEncode(cachedPeers[row['id']]!.toJson()) !=
                      jsonEncode(row),
            )) {
          // Another store changed the index; listStories must rescan.
          _headers = null;
        } else {
          if (doc != null) peers.add(AutoStoryHeader(doc));
          peers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          _headers = List.unmodifiable(peers);
        }
      }
      indexNeedsRepair = false;
      return true;
    });
  }, expectedEpoch: epoch);

  Future<void> _refreshIndexBestEffort({String? storyId}) async {
    final epoch = datasetEpoch;
    try {
      if (storyId == null ||
          _headers == null ||
          _headersEpoch != epoch ||
          indexNeedsRepair ||
          !await _updateIndex(storyId, epoch)) {
        await repairIndex();
      }
    } on FileSystemException {
      indexNeedsRepair = true;
    } on StoryStorageException {
      indexNeedsRepair = true;
    } on StateError {
      if (epoch == datasetEpoch) rethrow;
    }
  }

  Future<void> recoverInterruptedStories() async {
    if (_recoveredEpoch == datasetEpoch) return;
    await storage.jsonStore.runOperation(() async {
      final epoch = datasetEpoch;
      for (final file in await _storyFiles()) {
        try {
          await storage.jsonStore.synchronized(file, () async {
            final doc = await _readNow(file);
            if (doc == null) return;
            if (doc.status == StoryStatus.running ||
                doc.requestLedger.any((r) => r.status == 'pending')) {
              await _writeNow(
                file,
                doc.copyWith(
                  status: StoryStatus.paused,
                  pauseReason: StoryPauseReason.interruptedRestart,
                  pauseAfterCurrent: false,
                  runGeneration: doc.runGeneration + 1,
                  requestLedger: _cancelPending(
                    doc.requestLedger,
                    status: 'unknown',
                  ),
                  revision: doc.revision + 1,
                  updatedAt: DateTime.now(),
                ),
              );
            }
          });
        } on FormatException {
          /* Preserve evidence; corrupt stories cannot run. */
        }
      }
      _recoveredEpoch = epoch;
    });
    await _refreshIndexBestEffort();
  }
}
