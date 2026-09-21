import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/api_config.dart';
import '../../models/app_character.dart';
import '../../models/app_settings.dart';
import '../../models/auto_story.dart';
import '../../models/character_memory_entry.dart';
import '../../models/user_profile.dart';
import '../../models/world_book.dart';
import '../../services/auto_story/auto_story_creation.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/image_picker.dart';
import '../../utils/privacy_password_prompt.dart';
import '../../utils/page_layout.dart';
import '../../utils/snack.dart';
import '../../widgets/app_background.dart';

typedef AutoStoryEditorResult = ({AutoStoryDocument story, bool generatePlan});

class AutoStoryEditorScreen extends StatefulWidget {
  const AutoStoryEditorScreen({
    required this.storage,
    required this.settings,
    this.story,
    super.key,
  });
  final LocalStorageService storage;
  final AppSettings settings;
  final AutoStoryDocument? story;
  @override
  State<AutoStoryEditorScreen> createState() => _AutoStoryEditorScreenState();
}

class _AutoStoryEditorScreenState extends State<AutoStoryEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  List<AppCharacter> _characters = [];
  List<WorldBook> _books = [];
  final _selectedBooks = <String>{};
  AppCharacter? _character;
  ApiConfig _api = ApiConfig();
  String? _endpointA, _endpointB;
  String _length = 'standard', _avatarB = '';
  bool _loading = true,
      _busy = false,
      _importMemory = false,
      _confirmed = false;
  String? _error;
  late final int _epoch;
  int _selectionGeneration = 0;
  bool _budgetEdited = false;
  void _updateDefaultBudget(String value) {
    if (_editing || _budgetEdited) return;
    final rounds = int.tryParse(value);
    if (rounds != null && rounds >= 10 && rounds <= 300) {
      field('requests').text = '${2 * rounds + 2 * ((rounds + 4) ~/ 5) + 10}';
    }
  }

  bool get _editing => widget.story != null;
  TextEditingController field(String name) =>
      _fields.putIfAbsent(name, TextEditingController.new);
  @override
  void initState() {
    super.initState();
    _epoch = widget.storage.datasetEpoch;
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final chars = await widget.storage.loadCharacters();
      final api = await widget.storage.loadApiConfig();
      final profile = (await widget.storage.loadSettings()).userProfile;
      if (!mounted) return;
      _characters = chars;
      _api = api;
      final existing = widget.story;
      field('title').text = existing?.config.title ?? '';
      field('opening').text = existing?.config.opening ?? '';
      field('ending').text = existing?.config.targetEnding ?? '';
      field('style').text = existing?.config.style ?? '';
      field('rounds').text = '${existing?.config.plannedRounds ?? 80}';
      field('delay').text = '${existing?.config.interTurnDelayMs ?? 1000}';
      field('requests').text = '${existing?.config.maxRequests ?? 202}';
      field('tokens').text = existing?.config.tokenLimit?.toString() ?? '';
      field('bName').text = existing?.actors[1].name ?? profile.name;
      field('bPersona').text =
          existing?.actors[1].persona ??
          [
            profile.description,
            profile.personality,
            profile.extraPrompt,
          ].where((s) => s.isNotEmpty).join('\n\n');
      field('bStyle').text = _editing ? '' : profile.speakingStyle;
      field('publicA').text = existing?.actors[0].publicProfile ?? '';
      field('publicB').text = existing?.actors[1].publicProfile ?? profile.name;
      _avatarB = profile.avatar;
      _endpointA =
          existing?.actors[0].endpointId ?? api.effectiveEndpoint('')?.id;
      _endpointB = existing?.actors[1].endpointId ?? _endpointA;
      _length = existing?.config.replyLengthPreset ?? 'standard';
      _confirmed = _editing;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectCharacter(AppCharacter character) async {
    final generation = ++_selectionGeneration;
    final settings = await widget.storage.loadSettings();
    if (!mounted || generation != _selectionGeneration) return;
    if (character.isLocked &&
        !await verifyPrivacyPassword(
          context: context,
          settings: settings,
          storage: widget.storage,
          title: context.t('解锁私密内容'),
        )) {
      return;
    }
    if (!mounted || generation != _selectionGeneration) return;
    final books = (await widget.storage.loadWorldBooks())
        .where((b) => character.worldBookIds.contains(b.id) && b.enabled)
        .toList();
    if (!mounted || generation != _selectionGeneration) return;
    setState(() {
      _character = character;
      _books = books;
      _selectedBooks.clear();
      _importMemory = false;
      _confirmed = false;
      field('publicA').text = character.name;
      _endpointA = _api.effectiveEndpoint(character.defaultEndpointId)?.id;
      _endpointB = _endpointA;
    });
  }

  AiEndpointConfig? endpoint(String? id) =>
      id == null ? null : _api.endpointById(id);
  Future<void> _previewBook(WorldBook book) async {
    try {
      final entries = await widget.storage.loadWorldBookEntries(book.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(c.t('世界书快照预览')),
          content: SingleChildScrollView(
            child: SelectableText(
              [
                book.name,
                for (final entry in entries.where((e) => e.enabled))
                  '${entry.keywords.join(', ')}\n${entry.content}',
              ].join('\n\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(c.t('关闭')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) context.showSnack(e.toString());
    }
  }

  Future<void> _save(bool plan) async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_editing && _character == null) {
      context.showSnack('请选择演员 A');
      return;
    }
    if (!_confirmed) {
      context.showSnack('请确认公开介绍与资料范围');
      return;
    }
    final a = endpoint(_endpointA), b = endpoint(_endpointB);
    if (a == null ||
        b == null ||
        a.validationError != null ||
        b.validationError != null) {
      context.showSnack('请为两名演员选择可用 API');
      return;
    }
    final existing = widget.story;
    if (existing != null &&
        existing.config.targetEnding != field('ending').text.trim()) {
      if (!await showConfirmDialog(
        context: context,
        title: '修改目标结局',
        content: context.t('只重规划未来，已发生的正文保持不变。'),
      )) {
        return;
      }
      if (!mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (_epoch != widget.storage.datasetEpoch) {
        throw StateError('数据集已更新，请重新打开');
      }
      final rounds = int.parse(field('rounds').text);
      final config = StoryConfig(
        title: field('title').text,
        opening: field('opening').text,
        targetEnding: field('ending').text,
        style: field('style').text,
        plannedRounds: rounds,
        replyLengthPreset: _length,
        interTurnDelayMs: int.parse(field('delay').text),
        maxRequests: int.parse(field('requests').text),
        tokenLimit: int.tryParse(field('tokens').text),
        planVersion: (existing?.config.planVersion ?? 0) + 1,
      );
      final store = widget.storage.autoStories;
      AutoStoryDocument saved;
      if (existing == null) {
        final current = (await widget.storage.loadCharacters())
            .where((c) => c.id == _character!.id)
            .firstOrNull;
        if (current == null) throw StateError('来源角色已删除，请重新选择');
        if (current.isLocked && !_character!.isLocked) {
          throw StateError('来源隐私已变更，请重新选择角色');
        }
        final id = newAutoStoryId();
        final worldBooks = <Map<String, dynamic>>[];
        for (final book in _books.where((b) => _selectedBooks.contains(b.id))) {
          final entries = await widget.storage.loadWorldBookEntries(book.id);
          worldBooks.add({
            ...book.toJson(),
            'entries': entries
                .where((e) => e.enabled)
                .map((e) => e.toJson())
                .toList(),
          });
        }
        final memories = _importMemory
            ? (await widget.storage.loadCharacterMemories(current.id))
                  .where(
                    (m) =>
                        m.enabled &&
                        m.scope == MemoryScope.character &&
                        m.keywords.isEmpty,
                  )
                  .map((m) => m.toJson())
                  .toList()
            : <Map<String, dynamic>>[];
        final avatarA = await copyAutoStoryAvatar(
          widget.storage,
          id,
          'A',
          current.avatar,
        );
        final avatarB = await copyAutoStoryAvatar(
          widget.storage,
          id,
          'B',
          _avatarB,
        );
        if (_epoch != widget.storage.datasetEpoch) {
          throw StateError('数据集已更新，请重新打开');
        }
        saved = await store.createStory(
          buildAutoStoryDraft(
            id: id,
            character: current,
            user: UserProfile(
              name: field('bName').text,
              description: field('bPersona').text,
              speakingStyle: field('bStyle').text,
            ),
            publicA: field('publicA').text,
            publicB: field('publicB').text,
            opening: config.opening,
            targetEnding: config.targetEnding,
            endpointA: a,
            endpointB: b,
            title: config.title,
            style: config.style,
            plannedRounds: rounds,
            replyLengthPreset: _length,
            interTurnDelayMs: config.interTurnDelayMs,
            maxRequests: config.maxRequests,
            tokenLimit: config.tokenLimit,
            avatarA: avatarA,
            avatarB: avatarB,
            worldBooks: worldBooks,
            memories: memories,
          ),
        );
      } else {
        if (rounds * 2 < existing.turns.length) {
          throw StateError('新长度不能小于已完成正文');
        }
        saved = await store.mutateStory(existing.id, (latest) {
          if (latest.status == StoryStatus.running) throw StateError('请先暂停演绎');
          final replanned = latest.copyWith(
            config: config.copyWith(
              title: config.title.trim().isEmpty
                  ? latest.config.title
                  : config.title,
            ),
            actors: [
              latest.actors[0].copyWith(
                publicProfile: field('publicA').text,
                endpointId: a.id,
                model: a.model,
              ),
              latest.actors[1].copyWith(
                publicProfile: field('publicB').text,
                endpointId: b.id,
                model: b.model,
              ),
            ],
            runGeneration: latest.runGeneration + 1,
            status: StoryStatus.paused,
            pauseReason: StoryPauseReason.userPause,
            plan: [],
            clearCurrentCheckpoint: true,
            goalStatus: 'pending',
          );
          return AutoStoryDocument.fromJson({
            ...replanned.toJson(),
            'replanSummary':
                latest.currentCheckpoint?.summary ??
                latest.toJson()['replanSummary'] ??
                '',
            'replanCoveredThroughOrdinal':
                latest.currentCheckpoint?.coveredThroughOrdinal ??
                latest.toJson()['replanCoveredThroughOrdinal'] ??
                -1,
            'replanStartRound': (latest.turns.length + 1) ~/ 2,
            'replanStageIndex': 0,
          });
        }, expectedRevision: existing.revision);
      }
      if (mounted) {
        Navigator.of(
          context,
        ).pop<AutoStoryEditorResult>((story: saved, generatePlan: plan));
      }
    } catch (e) {
      if (mounted) context.showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _text(
    String name,
    String title, {
    int lines = 1,
    int max = 4000,
    bool required = false,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: ValueKey('auto-story-$name'),
      controller: field(name),
      enabled: enabled && !_busy,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 6,
      maxLength: max,
      decoration: InputDecoration(
        labelText: context.t(title),
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (value) =>
          required && (value ?? '').trim().isEmpty ? context.t('此项不能为空') : null,
    ),
  );
  Widget _number(String name, String title, int min, int max) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: ValueKey('auto-story-$name'),
      controller: field(name),
      enabled: !_busy,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: context.t(title)),
      onChanged: (value) {
        if (name == 'requests') _budgetEdited = true;
        if (name == 'rounds') _updateDefaultBudget(value);
      },
      validator: (value) {
        final n = int.tryParse(value ?? '');
        return n == null || n < min || n > max ? '$min–$max' : null;
      },
    ),
  );
  Widget _apiPicker(bool a) {
    final selected = a ? _endpointA : _endpointB;
    final items = _api.enabledEndpoints;
    return DropdownButtonFormField<String>(
      key: ValueKey('auto-story-endpoint-${a ? 'A' : 'B'}-$selected'),
      initialValue: items.any((e) => e.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.t(a ? '演员 A 模型' : '演员 B 模型'),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e.id,
              child: Text(
                '${e.name} · ${e.model}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _busy
          ? null
          : (id) => setState(() {
              if (a) {
                _endpointA = id;
              } else {
                _endpointB = id;
              }
            }),
    );
  }

  @override
  Widget build(BuildContext context) => AppBackground(
    settings: widget.settings,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(context.t(_editing ? '故事设置' : '新建故事'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : AdaptivePage(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(context.t('本模式会连续调用你配置的 AI 接口，演员和剧情检查均可能计费。')),
                    Text(context.t('两方人设与剧情将发送到所选模型服务商；不操作 QQ 或现实工具。')),
                    _text('title', '故事标题', max: 200),
                    if (!_editing)
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: context.t('演员 A'),
                        ),
                        isExpanded: true,
                        items: _characters
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  '${c.isLocked ? '🔒 ' : ''}${c.name}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (id) {
                                if (id != null) {
                                  unawaited(
                                    _selectCharacter(
                                      _characters.firstWhere((c) => c.id == id),
                                    ),
                                  );
                                }
                              },
                      )
                    else
                      Text(
                        '${context.t('演员 A')}：${widget.story!.actors[0].name}',
                      ),
                    if (_character != null)
                      ExpansionTile(
                        title: Text(context.t('角色人设快照')),
                        children: [
                          Text(
                            [
                              _character!.description,
                              _character!.personality,
                              _character!.background,
                              _character!.speakingStyle,
                              _character!.extraPrompt,
                            ].join('\n'),
                          ),
                        ],
                      ),
                    _text('publicA', 'A 的公开介绍', lines: 2, required: true),
                    Text(context.t('演员 B · 由 AI 代演，不代表本人真实表达')),
                    _text(
                      'bName',
                      '分身名称',
                      max: 200,
                      required: true,
                      enabled: !_editing,
                    ),
                    _text(
                      'bPersona',
                      '分身人设（仅本故事）',
                      lines: 3,
                      max: 16000,
                      enabled: !_editing,
                    ),
                    _text('bStyle', '分身说话风格', lines: 2, enabled: !_editing),
                    if (!_editing)
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final picked = await pickImage(widget.storage);
                                if (picked != null && mounted) {
                                  setState(() => _avatarB = picked.path);
                                }
                              },
                        icon: const Icon(Icons.image_outlined),
                        label: Text(context.t('选择分身头像')),
                      ),
                    _text('publicB', 'B 的公开介绍', lines: 2, required: true),
                    _text(
                      'opening',
                      '起始场景',
                      lines: 3,
                      required: true,
                      enabled: !_editing || widget.story!.turns.isEmpty,
                    ),
                    _text('ending', '目标结局', lines: 3, required: true),
                    _text('style', '剧情风格', max: 2000),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in ['日常', '甜', '慢热', '轻喜剧', '悬疑'])
                          ActionChip(
                            label: Text(context.t(s)),
                            onPressed: () => field('style').text = s,
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final n in [30, 80, 150])
                          ActionChip(
                            label: Text('$n ${context.t('轮')}'),
                            onPressed: _busy
                                ? null
                                : () {
                                    field('rounds').text = '$n';
                                    _updateDefaultBudget('$n');
                                  },
                          ),
                      ],
                    ),
                    _number('rounds', '计划轮数（10–300）', 10, 300),
                    DropdownButtonFormField<String>(
                      initialValue: _length,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.t('单条目标长度'),
                      ),
                      items: [
                        for (final v in [
                          ('short', '简短 40–120 字'),
                          ('standard', '标准 80–220 字'),
                          ('detailed', '细腻 150–400 字'),
                        ])
                          DropdownMenuItem(
                            value: v.$1,
                            child: Text(
                              context.t(v.$2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _length = v!),
                    ),
                    _apiPicker(true),
                    _apiPicker(false),
                    _number('delay', '发言间隔（毫秒）', 0, 10000),
                    ExpansionTile(
                      title: Text(context.t('请求预算与用量保护')),
                      children: [
                        _number('requests', '最大请求数', 1, 100000),
                        TextFormField(
                          controller: field('tokens'),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.t('Token 停止阈值（可留空）'),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? null
                              : (int.tryParse(v) ?? 0) > 0
                              ? null
                              : context.t('请输入正整数'),
                        ),
                        Text(
                          context.t('增加轮数不会自动提高已有故事的请求配额；用量缺失时 Token 阈值可能不可靠。'),
                        ),
                      ],
                    ),
                    if (!_editing) ...[
                      Text(context.t('仅导入勾选的已引用世界书；未命中关键词不注入。')),
                      for (final book in _books)
                        CheckboxListTile(
                          title: Text(book.name),
                          secondary: IconButton(
                            tooltip: context.t('世界书快照预览'),
                            icon: const Icon(Icons.preview_outlined),
                            onPressed: _busy ? null : () => _previewBook(book),
                          ),
                          subtitle: Text(book.description),
                          value: _selectedBooks.contains(book.id),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  v == true
                                      ? _selectedBooks.add(book.id)
                                      : _selectedBooks.remove(book.id);
                                }),
                        ),
                      CheckboxListTile(
                        value: _importMemory,
                        title: Text(context.t('导入 A 的长期记忆私有快照')),
                        subtitle: Text(context.t('不读取普通聊天历史，不写回普通记忆。')),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _importMemory = v ?? false),
                      ),
                    ],
                    CheckboxListTile(
                      value: _confirmed,
                      title: Text(context.t('已确认双方公开介绍与资料范围')),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _confirmed = v ?? false),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: _busy ? null : () => _save(false),
                          child: Text(context.t('保存草稿')),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : () => _save(true),
                          child: Text(context.t('生成剧情大纲')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}
