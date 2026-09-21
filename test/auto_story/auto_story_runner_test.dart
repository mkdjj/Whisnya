import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_response.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/auto_story/auto_story_run_controller.dart';
import 'package:whisnya/services/auto_story/auto_story_export.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'auto_story_prompt_test.dart' show promptStory, promptTurn;
import 'auto_story_store_test.dart' show FailingStoryJsonStore;

class RunnerStorage extends LocalStorageService {
  RunnerStorage(Directory dir, FailingStoryJsonStore json)
    : super(appDataDirectory: dir, jsonStore: json);
  Completer<void>? endpointGate;
  Completer<void>? endpointStarted;
  @override
  Future<ApiConfig> loadApiConfig() async {
    if (endpointStarted?.isCompleted == false) endpointStarted!.complete();
    if (endpointGate != null) await endpointGate!.future;
    return ApiConfig(
      endpoints: [
        AiEndpointConfig(
          id: 'e',
          name: 'test',
          apiKey: 'key',
          baseUrl: 'https://example.invalid',
          model: 'm',
          enabled: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );
  }
}

class ActorCall {
  ActorCall(this.request, this.token);
  final AiRequest request;
  final AiCancelToken? token;
  // Closed by complete() in each owning test.
  // ignore: close_sinks
  final stream = StreamController<AiResponseDelta>();
  Future<void> complete(String content) async {
    stream.add(AiResponseDelta(contentDelta: content));
    await stream.close();
  }
}

class RunnerGateway implements AiGateway, StructuredAiGateway {
  final calls = <ActorCall>[];
  final waiters = <int, Completer<ActorCall>>{};
  final directors = <Completer<AiResponse>>[];
  final directorWaiters = <int, Completer<Completer<AiResponse>>>{};
  Future<Completer<AiResponse>> director(int index) => index < directors.length
      ? Future.value(directors[index])
      : directorWaiters
            .putIfAbsent(index, () => Completer<Completer<AiResponse>>())
            .future;
  @override
  Future<AiResponse> sendResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) {
    final response = Completer<AiResponse>();
    directors.add(response);
    directorWaiters.remove(directors.length - 1)?.complete(response);
    return response.future;
  }

  Future<ActorCall> call(int index) => index < calls.length
      ? Future.value(calls[index])
      : waiters.putIfAbsent(index, () => Completer<ActorCall>()).future;
  @override
  Stream<AiResponseDelta> streamResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) {
    final call = ActorCall(request, cancelToken);
    calls.add(call);
    waiters.remove(calls.length - 1)?.complete(call);
    return call.stream.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FailingStoryJsonStore json;
  late RunnerStorage storage;
  late RunnerGateway gateway;
  late AutoStoryRunController runner;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('story-runner-');
    json = FailingStoryJsonStore();
    storage = RunnerStorage(directory, json);
    gateway = RunnerGateway();
    await storage.autoStories.createStory(
      promptStory().copyWith(status: StoryStatus.draft),
    );
    await storage.autoStories.mutateStory(
      'story',
      (doc) => doc.copyWith(status: StoryStatus.ready),
    );
    runner = AutoStoryRunController(
      storage: storage,
      aiService: gateway,
      storyId: 'story',
    );
    await runner.load();
  });
  tearDown(() async {
    json.failStory = false;
    await runner.stopImmediately();
    runner.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'regeneration rejects old context when paused config changes during endpoint lookup',
    () async {
      await storage.autoStories.mutateStory(
        'story',
        (doc) =>
            doc.copyWith(status: StoryStatus.paused, turns: [promptTurn(0)]),
      );
      storage.endpointStarted = Completer<void>();
      storage.endpointGate = Completer<void>();
      final redo = runner.regenerateLast();
      await storage.endpointStarted!.future;
      await storage.autoStories.mutateStory(
        'story',
        (doc) => doc.copyWith(
          config: doc.config.copyWith(style: 'edited while awaiting endpoint'),
        ),
      );
      storage.endpointGate!.complete();
      final outcome = await Future.any([
        redo.then((_) => 'blocked'),
        gateway.call(0).then((_) => 'stale HTTP'),
      ]);
      if (outcome == 'stale HTTP') {
        await runner.stopImmediately();
        await gateway.calls[0].complete('stale context result');
        await redo;
      }
      expect(outcome, 'blocked');
      expect(gateway.calls, isEmpty);
      final saved = await storage.autoStories.loadStory('story');
      expect(saved.turns.single.content, '正文0');
      expect(saved.config.style, 'edited while awaiting endpoint');
      expect(saved.requestLedger.single.status, 'failed');
    },
  );
  test(
    'director rejects old plan context when editor changes config during endpoint lookup',
    () async {
      await storage.autoStories.mutateStory(
        'story',
        (doc) => doc.copyWith(status: StoryStatus.paused),
      );
      storage.endpointStarted = Completer<void>();
      storage.endpointGate = Completer<void>();
      final plan = runner.generatePlan();
      await storage.endpointStarted!.future;
      await storage.autoStories.mutateStory(
        'story',
        (doc) => doc.copyWith(
          config: doc.config.copyWith(style: 'new director style'),
        ),
      );
      storage.endpointGate!.complete();
      final outcome = await Future.any([
        plan.then((_) => 'blocked'),
        gateway.director(0).then((_) => 'stale HTTP'),
      ]);
      if (outcome == 'stale HTTP') {
        await runner.stopImmediately();
        gateway.directors[0].complete(
          const AiResponse(content: '{}', usage: AiUsage()),
        );
        await plan;
      }
      expect(outcome, 'blocked');
      expect(gateway.directors, isEmpty);
      expect(
        (await storage.autoStories.loadStory('story')).config.style,
        'new director style',
      );
    },
  );
  test(
    'historical plan checkpoints do not count as stagnation in the new plan',
    () async {
      final turns = List.generate(10, (i) => promptTurn(i));
      final history = [
        DirectorCheckpoint(
          checkpointId: 'old0',
          coveredThroughOrdinal: 1,
          coveredTurnIdsHash: storyTurnsHash(turns.take(2).toList()),
          planVersion: 1,
          stageIndex: 0,
          checkKey: 'old-round1',
        ),
        DirectorCheckpoint(
          checkpointId: 'old1',
          coveredThroughOrdinal: 3,
          coveredTurnIdsHash: storyTurnsHash(turns.take(4).toList()),
          planVersion: 1,
          stageIndex: 0,
          checkKey: 'old-round2',
        ),
      ];
      await storage.autoStories.mutateStory(
        'story',
        (doc) => doc.copyWith(
          status: StoryStatus.paused,
          turns: turns,
          directorCheckpoints: history,
          config: doc.config.copyWith(style: 'new plan'),
          clearCurrentCheckpoint: true,
        ),
      );
      final run = runner.resume();
      (await gateway.director(0)).complete(
        AiResponse(
          content: jsonEncode({
            'coveredThroughOrdinal': 9,
            'summary': '既有事实。',
            'facts': <Object>[],
            'stageSatisfied': false,
            'criteriaEvidence': <Object>[],
            'nextBeat': '查看店内线索',
            'pacing': 'normal',
            'sceneTransition': null,
            'goalReached': false,
            'goalEvidence': <Object>[],
          }),
          usage: const AiUsage(),
        ),
      );
      final outcome = await Future.any([
        gateway.call(0).then((_) => 'actor'),
        run.then((_) => 'stopped'),
      ]);
      if (outcome == 'actor') {
        await runner.requestPause();
        await gateway.calls[0].complete('新计划的第一次互动');
        await run;
      }
      expect(outcome, 'actor', reason: runner.error);
      expect(runner.story!.pauseReason, StoryPauseReason.userPause);
    },
  );
  test(
    'A finishes and saves before B reads it; a single round stops exactly after B',
    () async {
      final run = runner.resume(singleRound: true);
      final a = await gateway.call(0);
      expect(gateway.calls.length, 1);
      expect((await storage.autoStories.loadStory('story')).turns, isEmpty);
      await a.complete('A saved line');
      final b = await gateway.call(1);
      expect(
        (await storage.autoStories.loadStory('story')).turns.single.content,
        'A saved line',
      );
      expect(b.request.messages.toString(), contains('A saved line'));
      await b.complete('B saved line');
      await run;
      expect(runner.story!.completedRounds, 1);
      expect(runner.story!.status, StoryStatus.paused);
      expect(gateway.calls.length, 2);
    },
  );
  test(
    'pause during A saves A only and step resumes B without repeating A',
    () async {
      final run = runner.resume();
      final a = await gateway.call(0);
      await runner.requestPause();
      await a.complete('first');
      await run;
      expect(runner.story!.turns.length, 1);
      expect(runner.story!.nextActor, 'B');
      expect(gateway.calls.length, 1);
      final resumed = runner.resume(singleRound: true);
      final b = await gateway.call(1);
      await b.complete('second');
      await resumed;
      expect(runner.story!.completedRounds, 1);
      expect(gateway.calls.length, 2);
    },
  );
  test(
    'immediate stop rejects late A while a new run owns the lease',
    () async {
      final old = runner.resume();
      final a = await gateway.call(0);
      await runner.stopImmediately();
      final resumed = runner.resume();
      final replacement = await gateway.call(1);
      await a.complete('stale');
      await old;
      expect(runner.isBusy, isTrue);
      await runner.requestPause();
      await replacement.complete('new');
      await resumed;
      expect(runner.story!.turns.single.content, 'new');
    },
  );
  test(
    'disk failure retains pending result; retry saves without requesting again',
    () async {
      final run = runner.resume();
      final a = await gateway.call(0);
      json.failStory = true;
      await a.complete('persist me');
      await run;
      expect(runner.pendingSave, isTrue);
      expect(gateway.calls.length, 1);
      expect((await storage.autoStories.loadStory('story')).turns, isEmpty);
      json.failStory = false;
      await runner.retrySave();
      expect(runner.story!.turns.single.content, 'persist me');
      expect(runner.story!.status, StoryStatus.paused);
      expect(gateway.calls.length, 1);
    },
  );
  test(
    'duplicate resume and second controller cannot start concurrent requests',
    () async {
      final other = AutoStoryRunController(
        storage: storage,
        aiService: gateway,
        storyId: 'story',
      );
      await other.load();
      final run = runner.resume();
      await gateway.call(0);
      await runner.resume();
      await other.resume();
      expect(gateway.calls.length, 1);
      await runner.requestPause();
      await gateway.calls.first.complete('one');
      await run;
      other.dispose();
    },
  );
  test('manual takeover only at B cursor and adds no request', () async {
    await runner.stopImmediately();
    await runner.takeoverB('wrong position');
    expect(runner.story!.turns, isEmpty);
    final run = runner.resume();
    final a = await gateway.call(0);
    await runner.requestPause();
    await a.complete('A');
    await run;
    await runner.takeoverB('本人接管');
    expect(runner.story!.completedRounds, 1);
    expect(runner.story!.turns.last.source, StoryTurnSource.manual);
    expect(gateway.calls.length, 1);
  });
  test(
    'malformed plan receives exactly one reserved repair and then pauses without actors',
    () async {
      final plan = runner.generatePlan();
      (await gateway.director(
        0,
      )).complete(const AiResponse(content: 'not json', usage: AiUsage()));
      (await gateway.director(1)).complete(
        const AiResponse(content: 'still not json', usage: AiUsage()),
      );
      await plan;
      expect(gateway.directors.length, 2);
      expect(gateway.calls, isEmpty);
      expect(runner.story!.status, StoryStatus.paused);
      expect(runner.story!.usageTotals.attempts, 2);
    },
  );
  test('last request quota prevents corrective actor retry', () async {
    await storage.autoStories.mutateStory(
      'story',
      (doc) => doc.copyWith(config: doc.config.copyWith(maxRequests: 1)),
    );
    final run = runner.resume();
    await (await gateway.call(0)).complete('{}');
    await run;
    expect(gateway.calls.length, 1);
    expect(runner.story!.turns, isEmpty);
    expect(runner.story!.pauseReason, StoryPauseReason.requestLimit);
    expect(runner.story!.usageTotals.attempts, 1);
  });
  test(
    'HTTP failure pauses with one charged attempt and no self retry',
    () async {
      final run = runner.resume();
      final call = await gateway.call(0);
      call.stream.addError(AiException('offline'));
      await call.stream.close();
      await run;
      expect(gateway.calls.length, 1);
      expect(runner.story!.pauseReason, StoryPauseReason.requestError);
      expect(runner.story!.usageTotals.attempts, 1);
    },
  );
  test(
    'retry save can fail repeatedly without invalidating original reservation',
    () async {
      final run = runner.resume();
      final a = await gateway.call(0);
      json.failStory = true;
      await a.complete('persist later');
      await run;
      await runner.retrySave();
      expect(runner.pendingSave, isTrue);
      json.failStory = false;
      await runner.retrySave();
      expect(runner.story!.turns.single.content, 'persist later');
      expect(gateway.calls.length, 1);
    },
  );
  test(
    'regeneration atomically replaces only last turn and preserves old content on failure',
    () async {
      final run = runner.resume();
      final a = await gateway.call(0);
      await runner.requestPause();
      await a.complete('old');
      await run;
      final oldId = runner.story!.turns.single.turnId;
      final redo = runner.regenerateLast();
      await (await gateway.call(1)).complete('new');
      await redo;
      expect(runner.story!.turns.single.content, 'new');
      expect(runner.story!.turns.single.turnId, isNot(oldId));
      expect(runner.story!.turns.single.replacesTurnId, oldId);
      expect(runner.story!.nextActor, 'B');
    },
  );
  test(
    'one periodic and stage boundary check never becomes a third actor',
    () async {
      final run = runner.resume(singleRound: true);
      await (await gateway.call(0)).complete('A1');
      await (await gateway.call(1)).complete('B1');
      await run;
      final second = runner.resume(singleRound: true);
      await (await gateway.call(2)).complete('A2');
      await (await gateway.call(3)).complete('B2');
      await second;
      final third = runner.resume(singleRound: true);
      await (await gateway.call(4)).complete('A3');
      await (await gateway.call(5)).complete('B3');
      final response = await gateway.director(0);
      response.complete(
        AiResponse(
          content: jsonEncode({
            'coveredThroughOrdinal': 5,
            'summary': '双方交谈。',
            'facts': <Object>[],
            'stageSatisfied': false,
            'criteriaEvidence': <Object>[],
            'nextBeat': '观察店内陈设',
            'pacing': 'normal',
            'sceneTransition': null,
            'goalReached': false,
            'goalEvidence': <Object>[],
          }),
          usage: const AiUsage(),
        ),
      );
      await third;
      expect(runner.story!.turns.length, 6);
      expect(runner.story!.completedRounds, 3);
      expect(gateway.directors.length, 1);
      expect(runner.story!.directorCheckpoints.single.coveredThroughOrdinal, 5);
    },
  );
  test(
    'total-only duplicate usage stops next actor without inventing token breakdown',
    () async {
      await storage.autoStories.mutateStory(
        'story',
        (doc) => doc.copyWith(config: doc.config.copyWith(tokenLimit: 5)),
      );
      final run = runner.resume();
      final a = await gateway.call(0);
      a.stream.add(const AiResponseDelta(usage: AiUsage(totalTokens: 5)));
      a.stream.add(const AiResponseDelta(usage: AiUsage(totalTokens: 5)));
      await a.complete('first');
      final outcome = await Future.any([
        run.then((_) => 'stopped'),
        gateway.call(1).then((_) => 'extra request'),
      ]);
      if (outcome != 'stopped') {
        await runner.stopImmediately();
        await gateway.calls[1].complete('unexpected');
        await run;
      }
      expect(outcome, 'stopped');
      expect(runner.story!.pauseReason, StoryPauseReason.tokenLimit);
      expect(runner.story!.usageTotals.totalTokens, 5);
      expect(runner.story!.requestLedger.single.inputTokens, isNull);
      expect(gateway.calls.length, 1);
      expect(
        (await storage.loadAiUsageRecords()).single.requestType,
        'autoStoryActorA',
      );
    },
  );
  test(
    'create, plan, half-round restart, goal evidence, TXT and backup restore form one closed loop',
    () async {
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secure, (call) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(secure, null),
      );
      runner.dispose();
      final initial = AutoStoryDocument.fromJson({
        ...promptStory().toJson(),
        'id': 'integration',
        'status': 'draft',
        'plan': <Object>[],
      });
      await storage.autoStories.createStory(initial);
      runner = AutoStoryRunController(
        storage: storage,
        aiService: gateway,
        storyId: 'integration',
      );
      await runner.load();
      expect(gateway.calls, isEmpty);
      expect(gateway.directors, isEmpty);
      final planned = runner.generatePlan();
      (await gateway.director(0)).complete(
        AiResponse(
          content: jsonEncode({
            'stages': [
              for (var i = 0; i < 3; i++)
                {
                  'title': '阶段$i',
                  'objective': '完成一次自然互动',
                  'minRounds': 1,
                  'targetRounds': i == 2 ? 4 : 3,
                  'acceptanceCriteria': ['角色完成本阶段互动'],
                  'permittedDevelopments': ['自己的对白动作'],
                  'prematureDevelopments': <String>[],
                },
            ],
          }),
          usage: const AiUsage(
            promptTokens: 10,
            completionTokens: 10,
            totalTokens: 20,
          ),
        ),
      );
      await planned;
      expect(runner.story!.status, StoryStatus.ready);
      expect(gateway.calls, isEmpty);
      final first = runner.resume();
      final a = await gateway.call(0);
      await runner.requestPause();
      await a.complete('第一轮的招呼');
      await first;
      expect(runner.story!.nextActor, 'B');
      runner.dispose();
      // New storage/controller instances read the persisted half-round; no auto HTTP.
      storage = RunnerStorage(directory, json);
      await storage.autoStories.recoverInterruptedStories();
      runner = AutoStoryRunController(
        storage: storage,
        aiService: gateway,
        storyId: 'integration',
      );
      await runner.load();
      expect(gateway.calls.length, 1);
      expect(runner.story!.nextActor, 'B');
      final resumed = runner.resume(singleRound: true);
      await (await gateway.call(1)).complete('第一轮的回应');
      await resumed;
      var reviewIndex = 1;
      for (var round = 2; round <= 9; round++) {
        final step = runner.resume(singleRound: true);
        await (await gateway.call((round - 1) * 2)).complete('第$round轮的招呼');
        final responseText = round == 9 ? '（互换戒指）愿意与你共度余生。' : '第$round轮的回应';
        await (await gateway.call((round - 1) * 2 + 1)).complete(responseText);
        if ([3, 5, 9].contains(round)) {
          final response = await gateway.director(reviewIndex++);
          final saved = await storage.autoStories.loadStory('integration');
          final evidence = {
            'turnId': saved.turns.last.turnId,
            'quote': responseText,
            'eventType': 'actual',
          };
          response.complete(
            AiResponse(
              content: jsonEncode({
                'coveredThroughOrdinal': saved.turns.length - 1,
                'summary': '双方已完成第$round轮的互动。',
                'facts': [
                  {
                    'text': responseText,
                    'evidence': [evidence],
                  },
                ],
                'stageSatisfied': true,
                'criteriaEvidence': [
                  {...evidence, 'criterionIndex': 0},
                ],
                'nextBeat': '自然回应眼前情境',
                'pacing': 'normal',
                'sceneTransition': null,
                'goalReached': round == 9,
                'goalEvidence': round == 9 ? [evidence] : <Object>[],
              }),
              usage: const AiUsage(
                promptTokens: 5,
                completionTokens: 5,
                totalTokens: 10,
              ),
            ),
          );
        }
        await step;
      }
      final completed = runner.story!;
      expect(completed.status, StoryStatus.completed);
      expect(completed.completedRounds, 9);
      expect(completed.turns.length, 18);
      expect(
        completed.currentCheckpoint!.goalEvidence.single.quote,
        '（互换戒指）愿意与你共度余生。',
      );
      final exported = formatAutoStoryText(completed.toJson());
      expect(exported, contains('AI代演'));
      expect(exported, contains('第一轮的招呼'));
      expect(exported, isNot(contains('A_PRIVATE')));
      expect(exported, isNot(contains('TOP_SECRET_FUTURE')));
      final backup = await storage.exportAllData();
      final restoredStorage = LocalStorageService(
        appDataDirectory: Directory('${directory.path}/restored/app_data'),
      );
      await restoredStorage.importAllData(backup);
      final restored = await restoredStorage.autoStories.loadStory(
        'integration',
      );
      expect(restored.status, StoryStatus.paused);
      expect(
        restored.turns.map((t) => t.content),
        completed.turns.map((t) => t.content),
      );
      expect(
        restored.currentCheckpoint!.goalEvidence.single.turnId,
        completed.turns.last.turnId,
      );
      expect(gateway.calls.length, 18);
      final restoredController = AutoStoryRunController(
        storage: restoredStorage,
        aiService: gateway,
        storyId: 'integration',
      );
      await restoredController.load();
      await restoredController.resume();
      expect(restoredController.story!.status, StoryStatus.completed);
      expect(gateway.calls.length, 18);
      expect(gateway.directors.length, 4);
      restoredController.dispose();
    },
  );
  test(
    'regenerate builds a valid transient context without future scene, pin or replan summary',
    () async {
      final turns = [promptTurn(0), promptTurn(1)];
      final evidence = StoryEvidence(turnId: 't1', quote: '正文1');
      final fact = StoryFact(
        text: '已确认的旧结局',
        evidenceTurnIds: ['t1'],
        evidence: [evidence],
      );
      final cp = DirectorCheckpoint(
        checkpointId: 'cp',
        coveredThroughOrdinal: 1,
        coveredTurnIdsHash: storyTurnsHash(turns),
        planVersion: 1,
        summary: '旧结局摘要',
      );
      await storage.autoStories.mutateStory(
        'story',
        (doc) => AutoStoryDocument.fromJson({
          ...doc
              .copyWith(
                turns: turns,
                directorCheckpoints: [cp],
                currentCheckpointId: 'cp',
                lockedFacts: [fact],
                events: [
                  StoryEvent(
                    eventId: 'scene',
                    kind: 'sceneTransition',
                    content: '旧结局场景',
                    effectiveAfterOrdinal: 1,
                    sourceCheckpointId: 'cp',
                    status: 'applied',
                  ),
                ],
                status: StoryStatus.paused,
              )
              .toJson(),
          'replanSummary': '旧结局摘要',
          'replanCoveredThroughOrdinal': 1,
          'replanStartRound': 1,
        }),
      );
      final redo = runner.regenerateLast();
      final outcome = await Future.any([
        gateway.call(0).then((_) => 'request'),
        redo.then((_) => 'error'),
      ]);
      expect(outcome, 'request', reason: runner.error);
      expect(
        (await storage.autoStories.loadStory('story')).turns.last.content,
        '正文1',
      );
      expect(
        gateway.calls[0].request.messages.toString(),
        isNot(contains('旧结局')),
      );
      await gateway.calls[0].complete('新的回应');
      await redo;
      expect(runner.story!.turns.last.content, '新的回应');
      expect(runner.story!.lockedFacts, isEmpty);
      expect(runner.story!.events, isEmpty);
    },
  );
}
