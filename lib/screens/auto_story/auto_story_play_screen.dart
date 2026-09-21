import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/app_settings.dart';
import '../../models/auto_story.dart';
import '../../models/chat_message.dart';
import '../../models/character_voice_profile.dart';
import '../../models/memento.dart';
import '../../services/ai/ai_gateway.dart';
import '../../services/auto_story/auto_story_export.dart';
import '../../services/auto_story/auto_story_run_controller.dart';
import '../../services/local_storage_service.dart';
import '../../services/memento_service.dart';
import '../../services/speech/role_speech_controller.dart';
import '../../services/speech/speech_backend.dart';
import '../../utils/app_i18n.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/snack.dart';
import '../../widgets/app_background.dart';
import '../../widgets/auto_story/auto_story_outline_dialog.dart';
import '../../widgets/auto_story/auto_story_turn_card.dart';
import 'auto_story_access.dart';
import 'auto_story_editor_screen.dart';

class AutoStoryPlayScreen extends StatefulWidget {
  const AutoStoryPlayScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    required this.storyId,
    this.generatePlanOnOpen = false,
    this.speechController,
    super.key,
  });
  final LocalStorageService storage;
  final AiGateway aiService;
  final AppSettings settings;
  final String storyId;
  final bool generatePlanOnOpen;
  final RoleSpeechController? speechController;
  @override
  State<AutoStoryPlayScreen> createState() => _AutoStoryPlayScreenState();
}

class _AutoStoryPlayScreenState extends State<AutoStoryPlayScreen>
    with WidgetsBindingObserver {
  late final AutoStoryRunController _runner;
  final _scroll = ScrollController();
  final _newContent = ValueNotifier(false);
  final _waiters = <Completer<void>>{};
  bool _authorized = false,
      _privacyAuthorized = false,
      _loading = true,
      _visible = true,
      _closing = false,
      _editing = false,
      _costAccepted = false;
  int _loadId = 0, _lastTurns = 0;
  late int _epoch;
  String? _error;
  String _root = '';
  bool _nearBottom = true, _scrollScheduled = false;
  RoleSpeechController get _speech =>
      widget.speechController ?? RoleSpeechController.instance;
  String tr(String zh, String en) => context.isEnglish ? en : zh;
  @override
  void initState() {
    super.initState();
    _epoch = widget.storage.datasetEpoch;
    _runner = AutoStoryRunController(
      storage: widget.storage,
      aiService: widget.aiService,
      storyId: widget.storyId,
      authorize: _authorize,
    );
    _runner.addListener(_changed);
    _runner.draft.addListener(_draftChanged);
    _scroll.addListener(_scrolled);
    widget.storage.datasetEpochListenable.addListener(_datasetChanged);
    WidgetsBinding.instance.addObserver(this);
    _speech.configure(
      enabled: widget.settings.enableCharacterSpeech,
      allowNetworkVoices: widget.settings.allowNetworkSpeechVoices,
    );
    unawaited(_load(generatePlan: widget.generatePlanOnOpen));
  }

  Future<bool> _authorize() async {
    if (!mounted ||
        _closing ||
        !_visible ||
        _epoch != widget.storage.datasetEpoch) {
      return false;
    }
    final headers = await widget.storage.autoStories.listStories();
    final header = headers.where((s) => s.id == widget.storyId).firstOrNull;
    if (header == null) return false;
    final needs = await autoStoryNeedsUnlock(widget.storage, header);
    if (!mounted ||
        _closing ||
        !_visible ||
        _epoch != widget.storage.datasetEpoch) {
      return false;
    }
    if (!needs) return true;
    if (_privacyAuthorized) return true;
    final allowed = await unlockAutoStory(context, widget.storage, header);
    if (allowed &&
        mounted &&
        !_closing &&
        _epoch == widget.storage.datasetEpoch) {
      _privacyAuthorized = true;
    }
    return allowed &&
        mounted &&
        !_closing &&
        _visible &&
        _epoch == widget.storage.datasetEpoch;
  }

  Future<void> _load({bool generatePlan = false}) async {
    final request = ++_loadId;
    try {
      final allowed = await _authorize();
      if (!mounted || request != _loadId) return;
      if (!allowed) {
        setState(() {
          _authorized = false;
          _loading = false;
        });
        return;
      }
      final root = await widget.storage.appDataDirectory;
      await _runner.load();
      if (!mounted ||
          request != _loadId ||
          _epoch != widget.storage.datasetEpoch) {
        return;
      }
      setState(() {
        _authorized = true;
        _loading = false;
        _root = root.path;
        _error = null;
      });
      _contentChanged();
      if (generatePlan) await _runner.generatePlan();
    } catch (e) {
      if (mounted && request == _loadId) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _changed() {
    if (!mounted || _closing) return;
    final count = _runner.story?.turns.length ?? 0;
    if (count != _lastTurns) {
      _lastTurns = count;
      _contentChanged();
    }
    if (!_runner.isBusy) {
      for (final waiter in _waiters.toList()) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
    setState(() {});
  }

  void _draftChanged() => _contentChanged();
  void _scrolled() {
    _nearBottom = !_scroll.hasClients || _scroll.position.extentAfter < 100;
    if (_nearBottom && _newContent.value) _newContent.value = false;
  }

  void _contentChanged() {
    if (!mounted || _closing) return;
    if (!_nearBottom) {
      _newContent.value = true;
      return;
    }
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted && !_closing && _nearBottom && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _datasetChanged() {
    if (!mounted || _closing) return;
    _epoch = widget.storage.datasetEpoch;
    _privacyAuthorized = false;
    unawaited(_speech.stop());
    setState(() {
      _authorized = false;
      _loading = true;
    });
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _visible = false;
      unawaited(_speech.stop());
      if (_runner.isBusy || _runner.story?.status == StoryStatus.running) {
        unawaited(_runner.requestPause());
      }
    } else if (state == AppLifecycleState.resumed) {
      _visible = true;
      // Resuming the window never resumes generation.
    } else {
      _visible = false;
      unawaited(_speech.stop());
      if (_runner.isBusy || _runner.story?.status == StoryStatus.running) {
        unawaited(_runner.stopImmediately(StoryPauseReason.background));
      }
    }
  }

  Future<void> _stop([
    StoryPauseReason reason = StoryPauseReason.userStop,
  ]) async {
    await _speech.stop();
    if (_runner.isBusy ||
        _runner.story?.status == StoryStatus.running ||
        _runner.pendingSave) {
      await _runner.stopImmediately(reason);
    }
  }

  @override
  void dispose() {
    _closing = true;
    ++_loadId;
    WidgetsBinding.instance.removeObserver(this);
    widget.storage.datasetEpochListenable.removeListener(_datasetChanged);
    _runner.removeListener(_changed);
    _runner.draft.removeListener(_draftChanged);
    unawaited(_speech.stop());
    if (_runner.isBusy ||
        _runner.story?.status == StoryStatus.running ||
        _runner.pendingSave) {
      unawaited(_runner.stopImmediately(StoryPauseReason.leftPage));
    }
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _runner.dispose();
    _scroll.dispose();
    _newContent.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted && !_closing) context.showSnack(e.toString());
    }
  }

  Future<bool> _pauseForEdit() async {
    await _speech.stop();
    if (_runner.pendingSave) {
      if (mounted) {
        context.showSnack(
          tr(
            '请先重试保存，或立即停止以放弃待保存内容。',
            'Retry saving first, or stop to discard the pending result.',
          ),
        );
      }
      return false;
    }
    if (_runner.isBusy || _runner.story?.status == StoryStatus.running) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await _runner.requestPause();
        if (_runner.isBusy) await waiter.future;
      } finally {
        _waiters.remove(waiter);
      }
    }
    return mounted && !_closing && _visible && await _authorize();
  }

  Future<void> _start({bool singleRound = false}) async {
    if (_runner.isBusy || _runner.pendingSave || _editing) return;
    final epoch = _epoch;
    if (!_costAccepted) {
      final allowed = await showConfirmDialog(
        context: context,
        title: tr('开始演绎', 'Start story'),
        content: tr(
          '本模式会连续调用你配置的 AI 接口，演员和剧情检查均可能计费。停止不保证服务商不计已处理请求费用。',
          'This mode repeatedly calls your AI providers. Actor turns and story reviews may incur charges. Stopping does not cancel charges already incurred.',
        ),
      );
      if (!allowed || !mounted || epoch != widget.storage.datasetEpoch) return;
      _costAccepted = true;
    }
    await _runner.resume(singleRound: singleRound);
  }

  Future<void> _outline() async {
    if (!await _pauseForEdit() || !mounted) return;
    final epoch = _epoch;
    final story = _runner.story!;
    if (story.plan.isEmpty) {
      context.showSnack(tr('请先生成剧情大纲。', 'Generate an outline first.'));
      return;
    }
    final plan = await showDialog<List<StoryStage>>(
      context: context,
      builder: (_) =>
          AutoStoryOutlineDialog(story: story, english: context.isEnglish),
    );
    if (plan == null || !mounted || epoch != widget.storage.datasetEpoch) {
      return;
    }
    if (jsonEncode(plan.map((stage) => stage.toJson()).toList()) ==
        jsonEncode(story.plan.map((stage) => stage.toJson()).toList())) {
      return;
    }
    await widget.storage.autoStories.mutateStory(
      story.id,
      (s) => AutoStoryDocument.fromJson({
        ...s
            .copyWith(
              plan: plan,
              status: s.turns.isEmpty ? StoryStatus.ready : StoryStatus.paused,
              clearCurrentCheckpoint: true,
              goalStatus: 'pending',
            )
            .toJson(),
        'replanSummary': s.currentCheckpoint?.summary ?? s.replanSummary,
        'replanCoveredThroughOrdinal':
            s.currentCheckpoint?.coveredThroughOrdinal ??
            s.replanCoveredThroughOrdinal,
        'replanStageIndex': s.stageIndex,
        'replanStartRound':
            s.currentCheckpoint?.stageStartedRound ?? s.replanStartRound,
      }),
      expectedRevision: story.revision,
    );
    await _runner.load();
  }

  Future<({String text, String scope})?> _input({
    required String title,
    String initial = '',
    int max = 2000,
    bool scopes = false,
  }) async {
    final epoch = _epoch;
    var text = initial, scope = 'checkpoint';
    String? error;
    final result = await showDialog<({String text, String scope})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('auto-story-input'),
                  initialValue: initial,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: max,
                  onChanged: (v) => text = v,
                  decoration: InputDecoration(errorText: error),
                ),
                if (scopes)
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    items: [
                      DropdownMenuItem(
                        value: 'nextTurn',
                        child: Text(tr('仅下一次发言', 'Next turn')),
                      ),
                      DropdownMenuItem(
                        value: 'round',
                        child: Text(tr('一轮（A 和 B）', 'One round (A and B)')),
                      ),
                      DropdownMenuItem(
                        value: 'checkpoint',
                        child: Text(tr('下次剧情检查前', 'Until next review')),
                      ),
                      DropdownMenuItem(
                        value: 'story',
                        child: Text(tr('整个故事', 'Entire story')),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) scope = v;
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              key: const ValueKey('auto-story-input-save'),
              onPressed: () {
                if (text.trim().isEmpty || text.runes.length > max) {
                  setDialogState(
                    () => error = tr('请输入有效内容', 'Enter valid content'),
                  );
                  return;
                }
                Navigator.of(context).pop((text: text.trim(), scope: scope));
              },
              child: Text(tr('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    return mounted && epoch == widget.storage.datasetEpoch ? result : null;
  }

  Future<void> _director() async {
    if (!await _pauseForEdit() || !mounted) return;
    final input = await _input(
      title: tr(
        '导演指令（建议，不是既成事实）',
        'Director instruction (a suggestion, not an established fact)',
      ),
      scopes: true,
    );
    if (input != null && mounted) {
      await _runner.addInstruction(input.text, scope: input.scope);
    }
  }

  Future<void> _takeover() async {
    if (!await _pauseForEdit() || !mounted) return;
    final input = await _input(
      title: tr('接管 B 一次', 'Take over B once'),
      max: 4000,
    );
    if (input != null && mounted) await _runner.takeoverB(input.text);
  }

  Future<void> _editManual(StoryTurn turn) async {
    if (!await _pauseForEdit() || !mounted) return;
    final epoch = _epoch;
    final input = await _input(
      title: tr('编辑最后一次接管', 'Edit last manual turn'),
      initial: turn.content,
      max: 4000,
    );
    if (input == null || !mounted) return;
    if (!await showConfirmDialog(
          context: context,
          title: tr('替换最后一条', 'Replace last turn'),
          content: tr(
            '相关剧情检查和场景判断会失效，之后需要重新检查。',
            'Related story reviews and scene conclusions will be invalidated and need reviewing again.',
          ),
        ) ||
        !mounted ||
        epoch != widget.storage.datasetEpoch) {
      return;
    }
    await widget.storage.autoStories.editLastManualTurn(
      widget.storyId,
      input.text,
    );
    await _runner.load();
  }

  Future<void> _regenerate() async {
    if (!await _pauseForEdit() || !mounted) return;
    final epoch = _epoch;
    if (await showConfirmDialog(
          context: context,
          title: tr('重新生成最后一条', 'Regenerate last turn'),
          content: tr(
            '这是一次新的计费请求。成功保存才会替换原文，相关剧情判断将重新检查。',
            'This is a new billable request. The original remains until a replacement is saved; dependent story conclusions will be reviewed again.',
          ),
        ) &&
        mounted &&
        epoch == widget.storage.datasetEpoch) {
      await _runner.regenerateLast();
    }
  }

  Future<void> _settings() async {
    if (!await _pauseForEdit() || !mounted) return;
    final epoch = _epoch;
    setState(() => _editing = true);
    try {
      final result = await Navigator.of(context).push<AutoStoryEditorResult>(
        MaterialPageRoute(
          builder: (_) => AutoStoryEditorScreen(
            storage: widget.storage,
            settings: widget.settings,
            story: _runner.story,
          ),
        ),
      );
      if (!mounted || epoch != widget.storage.datasetEpoch) return;
      await _runner.load();
      if (result?.generatePlan == true) await _runner.generatePlan();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _export() async {
    if (!await _pauseForEdit() || !mounted) return;
    final epoch = _epoch;
    var include = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr('导出 TXT', 'Export TXT')),
          content: CheckboxListTile(
            value: include,
            onChanged: (v) => setDialogState(() => include = v ?? false),
            title: Text(tr('包含目标与大纲', 'Include target and outline')),
            subtitle: Text(
              tr(
                '默认仅导出已保存正文与实际场景过渡。',
                'By default, exports only saved turns and actual scene transitions.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('导出', 'Export')),
            ),
          ],
        ),
      ),
    );
    if (approved != true ||
        !mounted ||
        epoch != widget.storage.datasetEpoch ||
        !await _authorize()) {
      return;
    }
    final story = await widget.storage.autoStories.loadStory(widget.storyId);
    if (mounted && epoch == widget.storage.datasetEpoch) {
      await exportAutoStoryText(
        story.toJson(),
        includePlan: include,
        english: context.isEnglish,
      );
    }
  }

  Future<void> _usage() async {
    final s = _runner.story;
    if (s == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('调用与用量', 'Requests and usage')),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.usageTotals.attempts} / ${s.config.maxRequests} ${tr('次请求', 'requests')}',
                ),
                Text(
                  '${tr('已知 Token', 'Known tokens')}: ${s.usageTotals.totalTokens}${s.config.tokenLimit == null ? '' : ' / ${s.config.tokenLimit}'}',
                ),
                if (s.usageTotals.hasUnknown)
                  Text(
                    tr(
                      '用量部分未知；Token 阈值不能可靠覆盖未报告的消耗。',
                      'Usage is partially unknown; the token threshold cannot reliably cover unreported usage.',
                    ),
                  ),
                const Divider(),
                for (final record in s.requestLedger.reversed.take(100))
                  ListTile(
                    dense: true,
                    title: Text(_purpose(record.purpose)),
                    subtitle: Text(
                      '${_ledgerStatus(record.status)} · ${record.createdAt.toLocal()} · ${record.inputTokens ?? '?'} + ${record.outputTokens ?? '?'} Token',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('关闭', 'Close')),
          ),
        ],
      ),
    );
  }

  String _purpose(RequestPurpose purpose) => switch (purpose) {
    RequestPurpose.plan => tr('初始规划', 'Initial plan'),
    RequestPurpose.replan => tr('重新规划', 'Replan'),
    RequestPurpose.actorA => tr('演员 A', 'Actor A'),
    RequestPurpose.actorB => tr('演员 B', 'Actor B'),
    RequestPurpose.review => tr('剧情检查', 'Story review'),
    RequestPurpose.repair => tr('格式纠正', 'Format repair'),
    RequestPurpose.regenerate => tr('重生成', 'Regeneration'),
  };
  String _ledgerStatus(String status) => switch (status) {
    'pending' => tr('待完成', 'Pending'),
    'committed' => tr('已保存', 'Saved'),
    'failed' => tr('失败', 'Failed'),
    'cancelled' => tr('已取消', 'Cancelled'),
    'unknown' => tr('结果未知', 'Outcome unknown'),
    'applied' => tr('已生效', 'Applied'),
    'expired' => tr('已失效', 'Expired'),
    _ => status,
  };
  bool _pinned(AutoStoryDocument story, StoryFact fact) =>
      story.lockedFacts.any(
        (f) =>
            f.text == fact.text &&
            f.evidenceTurnIds.length == fact.evidenceTurnIds.length &&
            f.evidenceTurnIds.toSet().containsAll(fact.evidenceTurnIds),
      );
  Future<void> _pin(StoryFact fact, bool pinned) async {
    if (!await _pauseForEdit()) return;
    await widget.storage.autoStories.setFactPinned(
      widget.storyId,
      fact,
      pinned: pinned,
    );
    await _runner.load();
  }

  Widget _facts(AutoStoryDocument s) {
    final facts = [
      ...s.currentCheckpoint?.confirmedFacts ?? <StoryFact>[],
      for (final locked in s.lockedFacts)
        if (!(s.currentCheckpoint?.confirmedFacts ?? <StoryFact>[]).any(
          (f) =>
              f.text == locked.text &&
              f.evidenceTurnIds.toSet().containsAll(locked.evidenceTurnIds),
        ))
          locked,
    ];
    return ExpansionTile(
      key: PageStorageKey('auto-story-facts-${s.id}'),
      title: Text(tr('已确认事实与剧情检查', 'Confirmed facts and story review')),
      children: [
        if (s.currentCheckpoint != null)
          ListTile(title: Text(s.currentCheckpoint!.summary)),
        for (final fact in facts)
          ListTile(
            dense: true,
            leading: Icon(
              _pinned(s, fact) ? Icons.lock : Icons.fact_check_outlined,
            ),
            title: Text(fact.text),
            subtitle: _pinned(s, fact)
                ? Text(
                    tr(
                      '已锁定：后续检查保留；证据被替换时自动失效',
                      'Pinned across reviews; invalidated when its evidence is replaced',
                    ),
                  )
                : null,
            trailing: IconButton(
              key: ValueKey('auto-story-pin-${fact.text}'),
              tooltip: _pinned(s, fact)
                  ? tr('解除事实锁定', 'Unpin fact')
                  : tr('锁定已验证事实', 'Pin verified fact'),
              onPressed:
                  !_runner.isBusy &&
                      [
                        StoryStatus.paused,
                        StoryStatus.completed,
                      ].contains(s.status) &&
                      (_pinned(s, fact) ||
                          fact.evidenceTurnIds.every(
                            (id) => fact.evidence.any((e) => e.turnId == id),
                          ))
                  ? () => _action(() => _pin(fact, !_pinned(s, fact)))
                  : null,
              icon: Icon(
                _pinned(s, fact)
                    ? Icons.lock_open_outlined
                    : Icons.lock_outline,
              ),
            ),
          ),
        if (s.status == StoryStatus.completed)
          for (final evidence in s.currentCheckpoint!.goalEvidence)
            ListTile(
              title: Text(tr('结局证据', 'Goal evidence')),
              subtitle: Text('“${evidence.quote}”'),
            ),
      ],
    );
  }

  Future<void> _collect(StoryTurn turn) async {
    if (!await _authorize() || !mounted) return;
    final epoch = _epoch;
    final story = await widget.storage.autoStories.loadStory(widget.storyId);
    if (!mounted || epoch != widget.storage.datasetEpoch) return;
    final title = await showTextInputDialog(
      context: context,
      title: tr('收藏到回忆册', 'Save to memories'),
      initialText: story.config.title,
      emptyIsNull: true,
    );
    if (title == null || !mounted || epoch != widget.storage.datasetEpoch) {
      return;
    }
    await MementoService(
      storage: widget.storage,
      authorize: (_, _) => _authorize(),
    ).createMemento(
      MementoDraft(
        idempotencyKey: newStoryId(),
        title: title,
        characterId: story.actors.first.sourceId ?? '',
        characterNameSnapshot: story.actors.first.name,
        sessionTitleSnapshot: story.config.title,
        sourceSessionId: story.id,
        sourceType: 'autoStory',
        entries: [autoStoryMementoEntry(story, turn)],
        requiresUnlock: story.privacyRequired,
      ),
    );
    if (mounted) context.showSnack(tr('已收藏正式正文', 'Saved formal story text'));
  }

  Future<void> _speak(StoryTurn turn) async {
    if (!await _authorize() || !mounted) return;
    final epoch = _epoch;
    if (_speech.messageId == turn.turnId && _speech.isPlaying) {
      await _speech.stop();
      return;
    }
    final actor = _runner.story!.actors.firstWhere(
      (a) => a.actorId == turn.speakerId,
    );
    final characters = await widget.storage.loadCharacters();
    if (!mounted || epoch != widget.storage.datasetEpoch) return;
    final source = characters.where((c) => c.id == actor.sourceId).firstOrNull;
    var profile = source?.voiceProfiles[_speech.platformKey];
    if (profile == null) {
      final availability = await _speech.backend.initialize().timeout(
        const Duration(seconds: 8),
      );
      final voices = availability.available
          ? (await _speech.backend.listVoices().timeout(
              const Duration(seconds: 8),
            )).where((voice) => voice.networkRequired == false).toList()
          : <AvailableVoice>[];
      if (!mounted || !_visible || epoch != widget.storage.datasetEpoch) return;
      if (voices.isEmpty) {
        context.showSnack(
          tr(
            '没有可用的离线系统音色，请先在系统设置中安装音色。',
            'No offline system voice is available. Install a voice in system settings first.',
          ),
        );
        return;
      }
      profile = await showDialog<CharacterVoiceProfile>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(tr('选择离线系统音色', 'Choose an offline system voice')),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr(
                  '此演员没有来源音色。仅为本次手动朗读选择本地音色，不更改角色或全局设置。',
                  'This actor has no source voice. Choose a local voice for this manual reading only; character and global settings stay unchanged.',
                ),
              ),
            ),
            for (final voice in voices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  CharacterVoiceProfile(
                    voiceName: voice.name,
                    locale: voice.locale,
                    identifier: voice.identifier,
                  ),
                ),
                child: Text('${voice.name} · ${voice.locale}'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('取消', 'Cancel')),
            ),
          ],
        ),
      );
      if (profile == null ||
          !mounted ||
          !_visible ||
          epoch != widget.storage.datasetEpoch) {
        return;
      }
    }
    if (!await _authorize() ||
        !mounted ||
        epoch != widget.storage.datasetEpoch) {
      return;
    }
    await _speech.playMessage(
      message: ChatMessage(
        id: turn.turnId,
        role: 'assistant',
        content: turn.content,
        time: turn.createdAt,
      ),
      sessionId: 'autoStory:${widget.storyId}',
      messageId: turn.turnId,
      variantId: turn.turnId,
      datasetEpoch: _epoch,
      profile: profile,
    );
    if (mounted && _speech.error != null) {
      context.showSnack(
        tr(
          '系统朗读不可用：${_speech.error}',
          'System speech unavailable: ${_speech.error}',
        ),
      );
    }
  }

  String _status(AutoStoryDocument s) => switch (s.status) {
    StoryStatus.draft => tr('草稿', 'Draft'),
    StoryStatus.ready => tr('大纲已就绪', 'Outline ready'),
    StoryStatus.running => tr('演绎中', 'Running'),
    StoryStatus.completed => tr('结局已达成（已验证）', 'Goal reached (verified)'),
    StoryStatus.paused => tr('已暂停', 'Paused'),
  };
  String _reason(StoryPauseReason? reason) => switch (reason) {
    StoryPauseReason.lengthLimit => tr(
      '篇幅上限已到，结局尚未达成',
      'Length limit reached; goal not achieved',
    ),
    StoryPauseReason.requestLimit => tr('请求预算已用完', 'Request budget exhausted'),
    StoryPauseReason.tokenLimit => tr(
      '已知 Token 已达阈值',
      'Known token threshold reached',
    ),
    StoryPauseReason.interruptedRestart => tr(
      '上次执行中断，等待手动继续',
      'Previous run interrupted; resume manually',
    ),
    StoryPauseReason.datasetChanged => tr(
      '数据集已更换，等待手动继续',
      'Dataset changed; resume manually',
    ),
    StoryPauseReason.storageError => tr(
      '保存失败，请重试保存',
      'Saving failed; retry saving',
    ),
    StoryPauseReason.stagnation => tr(
      '剧情进展停滞，请调整指令或目标',
      'Story progress stalled; adjust instructions or target',
    ),
    StoryPauseReason.requestError => tr(
      '请求失败，请检查配置后重试',
      'Request failed; check configuration and retry',
    ),
    StoryPauseReason.background => tr(
      '应用进入后台，已停止',
      'Stopped when app entered background',
    ),
    StoryPauseReason.leftPage => tr('离开页面后已停止', 'Stopped after leaving page'),
    _ => '',
  };
  Widget _avatar(StoryActorSnapshot actor) => CircleAvatar(
    radius: 18,
    child: actor.avatarRelativePath == null
        ? Text(actor.name.characters.first)
        : ClipOval(
            child: Image.file(
              File('$_root/${actor.avatarRelativePath}'),
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Text(actor.name.characters.first),
            ),
          ),
  );

  Widget _controls(AutoStoryDocument s) {
    final busy = _runner.isBusy,
        blocked = busy || _runner.pendingSave || _editing;
    Widget button(
      String key,
      String zh,
      String en,
      Future<void> Function() action, {
      bool enabled = true,
      bool primary = false,
    }) => primary
        ? FilledButton(
            key: ValueKey(key),
            onPressed: enabled ? () => _action(action) : null,
            child: Text(tr(zh, en)),
          )
        : OutlinedButton(
            key: ValueKey(key),
            onPressed: enabled ? () => _action(action) : null,
            child: Text(tr(zh, en)),
          );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer.withValues(
        alpha: widget.settings.navigationBarOpacity,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (s.status == StoryStatus.draft || s.plan.isEmpty)
                button(
                  'auto-story-plan',
                  '生成剧情大纲',
                  'Generate outline',
                  _runner.generatePlan,
                  enabled: !blocked,
                  primary: true,
                ),
              if (s.status == StoryStatus.ready)
                button(
                  'auto-story-start',
                  '确认并开始演绎',
                  'Confirm and start',
                  () => _start(),
                  enabled: !blocked && s.plan.isNotEmpty,
                  primary: true,
                ),
              if (s.status == StoryStatus.paused) ...[
                button(
                  'auto-story-continue',
                  '继续',
                  'Continue',
                  () => _start(),
                  enabled: !blocked && s.plan.isNotEmpty,
                  primary: true,
                ),
                button(
                  'auto-story-step-round',
                  '只演一轮',
                  'One round',
                  () => _start(singleRound: true),
                  enabled: !blocked && s.plan.isNotEmpty,
                ),
                button(
                  'auto-story-takeover',
                  '接管 B 一次',
                  'Take over B',
                  _takeover,
                  enabled: !blocked && s.nextActor == 'B',
                ),
              ],
              if (busy || s.status == StoryStatus.running) ...[
                button('auto-story-pause', '暂停', 'Pause', () async {
                  await _speech.stop();
                  await _runner.requestPause();
                }, enabled: !s.pauseAfterCurrent),
                button('auto-story-stop', '立即停止', 'Stop immediately', _stop),
              ],
              if (s.status != StoryStatus.draft &&
                  s.status != StoryStatus.completed)
                button(
                  'auto-story-director',
                  '导演指令',
                  'Director instruction',
                  _director,
                  enabled: !_runner.pendingSave && !_editing,
                ),
              if (s.status == StoryStatus.ready)
                button(
                  'auto-story-outline',
                  '查看与编辑大纲',
                  'Review outline',
                  _outline,
                  enabled: !blocked,
                ),
              if (s.status == StoryStatus.completed)
                button(
                  'auto-story-completed-export',
                  '导出',
                  'Export',
                  _export,
                  enabled: !blocked,
                  primary: true,
                ),
              if (!blocked &&
                  [
                    StoryStatus.paused,
                    StoryStatus.completed,
                  ].contains(s.status) &&
                  s.turns.lastOrNull?.source == StoryTurnSource.ai)
                button(
                  'auto-story-regenerate',
                  '重生成最后一条',
                  'Regenerate last',
                  _regenerate,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _authorized ? _runner.story : null;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_stop(StoryPauseReason.leftPage));
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s?.config.title ?? tr('故事演绎', 'Story performance')),
          actions: s == null
              ? []
              : [
                  IconButton(
                    key: const ValueKey('auto-story-export'),
                    tooltip: tr('导出', 'Export'),
                    onPressed: () => _action(_export),
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _action(switch (value) {
                      'outline' => _outline,
                      'usage' => _usage,
                      'settings' => _settings,
                      _ => _export,
                    }),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'outline',
                        child: Text(tr('查看与编辑大纲', 'Review outline')),
                      ),
                      PopupMenuItem(
                        value: 'usage',
                        child: Text(tr('用量', 'Usage')),
                      ),
                      PopupMenuItem(
                        value: 'settings',
                        child: Text(tr('故事设置', 'Story settings')),
                      ),
                    ],
                  ),
                ],
        ),
        body: AppBackground(
          settings: widget.settings,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : s == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 40),
                      Text(
                        _error ??
                            _runner.error ??
                            tr(
                              '故事受保护或不可用',
                              'Story is protected or unavailable',
                            ),
                      ),
                      TextButton(
                        onPressed: () => _load(),
                        child: Text(tr('重新读取 / 解锁', 'Reload / unlock')),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .30,
                        ),
                        child: SingleChildScrollView(
                          primary: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _avatar(s.actors[0]),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${s.actors[0].name} ↔ ${s.actors[1].name} · ${tr('AI代演', 'AI portrayal')}',
                                      ),
                                    ),
                                    _avatar(s.actors[1]),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${_status(s)} · ${s.completedRounds} / ${s.config.plannedRounds} ${tr('轮', 'rounds')}',
                                ),
                                Text(
                                  '${s.plan.isEmpty ? tr('尚未生成大纲', 'No outline yet') : s.plan[s.stageIndex.clamp(0, s.plan.length - 1)].title} · ${tr('下一位', 'Next')}: ${s.actors.firstWhere((a) => a.actorId == s.nextActor).name}',
                                ),
                                LinearProgressIndicator(
                                  value:
                                      s.turns.length /
                                      (s.config.plannedRounds * 2),
                                  semanticsLabel: tr(
                                    '篇幅使用（不是目标成功率）',
                                    'Length used (not goal probability)',
                                  ),
                                ),
                                Text(
                                  '${tr('篇幅使用', 'Length used')} · ${tr('请求', 'Requests')} ${s.usageTotals.attempts}/${s.config.maxRequests} · Token ${s.usageTotals.totalTokens}${s.usageTotals.hasUnknown ? tr('（部分未知）', ' (partially unknown)') : ''}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                if (_reason(s.pauseReason).isNotEmpty)
                                  Text(
                                    _reason(s.pauseReason),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                if (s.pauseAfterCurrent ||
                                    _runner.phase == AutoStoryRunPhase.pausing)
                                  Text(
                                    tr(
                                      '正在完成当前内容；不会开始下一请求',
                                      'Finishing current content; no new request will start',
                                    ),
                                  ),
                                if (_runner.pendingSave)
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        tr(
                                          '这条内容尚未保存',
                                          'This content has not been saved',
                                        ),
                                      ),
                                      TextButton(
                                        key: const ValueKey(
                                          'auto-story-retry-save',
                                        ),
                                        onPressed: () =>
                                            _action(_runner.retrySave),
                                        child: Text(tr('重试保存', 'Retry save')),
                                      ),
                                      TextButton(
                                        onPressed: () => _action(_stop),
                                        child: Text(
                                          tr('立即停止并放弃', 'Stop and discard'),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (_runner.error != null)
                                  Text(
                                    context.t(_runner.error!),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            ListView(
                              controller: _scroll,
                              key: const PageStorageKey('auto-story-timeline'),
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              children: [
                                if (s.turns.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      tr(
                                        '正式发言将在保存成功后出现在这里。',
                                        'Completed turns appear here after they are saved.',
                                      ),
                                    ),
                                  ),
                                for (final event in s.events.where(
                                  (e) => e.effectiveAfterOrdinal == -1,
                                ))
                                  _event(event),
                                for (final turn in s.turns) ...[
                                  AutoStoryTurnCard(
                                    key: ValueKey(turn.turnId),
                                    turn: turn,
                                    actor: s.actors.firstWhere(
                                      (a) => a.actorId == turn.speakerId,
                                    ),
                                    english: context.isEnglish,
                                    split: widget.settings.splitRoleMessages,
                                    showReasoning:
                                        widget.settings.showReasoningContent,
                                    onCollect: () =>
                                        _action(() => _collect(turn)),
                                    onSpeak:
                                        widget.settings.enableCharacterSpeech
                                        ? () => _action(() => _speak(turn))
                                        : null,
                                    onEdit:
                                        !_runner.isBusy &&
                                            (s.status == StoryStatus.paused ||
                                                s.status ==
                                                    StoryStatus.completed) &&
                                            turn.turnId ==
                                                s.turns.last.turnId &&
                                            turn.source ==
                                                StoryTurnSource.manual
                                        ? () => _action(() => _editManual(turn))
                                        : null,
                                  ),
                                  for (final event in s.events.where(
                                    (e) =>
                                        e.effectiveAfterOrdinal == turn.ordinal,
                                  ))
                                    _event(event),
                                ],
                                if (s.currentCheckpoint != null ||
                                    s.lockedFacts.isNotEmpty)
                                  _facts(s),
                                ValueListenableBuilder<AutoStoryDraft?>(
                                  valueListenable: _runner.draft,
                                  builder: (context, draft, _) => draft == null
                                      ? const SizedBox.shrink()
                                      : Align(
                                          alignment: draft.speakerId == 'B'
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: Card(
                                            child: Padding(
                                              padding: const EdgeInsets.all(14),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${s.actors.firstWhere((a) => a.actorId == draft.speakerId).name}${draft.speakerId == 'B' ? ' · ${tr('AI代演', 'AI portrayal')}' : ''} · ${tr('生成中，尚未保存', 'Generating, not saved')}',
                                                  ),
                                                  Text(draft.content),
                                                  if (widget
                                                          .settings
                                                          .showReasoningContent &&
                                                      draft
                                                          .reasoningContent
                                                          .isNotEmpty)
                                                    ExpansionTile(
                                                      key: PageStorageKey(
                                                        'auto-story-draft-reasoning-${s.id}',
                                                      ),
                                                      title: Text(
                                                        tr('推理内容', 'Reasoning'),
                                                      ),
                                                      children: [
                                                        Text(
                                                          draft
                                                              .reasoningContent,
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                            Positioned(
                              bottom: 12,
                              right: 16,
                              child: ValueListenableBuilder<bool>(
                                valueListenable: _newContent,
                                builder: (context, value, _) => value
                                    ? FilledButton.icon(
                                        onPressed: () {
                                          _nearBottom = true;
                                          _newContent.value = false;
                                          _contentChanged();
                                        },
                                        icon: const Icon(Icons.arrow_downward),
                                        label: Text(
                                          tr('回到最新', 'Jump to latest'),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .35,
                        ),
                        child: SingleChildScrollView(
                          primary: false,
                          child: _controls(s),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _event(StoryEvent event) => Card(
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainer.withValues(alpha: .75),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        '${event.kind == 'sceneTransition' ? tr('场景', 'Scene') : tr('导演 / 系统', 'Director / system')} · ${_ledgerStatus(event.status)}\n${event.content}',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
