import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/auto_story.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';
import '../local_storage_service.dart';
import 'auto_story_actor_service.dart';
import 'auto_story_budget.dart';
import 'auto_story_director_service.dart';
import 'auto_story_prompt_builder.dart';
import 'auto_story_store.dart';
import 'auto_story_validator.dart';

enum AutoStoryRunPhase {
  idle,
  planning,
  actorA,
  actorB,
  director,
  saving,
  pausing,
}

class AutoStoryDraft {
  const AutoStoryDraft({
    required this.speakerId,
    required this.content,
    this.reasoningContent = '',
  });
  final String speakerId;
  final String content;
  final String reasoningContent;
}

class _Session {
  _Session(this.epoch);
  final int epoch;
  final cancelled = Completer<void>();
  AiCancelToken? token;
  StoryOperationToken? reservation;
  bool pause = false;
  Timer? delay;
  Completer<void>? delayDone;
  void cancelDelay() {
    delay?.cancel();
    if (delayDone?.isCompleted == false) delayDone!.complete();
  }

  void cancel() {
    token?.cancel();
    cancelDelay();
    if (!cancelled.isCompleted) cancelled.complete();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _PendingSave {
  const _PendingSave(this.token, this.commit);
  final StoryOperationToken token;
  final Future<CommitResult> Function() commit;
}

class _SaveFailed implements Exception {
  const _SaveFailed();
}

/// A storage-scoped lease owns all requests. No UI lifecycle can auto-resume it.
class AutoStoryRunController extends ChangeNotifier {
  AutoStoryRunController({
    required this.storage,
    required AiGateway aiService,
    required this.storyId,
    this.authorize,
  }) : _actor = AutoStoryActorService(aiService),
       _director = AutoStoryDirectorService(aiService) {
    storage.jsonStore.datasetEpochNotifier.addListener(_datasetChanged);
  }
  final LocalStorageService storage;
  final String storyId;
  final Future<bool> Function()? authorize;
  final AutoStoryActorService _actor;
  final AutoStoryDirectorService _director;
  static final _leases = Expando<_Session>();
  AutoStoryStore get _store => storage.autoStories;
  AutoStoryDocument? story;
  String? error;
  AutoStoryRunPhase phase = AutoStoryRunPhase.idle;
  final draft = ValueNotifier<AutoStoryDraft?>(null);
  _Session? _session;
  _PendingSave? _pending;
  bool _disposed = false;
  bool get isBusy => _session != null;
  bool get pendingSave => _pending != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(_Session session) =>
      !_disposed &&
      identical(_session, session) &&
      session.epoch == _store.datasetEpoch &&
      !session.cancelled.isCompleted;
  void _check(_Session session) {
    if (!_valid(session)) throw const _Cancelled();
  }

  Future<bool> _allowed() async {
    if (authorize != null) return authorize!();
    return !(await _store.loadStory(storyId)).privacyRequired;
  }

  Future<void> load() async {
    try {
      if (!await _allowed()) {
        story = null;
        error = '故事尚未解锁。';
        _notify();
        return;
      }
      story = await _store.loadStory(storyId);
      error = null;
      _notify();
    } catch (e) {
      error = e.toString();
      _notify();
    }
  }

  Future<void> _reload(_Session session) async {
    final doc = await _store.loadStory(storyId);
    _check(session);
    story = doc;
    _notify();
  }

  Future<T> _race<T>(_Session session, Future<T> operation) => Future.any([
    operation,
    session.cancelled.future.then<T>((_) => throw const _Cancelled()),
  ]);
  Future<void> _launch(
    Future<void> Function(_Session) action, {
    bool allowPending = false,
  }) async {
    if (_disposed || _session != null || (!allowPending && pendingSave)) return;
    if (_leases[storage.jsonStore] != null) {
      error = '另一个故事正在生成，请先暂停。';
      _notify();
      return;
    }
    final session = _Session(_store.datasetEpoch);
    _session = session;
    _leases[storage.jsonStore] = session;
    error = null;
    _notify();
    try {
      if (!await _allowed()) throw StateError('故事尚未解锁。');
      _check(session);
      await _reload(session);
      await action(session);
    } on _Cancelled {
      /* An older generation no longer owns presentation. */
    } on _SaveFailed {
      /* Pending complete result is retained for retrySave. */
    } catch (e) {
      if (_valid(session)) {
        error = e.toString();
        final reason = e is StoryBudgetException
            ? e.reason
            : StoryPauseReason.requestError;
        try {
          if (session.reservation != null) {
            await _store.failRequest(
              session.reservation!,
              reason: reason,
              errorCode: e.runtimeType.toString(),
            );
          } else {
            await _store.stopImmediately(storyId, reason);
          }
          await _reload(session);
        } catch (_) {
          /* Keep actionable original error even when disk is unavailable. */
        }
      }
    } finally {
      if (identical(_leases[storage.jsonStore], session)) {
        _leases[storage.jsonStore] = null;
      }
      if (identical(_session, session)) {
        _session = null;
        session.cancelDelay();
        phase = AutoStoryRunPhase.idle;
        if (!_disposed) draft.value = null;
        _notify();
      }
    }
  }

  Future<void> generatePlan() => _launch((session) async {
    if (story!.status == StoryStatus.running) throw StateError('请先暂停。');
    await _plan(session);
  });
  Future<void> resume({bool singleRound = false}) => _launch((session) async {
    if (story!.status == StoryStatus.completed) return;
    if (story!.goalStatus == 'reached') {
      final completed = await _store.mutateStory(storyId, (doc) {
        final checkpoint = doc.currentCheckpoint;
        if (doc.goalStatus != 'reached' ||
            checkpoint == null ||
            checkpoint.planVersion != doc.config.planVersion ||
            checkpoint.coveredThroughOrdinal != doc.turns.length - 1) {
          throw StateError('已达成结局的证据不完整或已失效，请检查大纲与正文后再继续。');
        }
        // The model additionally validates complete rounds, final stage and
        // exact current goal evidence before restoring this presentation state.
        return doc.copyWith(
          status: StoryStatus.completed,
          clearPauseReason: true,
          pauseAfterCurrent: false,
        );
      });
      _check(session);
      story = completed;
      _notify();
      return;
    }
    story = await _store.beginRun(storyId);
    _check(session);
    _notify();
    if (story!.plan.isEmpty) await _plan(session);
    final stopAt = singleRound ? story!.completedRounds + 1 : null;
    while (_valid(session)) {
      await _reload(session);
      if (session.pause || story!.status != StoryStatus.running) break;
      if (AutoStoryBudget.shouldReview(story!)) {
        await _review(session);
        await _reload(session);
        if (session.pause || story!.status != StoryStatus.running) break;
      }
      if (story!.turns.length >= story!.config.plannedRounds * 2) {
        await _store.stopImmediately(storyId, StoryPauseReason.lengthLimit);
        await _reload(session);
        break;
      }
      if (stopAt != null && story!.completedRounds >= stopAt) {
        await _store.requestPause(storyId);
        await _reload(session);
        break;
      }
      await _actorTurn(session);
      if (session.pause || story!.status != StoryStatus.running) break;
      final atBoundary =
          (stopAt != null && story!.completedRounds >= stopAt) ||
          story!.turns.length >= story!.config.plannedRounds * 2 ||
          AutoStoryBudget.shouldReview(story!);
      if (!atBoundary && story!.config.interTurnDelayMs > 0) {
        session.delayDone = Completer<void>();
        session.delay = Timer(
          Duration(milliseconds: story!.config.interTurnDelayMs),
          () => session.delayDone!.complete(),
        );
        await _race(session, session.delayDone!.future);
        _check(session);
      }
    }
    if (_valid(session) &&
        session.pause &&
        story!.status == StoryStatus.running) {
      await _store.requestPause(storyId);
      await _reload(session);
    }
  });
  Future<AiEndpointConfig> _endpoint(_Session session, String actorId) async {
    if (!await _allowed()) throw StateError('故事已上锁或不再可见。');
    _check(session);
    final actor = story!.actors.singleWhere((a) => a.actorId == actorId);
    final config = await storage.loadApiConfig();
    _check(session);
    final endpoint = config.endpointById(actor.endpointId);
    if (endpoint == null ||
        endpoint.validationError != null ||
        actor.model.trim().isEmpty) {
      throw AiException('演员 $actorId 的 API 或模型不可用，请重新配置。');
    }
    return endpoint.copyWith(model: actor.model);
  }

  Future<void> _usage(
    StoryOperationToken token,
    AiUsage? usage,
    AiEndpointConfig endpoint,
    List<Map<String, String>> messages,
    String requestType,
  ) async {
    if (usage == null) return;
    final onlyTotal =
        usage.totalTokens > 0 &&
        usage.promptTokens == 0 &&
        usage.completionTokens == 0;
    try {
      await _store.recordUsage(
        token,
        inputTokens: onlyTotal ? null : usage.promptTokens,
        outputTokens: onlyTotal ? null : usage.completionTokens,
        totalTokens: usage.totalTokens,
      );
      await storage.recordAiUsage(
        requestType: requestType,
        model: endpoint.model,
        usage: usage,
        messages: messages,
        summaryUpdated: requestType == 'autoStoryReview',
      );
    } catch (_) {
      /* Usage failures must not discard a complete actor result. */
    }
  }

  Future<void> _commit(
    _Session session,
    StoryOperationToken token,
    Future<CommitResult> Function() commit,
  ) async {
    _check(session);
    phase = AutoStoryRunPhase.saving;
    _notify();
    try {
      final result = await commit();
      _check(session);
      if (result == CommitResult.stale || result == CommitResult.missing) {
        throw const _Cancelled();
      }
      session.reservation = null;
      await _reload(session);
    } on StoryStorageException catch (e) {
      _check(session);
      _pending = _PendingSave(token, commit);
      session.pause = true;
      error = '这条内容尚未保存，重试保存：$e';
      try {
        await _store.pauseForPendingSave(token);
      } catch (_) {
        /* Disk may still be unavailable. */
      }
      _notify();
      throw const _SaveFailed();
    }
  }

  Future<void> _checkReservedContext(
    _Session session,
    StoryOperationToken token,
    AutoStoryDocument snapshot, {
    bool replaceLast = false,
  }) async {
    _check(session);
    final ordinal = snapshot.nextOrdinal - (replaceLast ? 1 : 0);
    if (token.runGeneration == snapshot.runGeneration &&
        token.planVersion == snapshot.config.planVersion &&
        token.expectedNextOrdinal == ordinal &&
        token.expectedSpeaker == (ordinal.isEven ? 'A' : 'B')) {
      return;
    }
    await _store.finishFailedAttempt(token, errorCode: 'staleRequestContext');
    session.reservation = null;
    error = '故事配置或正文已改变，已取消旧上下文请求，请重新操作。';
    await _reload(session);
    throw const _Cancelled();
  }

  Future<void> _actorTurn(_Session session, {bool replaceLast = false}) async {
    final original = story!;
    final actorId = replaceLast
        ? original.turns.last.speakerId
        : original.nextActor;
    var context = original;
    if (replaceLast) {
      final kept = original.directorCheckpoints
          .where((c) => c.coveredThroughOrdinal < original.turns.length - 1)
          .toList();
      final remaining = original.turns.take(original.turns.length - 1).toList();
      final keptIds = kept.map((c) => c.checkpointId).toSet();
      final current = kept
          .where((c) => c.planVersion == original.config.planVersion)
          .lastOrNull;
      final replacedId = original.turns.last.turnId;
      final raw = original.toJson();
      final losesSummary =
          (raw['replanCoveredThroughOrdinal'] as int? ?? -1) >=
          remaining.length;
      final start = (raw['replanStartRound'] as int? ?? 0).clamp(
        0,
        (remaining.length + 1) ~/ 2,
      );
      // This is only the request view. The authoritative old turn remains intact
      // until commitTurn atomically replaces it and invalidates dependents.
      context = AutoStoryDocument.fromJson({
        ...raw,
        'turns': remaining.map((t) => t.toJson()).toList(),
        'nextActor': remaining.length.isEven ? 'A' : 'B',
        'completedRounds': remaining.length ~/ 2,
        'directorCheckpoints': kept.map((c) => c.toJson()).toList(),
        'currentCheckpointId': current?.checkpointId,
        'events': original.events
            .where(
              (e) =>
                  e.effectiveAfterOrdinal < remaining.length &&
                  (e.sourceCheckpointId == null ||
                      keptIds.contains(e.sourceCheckpointId)),
            )
            .map((e) => e.toJson())
            .toList(),
        'lockedFacts': original.lockedFacts
            .where(
              (f) =>
                  !f.evidenceTurnIds.contains(replacedId) &&
                  !f.evidence.any((e) => e.turnId == replacedId),
            )
            .map((f) => f.toJson())
            .toList(),
        'goalStatus': 'pending',
        'status': 'paused',
        'replanSummary': losesSummary ? '' : (raw['replanSummary'] ?? ''),
        'replanCoveredThroughOrdinal': losesSummary
            ? -1
            : (raw['replanCoveredThroughOrdinal'] ?? -1),
        'replanStartRound': start,
      });
    }
    final actor = context.actors.singleWhere((a) => a.actorId == actorId);
    final other = context.actors.singleWhere((a) => a.actorId != actorId);
    for (var attempt = 0; attempt < 2; attempt++) {
      _check(session);
      if (session.pause) return;
      final endpoint = await _endpoint(session, actorId);
      if (session.pause) return;
      final purpose = attempt > 0
          ? RequestPurpose.repair
          : replaceLast
          ? RequestPurpose.regenerate
          : actorId == 'A'
          ? RequestPurpose.actorA
          : RequestPurpose.actorB;
      final token = await _store.reserveRequest(
        storyId,
        purpose,
        replaceLast: replaceLast,
      );
      session.reservation = token;
      _check(session);
      await _checkReservedContext(
        session,
        token,
        original,
        replaceLast: replaceLast,
      );
      final messages = AutoStoryPromptBuilder.buildActor(
        context,
        actorId: actorId,
        repair: attempt > 0,
      );
      final showReasoning = (await storage.loadSettings()).showReasoningContent;
      _check(session);
      if (session.pause) {
        await _store.finishFailedAttempt(token, errorCode: 'pausedBeforeSend');
        session.reservation = null;
        await _store.requestPause(storyId);
        await _reload(session);
        return;
      }
      phase = actorId == 'A'
          ? AutoStoryRunPhase.actorA
          : AutoStoryRunPhase.actorB;
      _notify();
      final cancel = AiCancelToken();
      session.token = cancel;
      AiUsage? usage;
      AutoStoryActorResult result;
      try {
        result = await _race(
          session,
          _actor.generate(
            endpoint: endpoint,
            messages: messages,
            actorName: actor.name,
            otherActorName: other.name,
            actorId: actorId,
            cancelToken: cancel,
            includeReasoning: showReasoning,
            onUsage: (value) => usage = _mergeUsage(usage, value),
            onDraft: (content, reasoning) {
              if (_valid(session)) {
                draft.value = AutoStoryDraft(
                  speakerId: actorId,
                  content: content,
                  reasoningContent: reasoning,
                );
              }
            },
          ),
        );
      } on FormatException {
        if (attempt == 0 && _valid(session) && !session.pause) {
          await _store.finishFailedAttempt(
            token,
            errorCode: 'invalidActorOutput',
          );
          session.reservation = null;
          continue;
        }
        rethrow;
      } finally {
        await _usage(
          token,
          usage,
          endpoint,
          messages,
          attempt > 0
              ? 'autoStoryRepair'
              : actorId == 'A'
              ? 'autoStoryActorA'
              : 'autoStoryActorB',
        );
      }
      _check(session);
      final prior = context.turns
          .where((t) => t.speakerId == actorId)
          .lastOrNull;
      if (prior != null &&
          _normalize(prior.content) == _normalize(result.content)) {
        throw const StoryBudgetException(StoryPauseReason.stagnation);
      }
      final turn = StoryTurn(
        turnId: newStoryId(),
        ordinal: token.expectedNextOrdinal,
        speakerId: actorId,
        content: result.content,
        reasoningContent: result.reasoningContent,
        source: StoryTurnSource.ai,
        endpointId: endpoint.id,
        model: endpoint.model,
        requestId: token.requestId,
        replacesTurnId: replaceLast ? original.turns.last.turnId : null,
      );
      await _commit(session, token, () => _store.commitTurn(token, turn));
      if (_valid(session)) draft.value = null;
      return;
    }
  }

  Future<void> _plan(_Session session) async {
    phase = AutoStoryRunPhase.planning;
    _notify();
    await _directorCall(
      session,
      purpose: story!.turns.isEmpty
          ? RequestPurpose.plan
          : RequestPurpose.replan,
      messages: (repair) =>
          AutoStoryPromptBuilder.buildPlan(story!, repair: repair),
      parse: (raw) {
        final plan = AutoStoryDirectorService.parsePlan(
          raw,
          plannedRounds: story!.config.plannedRounds,
          idPrefix: 'plan_${story!.config.planVersion}',
        );
        final remaining =
            story!.config.plannedRounds - (story!.turns.length + 1) ~/ 2;
        if (plan.fold<int>(0, (sum, stage) => sum + stage.minRounds) >
            remaining) {
          throw const FormatException('剩余完整轮数不足以满足新大纲的最少轮数，请增加篇幅或修订大纲。');
        }
        return DirectorResult(plan: plan);
      },
    );
  }

  Future<void> _review(_Session session) async {
    do {
      final snapshot = story!;
      final batch = AutoStoryPromptBuilder.reviewBatch(snapshot);
      final full = batch.coveredThroughOrdinal == snapshot.turns.length - 1;
      final key = AutoStoryBudget.checkKey(snapshot);
      phase = AutoStoryRunPhase.director;
      _notify();
      await _directorCall(
        session,
        purpose: RequestPurpose.review,
        messages: (repair) =>
            AutoStoryPromptBuilder.buildReview(snapshot, batch, repair: repair),
        parse: (raw) => AutoStoryDirectorService.parseReview(
          raw,
          story: snapshot,
          coveredThroughOrdinal: batch.coveredThroughOrdinal,
          checkKey: full ? key : '$key:batch:${batch.coveredThroughOrdinal}',
        ),
      );
      if (full || session.pause || story!.status == StoryStatus.completed) {
        break;
      }
    } while (_valid(session));
    if (!session.pause && AutoStoryBudget.shouldPauseForStagnation(story!)) {
      throw const StoryBudgetException(StoryPauseReason.stagnation);
    }
  }

  Future<void> _directorCall(
    _Session session, {
    required RequestPurpose purpose,
    required List<Map<String, String>> Function(bool repair) messages,
    required DirectorResult Function(String) parse,
  }) async {
    final snapshot = story!;
    for (var attempt = 0; attempt < 2; attempt++) {
      _check(session);
      if (session.pause) return;
      final endpoint = await _endpoint(session, 'A');
      if (session.pause) return;
      final request = messages(attempt > 0);
      final token = await _store.reserveRequest(
        storyId,
        attempt > 0 ? RequestPurpose.repair : purpose,
      );
      session.reservation = token;
      _check(session);
      await _checkReservedContext(session, token, snapshot);
      final cancel = AiCancelToken();
      session.token = cancel;
      AiUsage? usage;
      DirectorResult result;
      try {
        final raw = await _race(
          session,
          _director.request(
            endpoint: endpoint,
            messages: request,
            cancelToken: cancel,
            onUsage: (value) => usage = _mergeUsage(usage, value),
          ),
        );
        _check(session);
        result = parse(raw);
      } on FormatException {
        if (attempt == 0 && _valid(session) && !session.pause) {
          await _store.finishFailedAttempt(
            token,
            errorCode: 'invalidDirectorOutput',
          );
          session.reservation = null;
          continue;
        }
        rethrow;
      } finally {
        await _usage(
          token,
          usage,
          endpoint,
          request,
          attempt > 0
              ? 'autoStoryRepair'
              : purpose == RequestPurpose.review
              ? 'autoStoryReview'
              : 'autoStoryPlan',
        );
      }
      await _commit(session, token, () => _store.commitDirector(token, result));
      return;
    }
  }

  Future<void> requestPause() async {
    final session = _session;
    if (session != null) {
      session.pause = true;
      session.cancelDelay();
      phase = AutoStoryRunPhase.pausing;
      _notify();
    }
    try {
      await _store.requestPause(storyId);
      if (session == null || _valid(session)) {
        story = await _store.loadStory(storyId);
        _notify();
      }
    } catch (e) {
      error = e.toString();
      _notify();
    }
  }

  Future<void> stopImmediately([
    StoryPauseReason reason = StoryPauseReason.userStop,
  ]) async {
    final session = _session;
    session?.cancel();
    _session = null;
    if (session != null && identical(_leases[storage.jsonStore], session)) {
      _leases[storage.jsonStore] = null;
    }
    _pending = null;
    phase = AutoStoryRunPhase.idle;
    if (!_disposed) draft.value = null;
    _notify();
    try {
      await _store.stopImmediately(storyId, reason);
      if (!_disposed && _session == null) {
        story = await _store.loadStory(storyId);
        _notify();
      }
    } catch (e) {
      if (!_disposed) {
        error = e.toString();
        _notify();
      }
    }
  }

  Future<void> retrySave() => _launch((session) async {
    final pending = _pending;
    if (pending == null) return;
    try {
      await _store.pauseForPendingSave(pending.token);
      final result = await pending.commit();
      _check(session);
      if (result == CommitResult.applied ||
          result == CommitResult.alreadyCommitted) {
        _pending = null;
        error = null;
        await _reload(session);
      } else {
        _pending = null;
        throw StateError('保存对象已更改，请重新读取故事。');
      }
    } on StoryStorageException catch (e) {
      error = '保存仍未成功，请重试：$e';
      _notify();
      throw const _SaveFailed();
    }
  }, allowPending: true);
  Future<void> regenerateLast() => _launch((session) async {
    if (![StoryStatus.paused, StoryStatus.completed].contains(story!.status) ||
        story!.turns.isEmpty ||
        story!.turns.last.source != StoryTurnSource.ai) {
      throw StateError('只能重新生成暂停故事最后一条AI正文。');
    }
    await _actorTurn(session, replaceLast: true);
  });
  Future<void> takeoverB(String text) => _launch((session) async {
    final actor = story!.actors[1];
    final content = AutoStoryValidator.actorContent(
      text,
      actorName: actor.name,
      otherActorName: story!.actors[0].name,
      actorId: 'B',
    );
    story = await _store.addManualTurn(storyId, content);
    _check(session);
    _notify();
  });
  Future<void> addInstruction(String text, {String scope = 'checkpoint'}) =>
      _launch((session) async {
        if (story!.status != StoryStatus.paused ||
            text.trim().isEmpty ||
            text.runes.length > 2000 ||
            ![
              'checkpoint',
              'nextTurn',
              'round',
              'story',
              'stage',
            ].contains(scope)) {
          throw StateError('导演指令须在暂停时填写，最多2000字符。');
        }
        story = await _store.mutateStory(
          storyId,
          (doc) => doc.copyWith(
            events: [
              ...doc.events,
              StoryEvent(
                eventId: newStoryId(),
                kind: 'directorInstruction',
                content: text.trim(),
                effectiveAfterOrdinal: doc.turns.length - 1,
                scope: scope,
                status: 'pending',
              ),
            ],
          ),
        );
        _check(session);
        _notify();
      });
  void _datasetChanged() {
    final session = _session;
    session?.cancel();
    if (session != null && identical(_leases[storage.jsonStore], session)) {
      _leases[storage.jsonStore] = null;
    }
    _session = null;
    _pending = null;
    story = null;
    phase = AutoStoryRunPhase.idle;
    if (!_disposed) draft.value = null;
    error = '数据集已更换，请重新读取故事。';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    storage.jsonStore.datasetEpochNotifier.removeListener(_datasetChanged);
    final session = _session;
    session?.cancel();
    if (session != null && identical(_leases[storage.jsonStore], session)) {
      _leases[storage.jsonStore] = null;
    }
    _session = null;
    draft.dispose();
    super.dispose();
  }
}

String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), '').trim();
AiUsage _mergeUsage(AiUsage? previous, AiUsage value) {
  if (previous == null) return value;
  int greater(int a, int b) => a > b ? a : b;
  return AiUsage(
    promptTokens: greater(previous.promptTokens, value.promptTokens),
    completionTokens: greater(
      previous.completionTokens,
      value.completionTokens,
    ),
    totalTokens: greater(previous.totalTokens, value.totalTokens),
    cacheHitTokens: greater(previous.cacheHitTokens, value.cacheHitTokens),
    cacheMissTokens: greater(previous.cacheMissTokens, value.cacheMissTokens),
    supportsCacheStats: previous.supportsCacheStats || value.supportsCacheStats,
  );
}
