part of 'theater_screens.dart';

class TheaterEditScreen extends StatefulWidget {
  const TheaterEditScreen({
    required this.storage,
    required this.aiService,
    this.session,
    this.initialUserProfile,
    super.key,
  });

  final LocalStorageService storage;
  final AiGateway aiService;
  final TheaterSession? session;
  final UserProfile? initialUserProfile;

  @override
  State<TheaterEditScreen> createState() => _TheaterEditScreenState();
}

class _TheaterEditScreenState extends State<TheaterEditScreen> {
  final _titleController = TextEditingController();
  final _customRoundsController = TextEditingController(text: '10');
  var _characters = <AppCharacter>[];
  var _novels = <NovelBook>[];
  var _apiConfig = ApiConfig();
  var _bubblePresets = const ChatBubblePresetSettings();
  var _selectedParticipants = <TheaterParticipant>[];
  var _boundNovelId = '';
  var _avatar = '';
  var _backgroundImage = '';
  var _backgroundImageRegion = ImageCropRegion.full;
  var _backgroundImageOpacity = 1.0;
  var _backgroundBlur = 0.0;
  var _bubbleTheme = ChatBubbleTheme.theaterDefault;
  var _roleBubblePresetId = '';
  var _userBubblePresetId = '';
  var _inputOpacity = 0.92;
  var _topBarOpacity = 0.0;
  var _apiMode = TheaterApiMode.singleApi;
  var _replyMode = TheaterMultiApiReplyMode.turnBased;
  var _singleEndpointId = '';
  var _userParticipantId = '';
  var _keepRoundCount = 30;
  var _mainReplyCount = 0;
  var _extraReplyMode = 0;
  var _useCustomRounds = false;
  var _isLoading = true;
  var _isSaving = false;
  var _speakerSequenceChanged = false;

  bool get _isEditing => widget.session != null;

  int get _replyParticipantCount => _selectedParticipants
      .where(
        (participant) =>
            participant.enabled &&
            !participant.isMuted &&
            participant.id != _userParticipantId,
      )
      .length;

  NovelBook? get _boundNovel {
    for (final book in _novels) {
      if (book.id == _boundNovelId) return book;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    if (session != null) {
      _titleController.text = session.title;
      _avatar = session.avatar;
      _backgroundImage = session.backgroundImage;
      _backgroundImageRegion = session.backgroundImageRegion;
      _backgroundImageOpacity = session.backgroundImageOpacity;
      _backgroundBlur = session.backgroundBlur;
      _bubbleTheme = session.bubbleTheme;
      _roleBubblePresetId = session.roleBubblePresetId;
      _userBubblePresetId = session.userBubblePresetId;
      _inputOpacity = session.inputOpacity;
      _topBarOpacity = session.topBarOpacity;
      _boundNovelId = session.boundNovelId;
      _apiMode = session.apiMode;
      _replyMode = session.multiApiReplyMode;
      _singleEndpointId = session.singleEndpointId;
      _userParticipantId = session.userParticipantId;
      _keepRoundCount = session.keepRoundCount;
      _mainReplyCount = session.mainReplyCount;
      _extraReplyMode = session.extraReplyMode;
      _customRoundsController.text = session.keepRoundCount.toString();
      _useCustomRounds = ![15, 30, 50].contains(session.keepRoundCount);
      _selectedParticipants = [...session.participants];
    } else if (widget.initialUserProfile case final profile?) {
      final user = TheaterParticipant.fromUserProfile(
        profile,
        id: _participantId('user'),
      );
      _selectedParticipants = [user];
      _userParticipantId = user.id;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customRoundsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      widget.storage.loadCharacters(),
      widget.storage.loadNovels(),
      widget.storage.loadApiConfig(),
      widget.storage.loadChatBubblePresets(),
    ]);
    if (!mounted) return;
    setState(() {
      _characters = values[0] as List<AppCharacter>;
      _novels = values[1] as List<NovelBook>;
      _apiConfig = values[2] as ApiConfig;
      _bubblePresets = values[3] as ChatBubblePresetSettings;
      _singleEndpointId = _effectiveEndpointId(_singleEndpointId);
      _selectedParticipants = [
        for (final participant in _selectedParticipants)
          participant.copyWith(
            endpointId: _effectiveEndpointId(participant.endpointId),
          ),
      ];
      _isLoading = false;
    });
  }

  String _effectiveEndpointId(String requested) {
    if (requested.trim().isEmpty) return '';
    return _apiConfig.effectiveEndpoint(requested)?.id ?? '';
  }

  String _participantId(String prefix) {
    return 'participant_${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _isSelectedBySource(String sourceCharacterId, String sourceRoleId) {
    return _selectedParticipants.any(
      (participant) =>
          (sourceCharacterId.isNotEmpty &&
              participant.sourceCharacterId == sourceCharacterId) ||
          (sourceRoleId.isNotEmpty &&
              participant.sourceNovelId == _boundNovelId &&
              participant.sourceRoleId == sourceRoleId),
    );
  }

  void _toggleAppCharacter(AppCharacter character, bool selected) {
    setState(() {
      _speakerSequenceChanged = true;
      if (!selected) {
        _selectedParticipants.removeWhere(
          (participant) => participant.sourceCharacterId == character.id,
        );
        if (!_selectedParticipants.any(
          (item) => item.id == _userParticipantId,
        )) {
          _userParticipantId = '';
        }
        return;
      }
      if (_isSelectedBySource(character.id, '')) return;
      _selectedParticipants.add(
        TheaterParticipant.fromAppCharacter(
          character,
          id: _participantId('app'),
          endpointId: _effectiveEndpointId(character.defaultEndpointId),
        ),
      );
    });
  }

  void _toggleNovelRole(
    NovelBook book,
    NovelRoleCandidate role,
    bool selected,
  ) {
    setState(() {
      _speakerSequenceChanged = true;
      if (!selected) {
        _selectedParticipants.removeWhere(
          (participant) =>
              participant.sourceNovelId == book.id &&
              participant.sourceRoleId == role.name,
        );
        if (!_selectedParticipants.any(
          (item) => item.id == _userParticipantId,
        )) {
          _userParticipantId = '';
        }
        return;
      }
      if (_isSelectedBySource('', role.name)) return;
      _selectedParticipants.add(
        TheaterParticipant.fromNovelRole(
          book: book,
          role: role,
          id: _participantId('novel'),
          endpointId: _singleEndpointId,
        ),
      );
    });
  }

  void _setParticipantEndpoint(String participantId, String endpointId) {
    setState(() {
      _selectedParticipants = [
        for (final participant in _selectedParticipants)
          participant.id == participantId
              ? participant.copyWith(endpointId: endpointId)
              : participant,
      ];
    });
  }

  List<TheaterParticipant> get _aiParticipants => _selectedParticipants
      .where((participant) => participant.id != _userParticipantId)
      .toList();

  TheaterParticipant? get _userParticipant {
    for (final participant in _selectedParticipants) {
      if (participant.id == _userParticipantId) return participant;
    }
    return null;
  }

  Future<void> _editUserParticipant() async {
    final current = _userParticipant;
    final profile = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(
        builder: (_) => UserProfileEditScreen(
          storage: widget.storage,
          profile: current == null
              ? const UserProfile()
              : UserProfile(
                  name: current.name,
                  avatar: current.avatar,
                  description: current.description,
                  personality: current.personality,
                  speakingStyle: current.speakingStyle,
                  extraPrompt: current.background,
                ),
          title: '编辑我的身份',
        ),
      ),
    );
    if (profile == null || !mounted) return;
    final participant = TheaterParticipant.fromUserProfile(
      profile,
      id: current?.id ?? _participantId('user'),
    );
    setState(() {
      _speakerSequenceChanged = true;
      if (current == null) {
        _selectedParticipants.add(participant);
      } else {
        final index = _selectedParticipants.indexOf(current);
        _selectedParticipants[index] = participant;
      }
      _userParticipantId = participant.id;
    });
  }

  void _setParticipantMuted(String participantId, bool isMuted) {
    setState(() {
      _speakerSequenceChanged = true;
      _selectedParticipants = [
        for (final participant in _selectedParticipants)
          participant.id == participantId
              ? participant.copyWith(isMuted: isMuted)
              : participant,
      ];
    });
  }

  void _reorderParticipants(int oldIndex, int newIndex) {
    setState(() {
      _speakerSequenceChanged = true;
      _selectedParticipants = reorderTheaterAiParticipants(
        _selectedParticipants,
        userParticipantId: _userParticipantId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
    });
  }

  bool _isDuplicateNovelExport(AppCharacter character, NovelBook book) {
    if (character.sourceType != 'novelExport') return false;
    if (character.sourceNovelId != book.id) return false;
    return book.roles.any((role) => role.name == character.sourceNovelRoleName);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      context.showSnack('请输入群聊名称');
      return;
    }
    if (_aiParticipants.isEmpty) {
      context.showSnack('至少添加一个 AI 角色');
      return;
    }
    if (_selectedParticipants.length < 2) {
      context.showSnack('至少选择 2 个参与角色');
      return;
    }
    if (_apiMode == TheaterApiMode.singleApi &&
        !_endpointReady(_singleEndpointId)) {
      context.showSnack('请先选择完整的 API 配置');
      return;
    }
    if (_apiMode == TheaterApiMode.multiApi) {
      for (final participant in _selectedParticipants) {
        if (participant.id == _userParticipantId || participant.isMuted) {
          continue;
        }
        if (!_endpointReady(participant.endpointId)) {
          context.showSnack('请为每个 AI 角色选择 API 配置');
          return;
        }
      }
    }
    final customRoundCount = int.tryParse(_customRoundsController.text.trim());
    final roundCount = _useCustomRounds ? customRoundCount : _keepRoundCount;
    if (roundCount == null || roundCount < 5 || roundCount > 100) {
      context.showSnack('自定义轮数必须在 5-100 之间');
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();
    final old = widget.session;
    final book = _boundNovel;
    final session = TheaterSession(
      id: old?.id ?? 'theater_${now.microsecondsSinceEpoch}',
      title: title,
      avatar: _avatar,
      backgroundImage: _backgroundImage,
      backgroundImageRegion: _backgroundImage.isEmpty
          ? ImageCropRegion.full
          : _backgroundImageRegion,
      backgroundImageOpacity: _backgroundImageOpacity,
      backgroundBlur: _backgroundBlur,
      bubbleTheme: _bubbleTheme,
      roleBubblePresetId: _roleBubblePresetId,
      userBubblePresetId: _userBubblePresetId,
      inputOpacity: _inputOpacity,
      topBarOpacity: _topBarOpacity,
      boundNovelId: book?.id ?? '',
      boundNovelTitle: book?.title ?? '',
      apiMode: _apiMode,
      multiApiReplyMode: _replyMode,
      singleEndpointId: _singleEndpointId,
      userParticipantId: _userParticipantId,
      keepRoundCount: roundCount,
      mainReplyCount: _mainReplyCount,
      extraReplyMode: _extraReplyMode,
      theaterSummary: old?.theaterSummary ?? '',
      summarizedMessageCount: old?.summarizedMessageCount ?? 0,
      nextSpeakerIndex: _speakerSequenceChanged
          ? 0
          : _safeNextSpeakerIndex(old?.nextSpeakerIndex ?? 0),
      participants: _selectedParticipants,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.storage.saveTheaterSession(session);
    if (!mounted) return;
    Navigator.of(context).pop(session);
  }

  bool _endpointReady(String id) {
    final endpoint = _apiConfig.endpointById(id);
    return endpoint != null && endpoint.enabled && endpoint.isComplete;
  }

  int _safeNextSpeakerIndex(int value) {
    final count = _selectedParticipants
        .where(
          (participant) =>
              participant.enabled &&
              participant.id != _userParticipantId &&
              !participant.isMuted,
        )
        .length;
    return count == 0 ? 0 : value % count;
  }

  Future<void> _pickImage({
    required bool avatar,
    required double aspectRatio,
    required int outputWidth,
    required int outputHeight,
  }) async {
    final picked = await pickImage(widget.storage, withData: false);
    if (picked == null || !mounted) return;
    final path = picked.path;
    if (!avatar) {
      final selection = await Navigator.of(context).push<ImageCropRegion>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(
            imagePath: path,
            title: context.t('裁剪群聊背景'),
            aspectRatio: aspectRatio,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            renderOutput: false,
          ),
        ),
      );
      if (selection == null) return;
      final saved = await widget.storage.saveMediaImage(
        folder: 'theater_backgrounds',
        characterId: 'theater_${DateTime.now().microsecondsSinceEpoch}',
        bytes: picked.bytes ?? await File(path).readAsBytes(),
      );
      if (!mounted) return;
      setState(() {
        _backgroundImage = saved;
        _backgroundImageRegion = selection;
      });
      return;
    }

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(
          imagePath: path,
          title: context.t('裁剪群聊头像'),
          aspectRatio: aspectRatio,
          outputWidth: outputWidth,
          outputHeight: outputHeight,
        ),
      ),
    );
    if (cropped == null) return;
    final saved = await widget.storage.saveMediaImage(
      folder: 'theater_avatars',
      characterId: 'theater_${DateTime.now().microsecondsSinceEpoch}',
      bytes: cropped,
    );
    if (!mounted) return;
    setState(() {
      _avatar = saved;
    });
  }

  Future<void> _pickAvatar() {
    return _pickImage(
      avatar: true,
      aspectRatio: 1,
      outputWidth: 512,
      outputHeight: 512,
    );
  }

  Future<void> _pickBackground() {
    return _pickImage(
      avatar: false,
      aspectRatio: 9 / 16,
      outputWidth: 1080,
      outputHeight: 1920,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final book = _boundNovel;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(_isEditing ? '编辑群聊' : '新建群聊')),
        actions: [
          IconButton(
            tooltip: context.t('保存'),
            onPressed: _isSaving ? null : _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: AdaptivePage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 120),
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: context.t('群聊名称')),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('boundNovel:$_boundNovelId'),
              initialValue: _boundNovelId,
              decoration: InputDecoration(labelText: context.t('绑定小说')),
              items: [
                DropdownMenuItem(value: '', child: Text(context.t('不绑定小说'))),
                for (final novel in _novels)
                  DropdownMenuItem(value: novel.id, child: Text(novel.title)),
              ],
              onChanged: _isEditing
                  ? null
                  : (value) {
                      setState(() {
                        _speakerSequenceChanged = true;
                        _boundNovelId = value ?? '';
                        _selectedParticipants.clear();
                        _userParticipantId = '';
                      });
                    },
            ),
            const SizedBox(height: 16),
            _sectionTitle('添加参与角色'),
            if (book == null && _characters.isNotEmpty)
              ExpansionTile(
                title: Text(context.t('从角色库添加')),
                initiallyExpanded: false,
                children: [
                  for (final character in _characters)
                    if (book == null ||
                        !_isDuplicateNovelExport(character, book))
                      CheckboxListTile(
                        value: _selectedParticipants.any(
                          (item) => item.sourceCharacterId == character.id,
                        ),
                        onChanged: (value) =>
                            _toggleAppCharacter(character, value ?? false),
                        title: Text(
                          character.isHidden ? '******' : character.name,
                        ),
                        subtitle: Text(
                          character.description.isEmpty
                              ? context.t('未填写简介')
                              : character.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
              ),
            if (book != null)
              ExpansionTile(
                title: Text(context.t('从绑定小说添加')),
                initiallyExpanded: false,
                children: [
                  if (book.roles.isEmpty)
                    ListTile(title: Text(context.t('还没有角色，请先总结小说。'))),
                  for (final role in book.roles)
                    CheckboxListTile(
                      value: _selectedParticipants.any(
                        (item) =>
                            item.sourceNovelId == book.id &&
                            item.sourceRoleId == role.name,
                      ),
                      onChanged: (value) =>
                          _toggleNovelRole(book, role, value ?? false),
                      title: Text(role.name),
                      subtitle: Text(
                        role.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('userParticipant:$_userParticipantId'),
                    initialValue:
                        _selectedParticipants.any(
                          (item) => item.id == _userParticipantId,
                        )
                        ? _userParticipantId
                        : '',
                    decoration: InputDecoration(labelText: context.t('我的身份')),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(context.t('我自己')),
                      ),
                      for (final participant in _selectedParticipants)
                        DropdownMenuItem(
                          value: participant.id,
                          child: Text(participant.name),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _speakerSequenceChanged = true;
                      _userParticipantId = value ?? '';
                    }),
                  ),
                ),
                IconButton(
                  key: const ValueKey('edit-theater-user-profile'),
                  tooltip: context.t('编辑我的身份'),
                  onPressed: _editUserParticipant,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle('API 模式'),
            SegmentedButton<TheaterApiMode>(
              segments: [
                ButtonSegment(
                  value: TheaterApiMode.singleApi,
                  label: Text(context.t('单 API')),
                ),
                ButtonSegment(
                  value: TheaterApiMode.multiApi,
                  label: Text(context.t('多 API')),
                ),
              ],
              selected: {_apiMode},
              onSelectionChanged: (values) =>
                  setState(() => _apiMode = values.first),
            ),
            const SizedBox(height: 12),
            if (_apiMode == TheaterApiMode.singleApi)
              _endpointPicker(
                label: 'API 配置',
                value: _singleEndpointId,
                onChanged: (value) =>
                    setState(() => _singleEndpointId = value ?? ''),
              )
            else ...[
              SegmentedButton<TheaterMultiApiReplyMode>(
                segments: [
                  ButtonSegment(
                    value: TheaterMultiApiReplyMode.randomSequential,
                    label: Text(context.t('随机顺序')),
                  ),
                  ButtonSegment(
                    value: TheaterMultiApiReplyMode.parallel,
                    label: Text(context.t('并行回复')),
                  ),
                  ButtonSegment(
                    value: TheaterMultiApiReplyMode.turnBased,
                    label: Text(context.t('轮流发言')),
                  ),
                ],
                selected: {_replyMode},
                onSelectionChanged: (values) =>
                    setState(() => _replyMode = values.first),
              ),
              const SizedBox(height: 8),
              Text(
                context.t(
                  _replyMode == TheaterMultiApiReplyMode.turnBased
                      ? '角色按照顺序逐个回复，后一个角色可以看到前一个角色刚生成的内容。'
                      : _replyMode == TheaterMultiApiReplyMode.parallel
                      ? '多个角色同时生成，速度快，但无法读取本轮其他角色刚生成的内容。'
                      : '角色按随机顺序逐个回复。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_apiMode == TheaterApiMode.singleApi ||
                _replyMode != TheaterMultiApiReplyMode.turnBased) ...[
              const SizedBox(height: 16),
              TheaterReplySettings(
                participantCount: _replyParticipantCount,
                mainReplyCount: _mainReplyCount,
                extraReplyMode: _extraReplyMode,
                onMainReplyCountChanged: (value) =>
                    setState(() => _mainReplyCount = value),
                onExtraReplyModeChanged: (value) =>
                    setState(() => _extraReplyMode = value),
              ),
            ],
            const SizedBox(height: 12),
            _sectionTitle('参与角色'),
            _participantSettings(),
            const SizedBox(height: 16),
            _sectionTitle('上下文保留轮数'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(_roundLabel('短', 15)),
                  selected: !_useCustomRounds && _keepRoundCount == 15,
                  onSelected: (_) => setState(() {
                    _useCustomRounds = false;
                    _keepRoundCount = 15;
                  }),
                ),
                ChoiceChip(
                  label: Text(_roundLabel('标准', 30)),
                  selected: !_useCustomRounds && _keepRoundCount == 30,
                  onSelected: (_) => setState(() {
                    _useCustomRounds = false;
                    _keepRoundCount = 30;
                  }),
                ),
                ChoiceChip(
                  label: Text(_roundLabel('长', 50)),
                  selected: !_useCustomRounds && _keepRoundCount == 50,
                  onSelected: (_) => setState(() {
                    _useCustomRounds = false;
                    _keepRoundCount = 50;
                  }),
                ),
                ChoiceChip(
                  label: Text(context.t('自定义')),
                  selected: _useCustomRounds,
                  onSelected: (_) => setState(() {
                    _useCustomRounds = true;
                    final parsed = int.tryParse(_customRoundsController.text);
                    _keepRoundCount = (parsed ?? _keepRoundCount).clamp(5, 100);
                    _customRoundsController.text = _keepRoundCount.toString();
                  }),
                ),
              ],
            ),
            if (_useCustomRounds) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customRoundsController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.t('自定义轮数')),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null) {
                    setState(() => _keepRoundCount = parsed.clamp(5, 100));
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            _appearanceSection(),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(context.t(_isEditing ? '保存' : '创建群聊')),
            ),
          ],
        ),
      ),
    );
  }

  String _roundLabel(String label, int count) {
    return context.isEnglish
        ? '${context.t(label)} $count'
        : '${context.t(label)} $count轮';
  }

  Widget _appearanceSection() {
    return ExpansionTile(
      title: Text(context.t('群聊外观')),
      initiallyExpanded: false,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _TheaterSessionAvatar(
            avatar: _avatar,
            title: _titleController.text,
          ),
          title: Text(context.t('群聊头像')),
          subtitle: Text(_avatar.isEmpty ? context.t('未设置') : context.t('已设置')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickAvatar,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.image_outlined),
          title: Text(context.t('群聊背景')),
          subtitle: Text(
            _backgroundImage.isEmpty ? context.t('未设置') : context.t('已设置'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickBackground,
        ),
        SettingSlider.transparency(
          label: '背景图透明度',
          opacity: _backgroundImageOpacity,
          onChanged: (opacity) {
            setState(() => _backgroundImageOpacity = opacity);
          },
        ),
        SettingSlider(
          label: '背景图模糊度',
          value: _backgroundBlur,
          min: 0,
          max: 12,
          divisions: 12,
          display: _backgroundBlur.toStringAsFixed(0),
          onChanged: (value) {
            setState(() => _backgroundBlur = value);
          },
        ),
        SettingSlider.transparency(
          key: const ValueKey('theater-edit-top-bar-transparency-setting'),
          label: '顶部状态栏透明度',
          opacity: _topBarOpacity,
          onChanged: (opacity) {
            setState(() => _topBarOpacity = opacity);
          },
        ),
        SettingSlider.transparency(
          key: const ValueKey('theater-edit-input-opacity-setting'),
          label: '输入框透明度',
          opacity: _inputOpacity,
          onChanged: (opacity) {
            setState(() => _inputOpacity = opacity);
          },
        ),
        Text(context.t('聊天外观'), style: Theme.of(context).textTheme.titleMedium),
        ChatBubblePresetSelectionTile(
          title: 'AI 共用气泡',
          presetId: _roleBubblePresetId,
          presets: _bubblePresets,
          isUser: false,
          onChanged: (value) => setState(() => _roleBubblePresetId = value),
        ),
        ChatBubblePresetSelectionTile(
          title: '我的气泡',
          presetId: _userBubblePresetId,
          presets: _bubblePresets,
          isUser: true,
          onChanged: (value) => setState(() => _userBubblePresetId = value),
        ),
        if (_backgroundImage.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _backgroundImage = '';
                _backgroundImageRegion = ImageCropRegion.full;
              }),
              icon: const Icon(Icons.clear),
              label: Text(context.t('清除聊天背景')),
            ),
          ),
      ],
    );
  }

  Widget _participantSettings() {
    final participants = _aiParticipants;
    final canReorder =
        _apiMode == TheaterApiMode.multiApi &&
        _replyMode == TheaterMultiApiReplyMode.turnBased;
    if (!canReorder) {
      return Column(
        children: [
          for (var i = 0; i < participants.length; i++)
            _participantSettingRow(participants[i], i, draggable: false),
        ],
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: participants.length,
      onReorderItem: _reorderParticipants,
      itemBuilder: (context, index) =>
          _participantSettingRow(participants[index], index, draggable: true),
    );
  }

  Widget _participantSettingRow(
    TheaterParticipant participant,
    int index, {
    required bool draggable,
  }) {
    return Row(
      key: ValueKey('participant-setting:${participant.id}'),
      children: [
        Expanded(
          child: _apiMode == TheaterApiMode.multiApi
              ? _endpointPicker(
                  label: participant.name,
                  value: participant.endpointId,
                  onChanged: (value) =>
                      _setParticipantEndpoint(participant.id, value ?? ''),
                )
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(participant.name),
                ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t('允许发言'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Switch(
              value: !participant.isMuted,
              onChanged: (value) =>
                  _setParticipantMuted(participant.id, !value),
            ),
          ],
        ),
        if (draggable)
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: context.t('拖动调整发言顺序'),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ),
      ],
    );
  }

  Widget _endpointPicker({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    final endpoints = _apiConfig.enabledEndpoints;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey('endpoint:$label:$value'),
        initialValue: endpoints.any((endpoint) => endpoint.id == value)
            ? value
            : null,
        decoration: InputDecoration(labelText: context.t(label)),
        items: [
          for (final endpoint in endpoints)
            DropdownMenuItem(value: endpoint.id, child: Text(endpoint.name)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        context.t(text),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
