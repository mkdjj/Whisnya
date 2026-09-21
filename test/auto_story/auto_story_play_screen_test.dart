import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/screens/auto_story/auto_story_play_screen.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/speech/role_speech_controller.dart';
import 'package:whisnya/services/speech/speech_backend.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'auto_story_model_test.dart' show storyFixture, turnFixture;
import 'auto_story_runner_test.dart' show RunnerStorage, RunnerGateway;
import 'auto_story_store_test.dart' show FailingStoryJsonStore;
import 'auto_story_prompt_test.dart' show promptStory;

class LocalSpeechBackend implements SpeechBackend {
  final spoken = <String>[];
  @override
  String get platformKey => 'test';
  @override
  Future<SpeechAvailability> initialize() async =>
      const SpeechAvailability(available: true);
  @override
  Future<List<AvailableVoice>> listVoices({String? engineId}) async => [
    const AvailableVoice(
      name: 'Local voice',
      locale: 'zh-CN',
      networkRequired: false,
    ),
    const AvailableVoice(
      name: 'Network voice',
      locale: 'zh-CN',
      networkRequired: true,
    ),
  ];
  @override
  Future<List<String>> listEngines() async => [];
  @override
  Future<void> speak(SpeechRequest request) async {
    spoken.add(request.text);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<(LocalStorageService, ValueNotifier<int>)> open(
    WidgetTester tester, {
    bool locked = false,
    bool half = false,
    bool facts = false,
    bool outline = false,
    bool completed = false,
    bool finalManual = false,
    bool longTimeline = false,
    bool reasoning = false,
    double textScale = 1,
    RoleSpeechController? speechController,
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('auto-story-play-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    late LocalStorageService storage;
    final calls = ValueNotifier(0);
    await tester.runAsync(() async {
      storage = LocalStorageService(appDataDirectory: root);
      await storage.loadCharacters();
      await storage.autoStories.createStory(
        storyFixture().copyWith(plan: outline ? promptStory().plan : []),
      );
      await storage.autoStories.mutateStory(
        'story-1',
        (s) => s.copyWith(
          status: completed ? StoryStatus.completed : StoryStatus.paused,
          goalStatus: completed ? 'reached' : 'pending',
          privacyRequired: locked,
          turns: longTimeline
              ? List.generate(
                  10,
                  (i) =>
                      StoryTurn.fromJson({
                        ...turnFixture(i).toJson(),
                        if (reasoning) 'reasoningContent': 'Reasoning $i',
                      }).copyWith(
                        content:
                            'Hello $i\n${List.filled(8, '这是故事的正式正文，手指在气泡上也应上下滚动。').join('\n')}',
                      ),
                )
              : facts || outline
              ? [
                  turnFixture(0),
                  finalManual
                      ? StoryTurn.fromJson({
                          ...turnFixture(1).toJson(),
                          'source': 'manual',
                        })
                      : turnFixture(1),
                ]
              : half
              ? [turnFixture(0)]
              : [],
          directorCheckpoints: facts || outline
              ? [
                  DirectorCheckpoint(
                    checkpointId: 'cp',
                    coveredThroughOrdinal: 1,
                    coveredTurnIdsHash: storyTurnsHash([
                      turnFixture(0),
                      turnFixture(1),
                    ]),
                    planVersion: 1,
                    stageIndex: completed
                        ? 2
                        : outline
                        ? 1
                        : 0,
                    goalEvidence: completed
                        ? [StoryEvidence(turnId: 'turn-0', quote: 'Hello 0')]
                        : [],
                    stageStartedRound: outline ? 1 : 0,
                    summary: 'Established summary',
                    confirmedFacts: [
                      StoryFact(
                        text: 'A greeted B',
                        evidenceTurnIds: ['turn-0'],
                        evidence: [
                          StoryEvidence(turnId: 'turn-0', quote: 'Hello 0'),
                        ],
                      ),
                    ],
                  ),
                ]
              : [],
          currentCheckpointId: facts || outline ? 'cp' : null,
          events: outline
              ? [
                  StoryEvent(
                    eventId: 'scene',
                    kind: 'sceneTransition',
                    effectiveAfterOrdinal: 1,
                    content: 'An established cafe',
                    status: 'applied',
                    sourceCheckpointId: 'cp',
                  ),
                ]
              : [],
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: AutoStoryPlayScreen(
          storage: storage,
          settings: AppSettings(
            showReasoningContent: reasoning,
            enableCharacterSpeech: speechController != null,
          ),
          speechController: speechController,
          storyId: 'story-1',
          aiService: AiService(
            client: MockClient((_) async {
              calls.value++;
              throw StateError('Unexpected AI');
            }),
          ),
        ),
      ),
    );
    await settleIo(tester);
    return (storage, calls);
  }

  testWidgets(
    'large text on a narrow story page does not overlap the controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, half: true, textScale: 2);
      expect(tester.takeException(), isNull);
      final viewport = tester.getRect(
        find.byKey(const PageStorageKey('auto-story-timeline')),
      );
      expect(viewport.height, greaterThan(80));
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets('touch dragging a saved bubble moves the real timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, longTimeline: true);
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('auto-story-timeline'));
    final controller = tester.widget<ListView>(list).controller!;
    final before = controller.offset;
    final viewport = tester.getRect(list);
    await tester.dragFrom(
      Offset(viewport.center.dx, viewport.center.dy),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(before - 80));
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });
  testWidgets(
    'opening saved story never generates and exposes explicit controls',
    (tester) async {
      final (_, calls) = await open(tester, half: true);
      expect(find.text('Hello 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('auto-story-continue')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auto-story-step-round')),
        findsOneWidget,
      );
      expect(calls.value, 0);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets('locked story never reveals body or future goal before unlock', (
    tester,
  ) async {
    final (_, calls) = await open(tester, locked: true, half: true);
    expect(find.text('Hello 0'), findsNothing);
    expect(find.text('Friends'), findsNothing);
    expect(find.byKey(const ValueKey('auto-story-continue')), findsNothing);
    expect(calls.value, 0);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });
  testWidgets(
    'manual B occupies only B slot and is visibly labeled without AI request',
    (tester) async {
      final (storage, calls) = await open(tester, half: true);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('auto-story-takeover'))),
      );
      await settleIo(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auto-story-input')),
        'I choose to stay.',
      );
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('auto-story-input-save'))),
      );
      await settleIo(tester);
      final doc = await tester.runAsync(
        () => storage.autoStories.loadStory('story-1'),
      );
      expect(doc!.turns.length, 2);
      expect(doc.turns.last.source, StoryTurnSource.manual);
      expect(find.textContaining('本人接管'), findsWidgets);
      expect(calls.value, 0);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets(
    'background cancels streaming turn and resumed never restarts it',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('auto-story-lifecycle-');
      addTearDown(() => root.deleteSync(recursive: true));
      late RunnerStorage storage;
      late RunnerGateway gateway;
      await tester.runAsync(() async {
        storage = RunnerStorage(root, FailingStoryJsonStore());
        gateway = RunnerGateway();
        await storage.loadCharacters();
        await storage.autoStories.createStory(
          promptStory().copyWith(status: StoryStatus.draft),
        );
        await storage.autoStories.mutateStory(
          'story',
          (s) => s.copyWith(status: StoryStatus.ready),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: AutoStoryPlayScreen(
            storage: storage,
            aiService: gateway,
            settings: const AppSettings(),
            storyId: 'story',
          ),
        ),
      );
      await settleIo(tester);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('auto-story-start'))),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, '确认')),
      );
      await settleIo(tester);
      expect(gateway.calls.length, 1);
      expect(find.byKey(const ValueKey('auto-story-stop')), findsOneWidget);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      });
      await settleIo(tester);
      await tester.runAsync(
        () => gateway.calls.single.complete('late uncommitted reply'),
      );
      await settleIo(tester);
      final doc = await tester.runAsync(
        () => storage.autoStories.loadStory('story'),
      );
      expect(doc!.turns, isEmpty);
      expect(doc.status, StoryStatus.paused);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await settleIo(tester);
      expect(gateway.calls.length, 1);
      expect(find.text('late uncommitted reply'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets('story review survives scrolling off screen and back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, facts: true, longTimeline: true);
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('auto-story-timeline'));
    final controller = tester.widget<ListView>(list).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('已确认事实与剧情检查'));
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Established summary'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });
  testWidgets('reasoning panels keep independent state while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, longTimeline: true, reasoning: true);
    await tester.pumpAndSettle();
    final controller = tester
        .widget<ListView>(
          find.byKey(const PageStorageKey('auto-story-timeline')),
        )
        .controller!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    await tester.tap(find.text('推理内容（不属于正文）').last);
    await tester.pumpAndSettle();
    expect(find.text('Reasoning 9'), findsOneWidget);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Reasoning 0'), findsNothing);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Reasoning 9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });
  testWidgets('verified fact can be pinned without inventing new facts', (
    tester,
  ) async {
    final (storage, calls) = await open(tester, facts: true);
    await tester.tap(find.text('已确认事实与剧情检查'));
    await tester.pumpAndSettle();
    final pin = find.byKey(const ValueKey('auto-story-pin-A greeted B'));
    expect(tester.widget<IconButton>(pin).onPressed, isNotNull);
    await tester.ensureVisible(pin);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(pin));
    await settleIo(tester);
    final doc = await tester.runAsync(
      () => storage.autoStories.loadStory('story-1'),
    );
    expect(doc!.lockedFacts.single.text, 'A greeted B');
    expect(calls.value, 0);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });
  testWidgets('an input dialog cannot write into a replaced dataset', (
    tester,
  ) async {
    final (storage, _) = await open(tester, half: true);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('auto-story-takeover'))),
    );
    await settleIo(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auto-story-input')),
      'old dataset input',
    );
    await tester.runAsync(
      () => storage.jsonStore.maintain(() {}, advanceEpoch: true),
    );
    await settleIo(tester);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('auto-story-input-save'))),
    );
    await settleIo(tester);
    final doc = await tester.runAsync(
      () => storage.autoStories.loadStory('story-1'),
    );
    expect(doc!.turns.length, 1);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });
  testWidgets(
    'future outline edit preserves past stages facts and stage progress',
    (tester) async {
      final (storage, _) = await open(tester, outline: true);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('查看与编辑大纲')));
      await settleIo(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).readOnly,
        true,
      );
      final title = find.byType(TextField).at(5);
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.enterText(title, 'Updated future stage');
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('auto-story-outline-save'))),
      );
      await settleIo(tester);
      final doc = await tester.runAsync(
        () => storage.autoStories.loadStory('story-1'),
      );
      expect(doc!.currentCheckpoint, isNull);
      expect(doc.stageIndex, 1);
      expect(doc.replanStartRound, 1);
      expect(doc.replanSummary, 'Established summary');
      expect(doc.replanCoveredThroughOrdinal, 1);
      expect(doc.turns.map((t) => t.content), ['Hello 0', 'Hello 1']);
      expect(doc.events.single.content, 'An established cafe');
      expect(doc.plan.first.title, '阶段0');
      expect(doc.plan[1].title, 'Updated future stage');
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets(
    'completed final manual B can be edited and invalidates completion',
    (tester) async {
      final (storage, calls) = await open(
        tester,
        outline: true,
        completed: true,
        finalManual: true,
      );
      final edit = find.widgetWithText(TextButton, '编辑最后一次接管');
      expect(edit, findsOneWidget);
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(edit));
      await settleIo(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auto-story-input')),
        'A changed ending.',
      );
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('auto-story-input-save'))),
      );
      await settleIo(tester);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, '确认')),
      );
      await settleIo(tester);
      final story = await tester.runAsync(
        () => storage.autoStories.loadStory('story-1'),
      );
      expect(story!.status, StoryStatus.paused);
      expect(story.goalStatus, 'pending');
      expect(story.currentCheckpoint, isNull);
      expect(story.turns.last.content, 'A changed ending.');
      expect(story.turns.last.replacesTurnId, 'turn-1');
      expect(story.turns.last.source, StoryTurnSource.manual);
      expect(calls.value, 0);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets('unchanged outline keeps completed story and checkpoint intact', (
    tester,
  ) async {
    final (storage, _) = await open(tester, outline: true, completed: true);
    final before = await tester.runAsync(
      () => storage.autoStories.loadStory('story-1'),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('查看与编辑大纲')));
    await settleIo(tester);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('auto-story-outline-save'))),
    );
    await settleIo(tester);
    final after = await tester.runAsync(
      () => storage.autoStories.loadStory('story-1'),
    );
    expect(after!.status, StoryStatus.completed);
    expect(after.goalStatus, 'reached');
    expect(after.currentCheckpointId, 'cp');
    expect(after.config.planVersion, before!.config.planVersion);
    expect(after.revision, before.revision);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });
  testWidgets('explicit B narration offers only offline fallback voices', (
    tester,
  ) async {
    final backend = LocalSpeechBackend();
    final speech = RoleSpeechController(backend: backend);
    final (_, calls) = await open(
      tester,
      facts: true,
      speechController: speech,
    );
    expect(backend.spoken, isEmpty);
    final button = find.byTooltip('朗读正文').last;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(button));
    await settleIo(tester);
    expect(find.text('Local voice · zh-CN'), findsOneWidget);
    expect(find.textContaining('Network voice'), findsNothing);
    expect(backend.spoken, isEmpty);
    await tester.runAsync(() => tester.tap(find.text('Local voice · zh-CN')));
    await settleIo(tester);
    expect(backend.spoken, ['Hello 1']);
    expect(calls.value, 0);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
    speech.dispose();
  });
}
