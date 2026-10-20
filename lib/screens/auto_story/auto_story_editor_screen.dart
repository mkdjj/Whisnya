import 'dart:async';
import 'dart:io';
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
import '../../utils/page_layout.dart';
import '../../utils/privacy_password_prompt.dart';
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
  final _actors = <_CastDraft>[];
  final _selectedBooks = <String>{};
  List<AppCharacter> _characters = [];
  List<WorldBook> _books = [];
  ApiConfig _api = ApiConfig();
  UserProfile _profile = const UserProfile();
  String _root = '', _length = 'standard';
  String? _error;
  bool _loading = true,
      _busy = false,
      _confirmed = false,
      _budgetEdited = false;
  late final int _epoch;
  bool get _editing => widget.story != null;
  bool get _canEditCast => widget.story?.turns.isEmpty ?? true;
  TextEditingController field(String key) =>
      _fields.putIfAbsent(key, TextEditingController.new);
  Set<String> get _availableBooks => {
    for (final actor in _actors)
      for (final character in _characters.where((c) => c.id == actor.sourceId))
        ...character.worldBookIds,
  };

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
    for (final actor in _actors) {
      actor.dispose();
    }
    super.dispose();
  }

  void _updateBudget() {
    if (!_editing && !_budgetEdited) {
      field('requests').text =
          '${storyRequestBudget(int.tryParse(field('rounds').text) ?? 80, _actors.length)}';
    }
  }

  void _useProfile(_CastDraft actor) {
    actor.sourceId = 'userProfile';
    actor.selectedSource = null;
    actor.lockedSource = false;
    actor.name.text = _profile.name.trim().isEmpty ? '我' : _profile.name;
    actor.persona.text = [
      _profile.description,
      _profile.personality,
      _profile.speakingStyle,
      _profile.extraPrompt,
    ].where((s) => s.trim().isNotEmpty).join('\n\n');
    actor.publicProfile.text = actor.name.text;
    actor.avatar = _profile.avatar;
    actor.importMemory = false;
  }

  Future<void> _load() async {
    try {
      _characters = await widget.storage.loadCharacters();
      _api = await widget.storage.loadApiConfig();
      _profile = (await widget.storage.loadSettings()).userProfile;
      _books = (await widget.storage.loadWorldBooks())
          .where((b) => b.enabled)
          .toList();
      _root = (await widget.storage.appDataDirectory).path;
      if (!mounted) return;
      final story = widget.story;
      for (final item in <String, String>{
        'title': story?.config.title ?? '',
        'opening': story?.config.opening ?? '',
        'ending': story?.config.targetEnding ?? '',
        'style': story?.config.style ?? '',
        'rounds': '${story?.config.plannedRounds ?? 80}',
        'delay': '${story?.config.interTurnDelayMs ?? 1000}',
        'tokens': story?.config.tokenLimit?.toString() ?? '',
        'requests': '${story?.config.maxRequests ?? 122}',
      }.entries) {
        field(item.key).text = item.value;
      }
      if (story == null) {
        final actor = _CastDraft(endpointId: _api.effectiveEndpoint('')?.id);
        _useProfile(actor);
        _actors.add(actor);
      } else {
        _actors.addAll(story.actors.map(_CastDraft.fromSnapshot));
      }
      _length = story?.config.replyLengthPreset ?? 'standard';
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

  Future<void> _useCharacter(_CastDraft draft, AppCharacter character) async {
    final settings = await widget.storage.loadSettings();
    if (!mounted) return;
    if (character.isLocked &&
        !await verifyPrivacyPassword(
          context: context,
          settings: settings,
          storage: widget.storage,
          title: context.t('解锁私密内容'),
        )) {
      return;
    }
    if (!mounted || draft.disposed) return;
    draft.sourceId = character.id;
    draft.selectedSource = character;
    draft.lockedSource = character.isLocked;
    draft.name.text = character.name;
    draft.persona.text = [
      character.description,
      character.personality,
      character.background,
      character.speakingStyle,
      character.extraPrompt,
    ].where((s) => s.trim().isNotEmpty).join('\n\n');
    draft.publicProfile.text = character.name;
    draft.avatar = character.avatar;
    draft.endpointId = _api.effectiveEndpoint(character.defaultEndpointId)?.id;
    draft.importMemory = false;
  }

  Widget _avatar(_CastDraft actor, String id) {
    final path = actor.avatar.startsWith('media/')
        ? '$_root/${actor.avatar}'
        : actor.avatar;
    return CircleAvatar(
      radius: 20,
      foregroundImage: path.isEmpty ? null : FileImage(File(path)),
      onForegroundImageError: path.isEmpty ? null : (_, _) {},
      child: Text(id),
    );
  }

  Widget _modelPicker(
    String? selected,
    ValueChanged<String?> onChanged, {
    String label = '模型',
  }) => DropdownButtonFormField<String>(
    key: ValueKey('story-model-$label-$selected'),
    initialValue: _api.enabledEndpoints.any((e) => e.id == selected)
        ? selected
        : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: context.t(label)),
    hint: Text(context.t('请选择模型')),
    items: [
      for (final api in _api.enabledEndpoints)
        DropdownMenuItem(
          value: api.id,
          child: Text(
            '${api.name} · ${api.model}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: _busy ? null : onChanged,
  );

  Future<void> _editActor([int? index]) async {
    final draft = index == null
        ? _CastDraft(endpointId: _actors.first.endpointId)
        : _actors[index].copy();
    final id = storyActorId(index ?? _actors.length);
    final form = GlobalKey<FormState>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Row(
                    children: [
                      _avatar(draft, id),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '演员 $id${draft.isUser ? ' · 主角' : ''}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_canEditCast) ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.t('从已有角色选择（可选）'),
                      ),
                      items: [
                        for (final c in _characters)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              '${c.isLocked ? '🔒 ' : ''}${c.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        await _useCharacter(
                          draft,
                          _characters.firstWhere((c) => c.id == value),
                        );
                        if (sheetContext.mounted) refresh(() {});
                      },
                    ),
                    if (index == 0 || draft.isUser)
                      TextButton.icon(
                        onPressed: () => refresh(() => _useProfile(draft)),
                        icon: const Icon(Icons.person_outline),
                        label: Text(context.t('使用用户设定（主角）')),
                      ),
                    const SizedBox(height: 12),
                  ],
                  _actorText(
                    draft.name,
                    '名称',
                    enabled: _canEditCast,
                    required: true,
                    max: 200,
                  ),
                  _actorText(
                    draft.persona,
                    '人设（仅本故事）',
                    enabled: _canEditCast,
                    lines: 4,
                    max: 20000,
                  ),
                  _actorText(draft.publicProfile, '公开介绍（其他演员可见）', lines: 2),
                  _modelPicker(
                    draft.endpointId,
                    (value) => refresh(() => draft.endpointId = value),
                  ),
                  if (_canEditCast)
                    TextButton.icon(
                      onPressed: () async {
                        final image = await pickImage(widget.storage);
                        if (image != null && sheetContext.mounted) {
                          refresh(() => draft.avatar = image.path);
                        }
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: Text(context.t('选择头像')),
                    ),
                  const SizedBox(height: 12),
                  Text(context.t('完整人设仅发给该演员的模型，其他演员只看到公开介绍。')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.of(sheetContext).pop(true);
                      }
                    },
                    child: Text(context.t('完成')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        if (index == null) {
          _actors.add(draft);
        } else {
          _actors[index].dispose();
          _actors[index] = draft;
        }
        _selectedBooks.removeWhere((id) => !_availableBooks.contains(id));
        _confirmed = false;
        _updateBudget();
      });
    } else {
      draft.dispose();
    }
  }

  Widget _actorText(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    bool required = false,
    int lines = 1,
    int max = 4000,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 8,
      maxLength: max,
      decoration: InputDecoration(
        labelText: context.t(label),
        counterText: '',
        alignLabelWithHint: lines > 1,
      ),
      validator: (value) =>
          required && (value ?? '').trim().isEmpty ? context.t('此项不能为空') : null,
    ),
  );

  Future<List<StoryActorSnapshot>> _snapshots(String storyId) async {
    final characters = await widget.storage.loadCharacters();
    final result = <StoryActorSnapshot>[];
    for (var i = 0; i < _actors.length; i++) {
      final draft = _actors[i], selected = draft.selectedSource;
      if (selected != null) {
        final current = characters
            .where((c) => c.id == selected.id)
            .firstOrNull;
        if (current == null || (current.isLocked && !selected.isLocked)) {
          throw StateError('来源角色已删除或隐私已变更，请重新选择');
        }
      }
      final id = storyActorId(i);
      final avatar = draft.avatar.startsWith('media/auto_stories/$storyId/')
          ? draft.avatar
          : await copyAutoStoryAvatar(
              widget.storage,
              storyId,
              id,
              draft.avatar,
            );
      final api = _api.endpointById(draft.endpointId!)!;
      result.add(
        StoryActorSnapshot(
          actorId: id,
          sourceId: draft.sourceId,
          name: draft.name.text.trim(),
          persona: draft.persona.text.trim(),
          publicProfile: draft.publicProfile.text.trim().isEmpty
              ? draft.name.text.trim()
              : draft.publicProfile.text.trim(),
          avatarRelativePath: avatar,
          endpointId: api.id,
          model: api.model,
          lockedSource: draft.lockedSource,
        ),
      );
    }
    if (_epoch != widget.storage.datasetEpoch) throw StateError('数据集已更新，请重新打开');
    return result;
  }

  Future<void> _save(bool generatePlan) async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_actors.any((a) => a.name.text.trim().isEmpty)) {
      context.showSnack('请填写每位演员的名称');
      return;
    }
    if (!_confirmed) {
      context.showSnack('请确认设定和 AI 代演');
      return;
    }
    if (_actors.any((a) {
      final api = a.endpointId == null
          ? null
          : _api.endpointById(a.endpointId!);
      return api == null || !api.enabled || api.validationError != null;
    })) {
      context.showSnack('请为每位演员选择可用模型');
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
      final id = existing?.id ?? newAutoStoryId();
      final actors = await _snapshots(id);
      final config = StoryConfig(
        title: field('title').text.trim().isEmpty
            ? '${actors.first.name} · 故事演绎'
            : field('title').text.trim(),
        opening: field('opening').text.trim(),
        targetEnding: field('ending').text.trim(),
        style: field('style').text.trim(),
        plannedRounds: int.parse(field('rounds').text),
        replyLengthPreset: _length,
        interTurnDelayMs: int.parse(field('delay').text),
        maxRequests: int.parse(field('requests').text),
        tokenLimit: int.tryParse(field('tokens').text),
        planVersion: (existing?.config.planVersion ?? 0) + 1,
      );
      final store = widget.storage.autoStories;
      AutoStoryDocument saved;
      if (existing == null) {
        final books = <Map<String, dynamic>>[];
        for (final book in _books.where((b) => _selectedBooks.contains(b.id))) {
          final entries = await widget.storage.loadWorldBookEntries(book.id);
          books.add({
            ...book.toJson(),
            'entries': entries
                .where((e) => e.enabled)
                .map((e) => e.toJson())
                .toList(),
          });
        }
        final memories = <Map<String, dynamic>>[], seen = <String>{};
        for (final actor in _actors.where(
          (a) => a.importMemory && !a.isUser && a.sourceId != null,
        )) {
          for (final memory in await widget.storage.loadCharacterMemories(
            actor.sourceId!,
          )) {
            if (memory.enabled &&
                memory.scope == MemoryScope.character &&
                seen.add(memory.id)) {
              memories.add(memory.toJson());
            }
          }
        }
        if (_epoch != widget.storage.datasetEpoch) {
          throw StateError('数据集已更新，请重新打开');
        }
        saved = await store.createStory(
          AutoStoryDocument(
            id: id,
            actors: actors,
            config: config,
            worldBookSnapshots: books,
            importedMemorySnapshots: memories,
          ),
        );
      } else {
        if (config.plannedRounds * actors.length < existing.turns.length) {
          throw StateError('新长度不能小于已完成正文');
        }
        saved = await store.mutateStory(id, (latest) {
          if (latest.status == StoryStatus.running) throw StateError('请先暂停演绎');
          final updated = latest.copyWith(
            actors: actors,
            config: config,
            runGeneration: latest.runGeneration + 1,
            status: StoryStatus.paused,
            pauseReason: StoryPauseReason.userPause,
            plan: [],
            clearCurrentCheckpoint: true,
            goalStatus: 'pending',
          );
          return AutoStoryDocument.fromJson({
            ...updated.toJson(),
            'replanSummary':
                latest.currentCheckpoint?.summary ?? latest.replanSummary,
            'replanCoveredThroughOrdinal':
                latest.currentCheckpoint?.coveredThroughOrdinal ??
                latest.replanCoveredThroughOrdinal,
            'replanStartRound': latest.startedRounds,
            'replanStageIndex': 0,
          });
        }, expectedRevision: existing.revision);
      }
      if (mounted) {
        Navigator.of(context).pop<AutoStoryEditorResult>((
          story: saved,
          generatePlan: generatePlan,
        ));
      }
    } catch (e) {
      if (mounted) context.showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                context.t(title),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _text(
    String key,
    String label, {
    int lines = 1,
    bool required = false,
    bool enabled = true,
  }) => _actorText(
    field(key),
    label,
    lines: lines,
    required: required,
    enabled: enabled,
    max: key == 'title'
        ? 200
        : key == 'style'
        ? 2000
        : 4000,
  );

  Widget _number(String key, String label, int min, int max) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: field(key),
      enabled: !_busy,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: context.t(label)),
      onChanged: (_) {
        if (key == 'requests') _budgetEdited = true;
        if (key == 'rounds') _updateBudget();
      },
      validator: (value) {
        final number = int.tryParse(value ?? '');
        return number == null || number < min || number > max
            ? '$min–$max'
            : null;
      },
    ),
  );

  Widget _actorCard(int index) {
    final actor = _actors[index], id = storyActorId(index);
    final api = actor.endpointId == null
        ? null
        : _api.endpointById(actor.endpointId!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _avatar(actor, id),
      title: Text(
        '${actor.name.text} · ${actor.isUser ? '主角 ' : '演员 '}$id',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${actor.isUser
            ? '用户设定'
            : actor.sourceId == null
            ? '自定义人设'
            : '角色快照'} · ${api?.name ?? '未选模型'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: _busy ? null : () => _editActor(index),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_canEditCast || index == 0)
            const Icon(Icons.chevron_right, size: 20),
          if (_canEditCast && index > 0)
            IconButton(
              tooltip: context.t('移除演员'),
              icon: const Icon(Icons.close, size: 20),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _actors.removeAt(index).dispose();
                      _selectedBooks.removeWhere(
                        (id) => !_availableBooks.contains(id),
                      );
                      _confirmed = false;
                      _updateBudget();
                    }),
            ),
        ],
      ),
    );
  }

  Widget _moreSettings() => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 16),
    child: ExpansionTile(
      title: Text(context.t('更多设置')),
      subtitle: Text(context.t('风格、资料导入与请求预算')),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _text('style', '剧情风格（可选）'),
        _number('delay', '发言间隔（毫秒）', 0, 10000),
        _number('requests', '最大请求数', 1, 100000),
        TextFormField(
          controller: field('tokens'),
          keyboardType: TextInputType.number,
          enabled: !_busy,
          decoration: InputDecoration(labelText: context.t('Token 停止阈值（可留空）')),
          validator: (v) => v == null || v.isEmpty || (int.tryParse(v) ?? 0) > 0
              ? null
              : context.t('请输入正整数'),
        ),
        if (!_editing) ...[
          for (final actor in _actors.where(
            (a) => a.sourceId != null && !a.isUser,
          ))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('导入 ${actor.name.text} 的长期记忆'),
              subtitle: Text(context.t('仅本故事使用，不读取普通聊天历史。')),
              value: actor.importMemory,
              onChanged: _busy
                  ? null
                  : (value) =>
                        setState(() => actor.importMemory = value ?? false),
            ),
          if (_availableBooks.isNotEmpty) ...[
            const Divider(),
            Text(context.t('世界书（仅导入手动勾选的已引用资源）')),
            for (final book in _books.where(
              (b) => _availableBooks.contains(b.id),
            ))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(book.name),
                subtitle: Text(
                  book.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _selectedBooks.contains(book.id),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _selectedBooks.add(book.id);
                        } else {
                          _selectedBooks.remove(book.id);
                        }
                      }),
              ),
          ],
        ],
        const SizedBox(height: 8),
        Text(context.t('每位演员每轮会调用一次模型，导演检查另外计费；可随时暂停。')),
      ],
    ),
  );

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
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section('故事', Icons.auto_stories_outlined, [
                      _text('title', '故事名称（可留空）'),
                      _text(
                        'opening',
                        '从哪里开始？',
                        lines: 3,
                        required: true,
                        enabled: !_editing || widget.story!.turns.isEmpty,
                      ),
                      _text('ending', '希望走向怎样的结局？', lines: 3, required: true),
                    ]),
                    _section('演员', Icons.people_outline, [
                      Text(context.t('演员 A 默认使用用户设定。点卡片编辑人设、头像和独立模型。')),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _actors.length; i++) _actorCard(i),
                      if (_canEditCast && _actors.length < maxStoryActors)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _editActor(),
                          icon: const Icon(Icons.person_add_outlined),
                          label: Text('添加演员 ${storyActorId(_actors.length)}'),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '${_actors.length} 人 · 每人发言一次算一轮${_canEditCast ? '' : ' · 已开始的故事固定阵容'}',
                      ),
                    ]),
                    _section('篇幅与模型', Icons.tune, [
                      _modelPicker(
                        _actors.map((a) => a.endpointId).toSet().length == 1
                            ? _actors.first.endpointId
                            : null,
                        (value) => setState(() {
                          for (final actor in _actors) {
                            actor.endpointId = value;
                          }
                        }),
                        label: '统一模型',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final rounds in [30, 80, 150])
                            ActionChip(
                              label: Text('$rounds 轮'),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      field('rounds').text = '$rounds';
                                      _updateBudget();
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _number('rounds', '计划轮数（10–300）', 10, 300),
                      DropdownButtonFormField<String>(
                        initialValue: _length,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.t('单条回复长度'),
                        ),
                        items: [
                          for (final item in [
                            ('short', '简短'),
                            ('standard', '标准'),
                            ('detailed', '细腻'),
                          ])
                            DropdownMenuItem(
                              value: item.$1,
                              child: Text(context.t(item.$2)),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _length = value!),
                      ),
                    ]),
                    _moreSettings(),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _confirmed,
                      title: Text(context.t('已确认设定，并允许 AI 代演')),
                      subtitle: Text(context.t('角色资料和剧情会发送至所选模型服务商，仅用于虚构故事。')),
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _confirmed = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => _save(false),
                            child: Text(context.t('保存草稿')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : () => _save(true),
                            child: Text(context.t('生成剧情大纲')),
                          ),
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

class _CastDraft {
  _CastDraft({
    String name = '',
    String persona = '',
    String publicProfile = '',
    this.sourceId,
    this.endpointId,
    this.avatar = '',
    this.lockedSource = false,
    this.selectedSource,
    this.importMemory = false,
  }) : name = TextEditingController(text: name),
       persona = TextEditingController(text: persona),
       publicProfile = TextEditingController(text: publicProfile);
  factory _CastDraft.fromSnapshot(StoryActorSnapshot actor) => _CastDraft(
    name: actor.name,
    persona: actor.persona,
    publicProfile: actor.publicProfile,
    sourceId: actor.sourceId,
    endpointId: actor.endpointId,
    avatar: actor.avatarRelativePath ?? '',
    lockedSource: actor.lockedSource,
  );
  final TextEditingController name, persona, publicProfile;
  String? sourceId, endpointId;
  String avatar;
  bool lockedSource, importMemory;
  bool disposed = false;
  AppCharacter? selectedSource;
  bool get isUser => sourceId == 'userProfile';
  _CastDraft copy() => _CastDraft(
    name: name.text,
    persona: persona.text,
    publicProfile: publicProfile.text,
    sourceId: sourceId,
    endpointId: endpointId,
    avatar: avatar,
    lockedSource: lockedSource,
    selectedSource: selectedSource,
    importMemory: importMemory,
  );
  void dispose() {
    disposed = true;
    name.dispose();
    persona.dispose();
    publicProfile.dispose();
  }
}
