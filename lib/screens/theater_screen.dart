import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/api_config.dart';
import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../models/novel_book.dart';
import '../models/theater.dart';
import '../prompts.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';
import '../utils/page_layout.dart';
import '../utils/password_lock.dart';
import '../widgets/message_content.dart';
import 'image_crop_screen.dart';

class TheaterListScreen extends StatefulWidget {
  const TheaterListScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final AppSettings settings;

  @override
  State<TheaterListScreen> createState() => TheaterListScreenState();
}

class TheaterListScreenState extends State<TheaterListScreen> {
  var _isLoading = true;
  var _sessions = <TheaterSession>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sessions = await widget.storage.loadTheaterSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> createTheater() async {
    final session = await Navigator.of(context).push<TheaterSession>(
      MaterialPageRoute(
        builder: (_) => TheaterEditScreen(
          storage: widget.storage,
          aiService: widget.aiService,
        ),
      ),
    );
    if (session == null || !mounted) return;
    await _open(session);
  }

  Future<void> _open(TheaterSession session) async {
    if (!await _verifySessionOperation(session, '进入聊天')) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TheaterChatScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          settings: widget.settings,
          session: session,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _rename(TheaterSession session) async {
    if (!await _verifySessionOperation(session, '重命名')) return;
    if (!mounted) return;
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('重命名群聊')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.t('群聊名称')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(context.t('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await widget.storage.saveTheaterSession(
      session.copyWith(title: title, updatedAt: DateTime.now()),
    );
    await _load();
  }

  Future<void> _delete(TheaterSession session) async {
    if (!await _verifySessionOperation(session, '删除群聊')) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('删除群聊')),
        content: Text(
          context.isEnglish
              ? 'Delete "${session.title}"? Messages will also be deleted.'
              : '确定删除“${session.title}”吗？消息也会一起删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('删除')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.deleteTheaterSession(session.id);
    if (mounted) await _load();
  }

  Future<void> _toggleHidden(TheaterSession session) async {
    if (!await _verifySessionOperation(
      session,
      session.isHidden ? '显示设定' : '隐藏设定',
    )) {
      return;
    }
    await widget.storage.saveTheaterSession(
      session.copyWith(isHidden: !session.isHidden, updatedAt: DateTime.now()),
    );
    if (!mounted) return;
    _showSnack(session.isHidden ? '已显示设定' : '已隐藏设定');
    await _load();
  }

  Future<void> _toggleLock(TheaterSession session) async {
    if (!session.isLocked && !widget.settings.hasPrivacyPassword) {
      _showSnack('请先到设置里设置隐私密码');
      return;
    }
    if (session.isLocked && !await _verifySessionOperation(session, '解除上锁')) {
      return;
    }
    await widget.storage.saveTheaterSession(
      session.copyWith(isLocked: !session.isLocked, updatedAt: DateTime.now()),
    );
    if (!mounted) return;
    _showSnack(session.isLocked ? '已解除上锁' : '已上锁');
    await _load();
  }

  Future<bool> _verifySessionOperation(
    TheaterSession session,
    String title,
  ) async {
    if (!session.isLocked) return true;
    return _verifyPassword(title);
  }

  Future<bool> _verifyPassword(String title) async {
    if (!widget.settings.hasPrivacyPassword) {
      _showSnack('请先到设置里设置隐私密码');
      return false;
    }
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t(title)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(labelText: context.t('隐私密码')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () async {
              final password = controller.text;
              final ok = PasswordLock.verify(
                password,
                widget.settings.privacyPasswordSalt,
                widget.settings.privacyPasswordHash,
              );
              if (!ok) {
                _showSnack('密码不正确');
                return;
              }
              await widget.storage.upgradePrivacyPasswordHashIfNeeded(
                widget.settings,
                password,
              );
              if (!context.mounted) return;
              Navigator.of(context).pop(true);
            },
            child: Text(context.t('确认')),
          ),
        ],
      ),
    );
    controller.dispose();
    return ok == true;
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(text))));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(context.t('重新加载')),
              ),
            ],
          ),
        ),
      );
    }

    final content = _sessions.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forum_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(context.t('还没有群聊')),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: EdgeInsets.fromLTRB(
              0,
              homeListTop(context) - kToolbarHeight,
              0,
              120,
            ),
            itemCount: _sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final session = _sessions[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  leading: _TheaterSessionAvatar(
                    avatar: session.avatar,
                    title: session.title,
                  ),
                  title: Text(
                    session.isHidden ? '******' : session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      '${context.t('绑定小说')}：${session.isHidden ? '******' : _maskedNovelTitle(context, session.boundNovelTitle)}',
                      '${context.t('参与角色')}：${session.participants.length}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _open(session),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rename') _rename(session);
                      if (value == 'hide') _toggleHidden(session);
                      if (value == 'lock') _toggleLock(session);
                      if (value == 'delete') _delete(session);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(context.t('重命名')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: ListTile(
                          leading: Icon(
                            session.isHidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          title: Text(
                            context.t(session.isHidden ? '显示设定' : '隐藏设定'),
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'lock',
                        child: ListTile(
                          leading: Icon(
                            session.isLocked
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                          ),
                          title: Text(
                            context.t(session.isLocked ? '解除上锁' : '上锁'),
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(context.t('删除群聊')),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );

    return AdaptivePage(child: content);
  }

  String _maskedNovelTitle(BuildContext context, String title) {
    final text = title.trim();
    if (text.isEmpty) return context.t('无');
    final chars = text.characters.toList();
    if (chars.length <= 2) return text;
    return '${chars.take(2).join()}${List.filled(chars.length - 2, '*').join()}';
  }
}

class TheaterEditScreen extends StatefulWidget {
  const TheaterEditScreen({
    required this.storage,
    required this.aiService,
    this.session,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final TheaterSession? session;

  @override
  State<TheaterEditScreen> createState() => _TheaterEditScreenState();
}

class _TheaterEditScreenState extends State<TheaterEditScreen> {
  final _titleController = TextEditingController();
  final _customRoundsController = TextEditingController(text: '10');
  var _characters = <AppCharacter>[];
  var _novels = <NovelBook>[];
  var _apiConfig = ApiConfig.defaults();
  var _selectedParticipants = <TheaterParticipant>[];
  var _boundNovelId = '';
  var _avatar = '';
  var _backgroundImage = '';
  var _backgroundImageOpacity = 1.0;
  var _backgroundBlur = 0.0;
  var _bubbleOpacity = 0.94;
  var _inputOpacity = 0.92;
  var _topBarOpacity = 0.0;
  var _apiMode = TheaterApiMode.singleApi;
  var _replyMode = TheaterMultiApiReplyMode.randomSequential;
  var _singleEndpointId = '';
  var _userParticipantId = '';
  var _keepRoundCount = 30;
  var _useCustomRounds = false;
  var _isLoading = true;
  var _isSaving = false;

  bool get _isEditing => widget.session != null;

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
      _backgroundImageOpacity = session.backgroundImageOpacity;
      _backgroundBlur = session.backgroundBlur;
      _bubbleOpacity = session.bubbleOpacity;
      _inputOpacity = session.inputOpacity;
      _topBarOpacity = session.topBarOpacity;
      _boundNovelId = session.boundNovelId;
      _apiMode = session.apiMode;
      _replyMode = session.multiApiReplyMode;
      _singleEndpointId = session.singleEndpointId;
      _userParticipantId = session.userParticipantId;
      _keepRoundCount = session.keepRoundCount;
      _customRoundsController.text = session.keepRoundCount.toString();
      _useCustomRounds = ![15, 30, 50].contains(session.keepRoundCount);
      _selectedParticipants = [...session.participants];
    }
    _load();
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
    ]);
    if (!mounted) return;
    setState(() {
      _characters = values[0] as List<AppCharacter>;
      _novels = values[1] as List<NovelBook>;
      _apiConfig = values[2] as ApiConfig;
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

  bool _isDuplicateNovelExport(AppCharacter character, NovelBook book) {
    if (character.sourceType != 'novelExport') return false;
    if (character.sourceNovelId != book.id) return false;
    return book.roles.any((role) => role.name == character.sourceNovelRoleName);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnack('请输入群聊名称');
      return;
    }
    if (_selectedParticipants.length < 2) {
      _showSnack('至少选择 2 个参与角色');
      return;
    }
    if (_apiMode == TheaterApiMode.singleApi &&
        !_endpointReady(_singleEndpointId)) {
      _showSnack('请先选择完整的 API 配置');
      return;
    }
    if (_apiMode == TheaterApiMode.multiApi) {
      for (final participant in _selectedParticipants) {
        if (participant.id == _userParticipantId) continue;
        if (!_endpointReady(participant.endpointId)) {
          _showSnack('请为每个 AI 角色选择 API 配置');
          return;
        }
      }
    }
    final customRoundCount = int.tryParse(_customRoundsController.text.trim());
    final roundCount = _useCustomRounds ? customRoundCount : _keepRoundCount;
    if (roundCount == null || roundCount < 5 || roundCount > 100) {
      _showSnack('自定义轮数必须在 5-100 之间');
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
      backgroundImageOpacity: _backgroundImageOpacity,
      backgroundBlur: _backgroundBlur,
      bubbleOpacity: _bubbleOpacity,
      inputOpacity: _inputOpacity,
      topBarOpacity: _topBarOpacity,
      boundNovelId: book?.id ?? '',
      boundNovelTitle: book?.title ?? '',
      apiMode: _apiMode,
      multiApiReplyMode: _replyMode,
      singleEndpointId: _singleEndpointId,
      userParticipantId: _userParticipantId,
      keepRoundCount: roundCount,
      theaterSummary: old?.theaterSummary ?? '',
      summarizedMessageCount: old?.summarizedMessageCount ?? 0,
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

  Future<void> _pickImage({
    required bool avatar,
    required double aspectRatio,
    required int outputWidth,
    required int outputHeight,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(
          imagePath: path,
          title: context.t(avatar ? '裁剪群聊头像' : '裁剪群聊背景'),
          aspectRatio: aspectRatio,
          outputWidth: outputWidth,
          outputHeight: outputHeight,
        ),
      ),
    );
    if (cropped == null) return;
    final saved = await widget.storage.saveMediaImage(
      folder: avatar ? 'theater_avatars' : 'theater_backgrounds',
      characterId: 'theater_${DateTime.now().microsecondsSinceEpoch}',
      bytes: cropped,
    );
    if (!mounted) return;
    setState(() {
      if (avatar) {
        _avatar = saved;
      } else {
        _backgroundImage = saved;
      }
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

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(text))));
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
            DropdownButtonFormField<String>(
              key: ValueKey('userParticipant:$_userParticipantId'),
              initialValue:
                  _selectedParticipants.any(
                    (item) => item.id == _userParticipantId,
                  )
                  ? _userParticipantId
                  : '',
              decoration: InputDecoration(labelText: context.t('我的身份')),
              items: [
                DropdownMenuItem(value: '', child: Text(context.t('我自己'))),
                for (final participant in _selectedParticipants)
                  DropdownMenuItem(
                    value: participant.id,
                    child: Text(participant.name),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _userParticipantId = value ?? ''),
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
                ],
                selected: {_replyMode},
                onSelectionChanged: (values) =>
                    setState(() => _replyMode = values.first),
              ),
              const SizedBox(height: 12),
              for (final participant in _selectedParticipants)
                if (participant.id != _userParticipantId)
                  _endpointPicker(
                    label: participant.name,
                    value: participant.endpointId,
                    onChanged: (value) =>
                        _setParticipantEndpoint(participant.id, value ?? ''),
                  ),
            ],
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
        _compactSlider(
          label: '背景图透明度',
          value: _backgroundImageOpacity,
          min: 0,
          max: 1,
          divisions: 100,
          display: '${(_backgroundImageOpacity * 100).round()}%',
          onChanged: (value) {
            setState(() => _backgroundImageOpacity = value);
          },
        ),
        _compactSlider(
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
        _compactSlider(
          label: '文本框透明度',
          value: _bubbleOpacity,
          min: 0,
          max: 1,
          divisions: 100,
          display: '${(_bubbleOpacity * 100).round()}%',
          onChanged: (value) {
            setState(() => _bubbleOpacity = value);
          },
        ),
        _compactSlider(
          label: '输入框透明度',
          value: _inputOpacity,
          min: 0,
          max: 1,
          divisions: 100,
          display: '${(_inputOpacity * 100).round()}%',
          onChanged: (value) {
            setState(() => _inputOpacity = value);
          },
        ),
        if (_backgroundImage.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _backgroundImage = ''),
              icon: const Icon(Icons.clear),
              label: Text(context.t('清除聊天背景')),
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

  Widget _compactSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          labelText: context.t(label),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ),
            SizedBox(width: 48, child: Text(display, textAlign: TextAlign.end)),
          ],
        ),
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

class TheaterChatScreen extends StatefulWidget {
  const TheaterChatScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    required this.session,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final AppSettings settings;
  final TheaterSession session;

  @override
  State<TheaterChatScreen> createState() => _TheaterChatScreenState();
}

class _TheaterChatScreenState extends State<TheaterChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late TheaterSession _session;
  var _messages = <TheaterMessage>[];
  var _apiConfig = ApiConfig.defaults();
  var _novelSummary = '';
  var _isLoading = true;
  var _isGenerating = false;
  var _isSummarizing = false;
  var _generationId = 0;
  AiCancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apiConfig = await widget.storage.loadApiConfig();
    final messages = await widget.storage.loadTheaterMessages(_session.id);
    var novelSummary = '';
    if (_session.boundNovelId.isNotEmpty) {
      final novels = await widget.storage.loadNovels();
      for (final novel in novels) {
        if (novel.id == _session.boundNovelId) {
          novelSummary = novel.summary;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _apiConfig = apiConfig;
      _messages = messages;
      _novelSummary = novelSummary;
      _isLoading = false;
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;
    final now = DateTime.now();
    final userRole = _session.userParticipant;
    final round = _messages.isEmpty ? 1 : _messages.last.round + 1;
    final message = TheaterMessage(
      id: 'theater_msg_${now.microsecondsSinceEpoch}',
      sessionId: _session.id,
      round: round,
      speakerType: TheaterSpeakerType.user,
      speakerId: userRole?.id ?? '',
      speakerName: userRole?.name ?? context.t('我'),
      content: text,
      time: now,
    );
    setState(() {
      _messages = [..._messages, message];
      _isGenerating = true;
    });
    _inputController.clear();
    await _saveMessages();
    await _saveSession(_session.copyWith(updatedAt: now));
    await _generateReplies(round);
  }

  Future<void> _generateReplies(int round) async {
    final generationId = ++_generationId;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    try {
      await _updateRollingSummary(generationId, cancelToken);
      if (!mounted || generationId != _generationId) return;
      switch (_session.apiMode) {
        case TheaterApiMode.singleApi:
          await _generateSingleApi(round, generationId, cancelToken);
        case TheaterApiMode.multiApi:
          if (_session.multiApiReplyMode == TheaterMultiApiReplyMode.parallel) {
            await _generateParallel(round, generationId, cancelToken);
          } else {
            await _generateSequential(round, generationId, cancelToken);
          }
      }
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      if (mounted && generationId == _generationId) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _generateSingleApi(
    int round,
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    final endpoint = _apiConfig.effectiveEndpoint(_session.singleEndpointId);
    final error = _validateEndpoint(endpoint);
    if (error != null) {
      await _appendSystemError(error, round);
      return;
    }
    if (_session.aiParticipants.isEmpty) {
      await _appendSystemError('没有可自动回复的角色', round);
      return;
    }
    var raw = '';
    await for (final chunk in widget.aiService.streamMessage(
      apiKey: endpoint!.apiKey,
      baseUrl: endpoint.baseUrl,
      model: endpoint.model,
      messages: PromptBuilder.buildTheaterSingleApiRequest(
        session: _session,
        novelSummary: _novelSummary,
        messages: _recentMessages(),
      ),
      cancelToken: cancelToken,
    )) {
      if (!mounted || generationId != _generationId) return;
      raw += chunk;
    }
    final drafts = PromptBuilder.parseTheaterReplies(raw);
    if (drafts.isEmpty) {
      await _appendSystemError('生成失败，可重试', round);
      return;
    }
    final next = <TheaterMessage>[];
    for (final draft in drafts) {
      final participant = _matchParticipant(draft.speaker);
      if (participant == null) continue;
      next.add(
        _roleMessage(participant, draft.content, round, endpoint: endpoint),
      );
    }
    if (next.isEmpty) {
      await _appendSystemError('生成失败，可重试', round);
      return;
    }
    if (!mounted || generationId != _generationId) return;
    setState(() => _messages = [..._messages, ...next]);
    await _saveMessages();
  }

  Future<void> _generateSequential(
    int round,
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    final participants = [..._session.aiParticipants]..shuffle(Random());
    for (final participant in participants) {
      if (!mounted || generationId != _generationId) return;
      await _generateForParticipant(
        participant,
        round,
        generationId,
        cancelToken,
      );
    }
  }

  Future<void> _generateParallel(
    int round,
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    await Future.wait([
      for (final participant in _session.aiParticipants)
        _generateForParticipant(participant, round, generationId, cancelToken),
    ]);
  }

  Future<void> _generateForParticipant(
    TheaterParticipant participant,
    int round,
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    final endpoint = _apiConfig.effectiveEndpoint(participant.endpointId);
    final error = _validateEndpoint(endpoint);
    if (error != null) {
      await _appendRoleError(participant, error, round);
      return;
    }
    final placeholder = _roleMessage(
      participant,
      '',
      round,
      endpoint: endpoint!,
    );
    final streamResponses = widget.settings.streamResponses;
    try {
      if (!mounted || generationId != _generationId) return;
      if (streamResponses) {
        setState(() => _messages = [..._messages, placeholder]);
      }

      var reply = '';
      await for (final chunk in widget.aiService.streamMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: PromptBuilder.buildTheaterParticipantRequest(
          session: _session,
          participant: participant,
          novelSummary: _novelSummary,
          messages: _recentMessages(),
        ),
        cancelToken: cancelToken,
        includeReasoning: widget.settings.showReasoningContent,
      )) {
        if (!mounted || generationId != _generationId) return;
        reply += chunk;
        if (streamResponses) {
          setState(() {
            _replaceMessage(
              placeholder.id,
              placeholder.copyWith(content: reply),
            );
          });
        }
      }
      if (reply.trim().isEmpty) {
        throw AiException('API 没有返回可用回复。');
      }
      if (!mounted || generationId != _generationId) return;
      if (!streamResponses) {
        setState(() {
          _messages = [..._messages, placeholder.copyWith(content: reply)];
        });
      }
      await _saveMessages();
    } catch (error) {
      if (!mounted || generationId != _generationId) return;
      setState(() => _removeMessage(placeholder.id));
      await _appendRoleError(participant, error.toString(), round);
    }
  }

  TheaterMessage _roleMessage(
    TheaterParticipant participant,
    String content,
    int round, {
    required AiEndpointConfig endpoint,
  }) {
    final now = DateTime.now();
    return TheaterMessage(
      id: 'theater_msg_${now.microsecondsSinceEpoch}_${participant.id}',
      sessionId: _session.id,
      round: round,
      speakerType: TheaterSpeakerType.role,
      speakerId: participant.id,
      speakerName: participant.name,
      content: content.trim(),
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      model: endpoint.model,
      time: now,
    );
  }

  void _replaceMessage(String id, TheaterMessage message) {
    final index = _messages.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final next = [..._messages];
    next[index] = message;
    _messages = next;
  }

  void _removeMessage(String id) {
    _messages = _messages.where((item) => item.id != id).toList();
  }

  TheaterParticipant? _matchParticipant(String name) {
    final normalized = name.trim();
    for (final participant in _session.aiParticipants) {
      if (participant.name.trim() == normalized) return participant;
    }
    return null;
  }

  Future<void> _appendSystemError(String error, int round) async {
    final now = DateTime.now();
    setState(() {
      _messages = [
        ..._messages,
        TheaterMessage(
          id: 'theater_msg_${now.microsecondsSinceEpoch}_error',
          sessionId: _session.id,
          round: round,
          speakerType: TheaterSpeakerType.system,
          speakerId: '',
          speakerName: context.t('系统'),
          content: error,
          isError: true,
          errorMessage: error,
          time: now,
        ),
      ];
    });
    await _saveMessages();
  }

  Future<void> _appendRoleError(
    TheaterParticipant participant,
    String error,
    int round,
  ) async {
    final now = DateTime.now();
    setState(() {
      _messages = [
        ..._messages,
        TheaterMessage(
          id: 'theater_msg_${now.microsecondsSinceEpoch}_error_${participant.id}',
          sessionId: _session.id,
          round: round,
          speakerType: TheaterSpeakerType.role,
          speakerId: participant.id,
          speakerName: participant.name,
          content: context.t('生成失败，点击重试'),
          isError: true,
          errorMessage: error,
          time: now,
        ),
      ];
    });
    await _saveMessages();
  }

  Future<void> _retry(TheaterMessage message) async {
    if (_isGenerating) return;
    final participant = _session.participants.firstWhere(
      (item) => item.id == message.speakerId,
      orElse: () => const TheaterParticipant(
        id: '',
        source: TheaterRoleSource.appCharacter,
        name: '',
        avatar: '',
        description: '',
        personality: '',
        background: '',
        speakingStyle: '',
      ),
    );
    if (participant.id.isEmpty) return;
    final generationId = ++_generationId;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _isGenerating = true;
      _messages = _messages.where((item) => item.id != message.id).toList();
    });
    await _saveMessages();
    try {
      await _generateForParticipant(
        participant,
        message.round,
        generationId,
        cancelToken,
      );
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      if (mounted && generationId == _generationId) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _updateRollingSummary(
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    final recentLimit = _session.recentMessageLimit;
    final buffer = _session.participantUnitCount;
    if (_messages.length <= recentLimit + buffer) return;
    final summarizeUntil = _messages.length - recentLimit;
    final summarizedCount = _session.summarizedMessageCount
        .clamp(0, summarizeUntil)
        .toInt();
    if (summarizedCount >= summarizeUntil) return;
    final aiParticipants = _session.aiParticipants;
    final endpointId = _session.apiMode == TheaterApiMode.singleApi
        ? _session.singleEndpointId
        : aiParticipants.isEmpty
        ? ''
        : aiParticipants.first.endpointId;
    final endpoint = _apiConfig.effectiveEndpoint(endpointId);
    if (_validateEndpoint(endpoint) != null) return;
    final chunk = _messages.sublist(summarizedCount, summarizeUntil);
    setState(() => _isSummarizing = true);
    try {
      final summary = await widget.aiService.sendMessage(
        apiKey: endpoint!.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: [
          {'role': 'system', 'content': '你负责总结群聊记录，并只输出总结内容。'},
          {
            'role': 'user',
            'content': PromptBuilder.buildTheaterSummaryPrompt(
              previousSummary: _session.theaterSummary,
              messages: chunk,
              useCustomItems: widget.settings.useCustomTheaterSummaryItems,
              customItems: widget.settings.customTheaterSummaryItems,
            ),
          },
        ],
        cancelToken: cancelToken,
      );
      if (!mounted || generationId != _generationId) return;
      await _saveSession(
        _session.copyWith(
          theaterSummary: summary,
          summarizedMessageCount: summarizeUntil,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      return;
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  List<TheaterMessage> _recentMessages() {
    final start = max(
      _session.summarizedMessageCount,
      _messages.length - _session.recentMessageLimit,
    );
    return _messages.skip(start).toList();
  }

  String? _validateEndpoint(AiEndpointConfig? endpoint) {
    if (endpoint == null) return '请先到 API 设置添加配置。';
    if (!endpoint.enabled) return '当前 API 配置已禁用。';
    if (endpoint.apiKey.trim().isEmpty) return 'API Key 为空，请先配置。';
    if (endpoint.baseUrl.trim().isEmpty) return 'Base URL 为空，请先配置。';
    if (endpoint.model.trim().isEmpty) return 'Model 为空，请先配置。';
    return null;
  }

  Future<void> _saveMessages() {
    return widget.storage.saveTheaterMessages(_session.id, _messages);
  }

  Future<void> _saveSession(TheaterSession session) async {
    await widget.storage.saveTheaterSession(session);
    if (!mounted) return;
    setState(() => _session = session);
  }

  void _stopGeneration() {
    if (!_isGenerating) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _generationId++;
    setState(() => _isGenerating = false);
  }

  Future<void> _clearMessages() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('清空群聊消息')),
        content: Text(context.t('确定清空当前群聊消息吗？群聊总结也会清空。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('清空')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.clearTheaterMessages(_session.id);
    await _saveSession(
      _session.copyWith(
        theaterSummary: '',
        summarizedMessageCount: 0,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) setState(() => _messages = []);
  }

  Future<void> _showSummaryDialog() async {
    final controller = TextEditingController(text: _session.theaterSummary);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('群聊总结')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(hintText: context.t('可以直接填写历史总结')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () async {
              await _saveSession(
                _session.copyWith(
                  theaterSummary: controller.text.trim(),
                  summarizedMessageCount: controller.text.trim().isEmpty
                      ? 0
                      : _messages.length,
                  updatedAt: DateTime.now(),
                ),
              );
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(context.t('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _openSettings() async {
    var draft = _session;
    var openEditor = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void preview(TheaterSession next) {
            setSheetState(() => draft = next);
            setState(() => _session = next);
          }

          void apply(TheaterSession next) {
            final saved = next.copyWith(updatedAt: DateTime.now());
            preview(saved);
            unawaited(widget.storage.saveTheaterSession(saved));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    context.t('群聊设置'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 18),
                  _TheaterSettingsInfo(
                    icon: Icons.chat_bubble_outline,
                    title: _chatCountLabel(),
                    subtitle: _theaterSpeedHint(),
                  ),
                  _TheaterSettingsInfo(
                    icon: Icons.memory_outlined,
                    title: context.t('当前模型'),
                    subtitle: _currentModelLabel(),
                  ),
                  _TheaterSettingsInfo(
                    icon: Icons.history_toggle_off,
                    title: _keepRoundCountLabel(draft.keepRoundCount),
                    subtitle: null,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(_roundSheetLabel('短', 15)),
                        selected: draft.keepRoundCount == 15,
                        onSelected: (_) =>
                            apply(draft.copyWith(keepRoundCount: 15)),
                      ),
                      ChoiceChip(
                        label: Text(_roundSheetLabel('标准', 30)),
                        selected: draft.keepRoundCount == 30,
                        onSelected: (_) =>
                            apply(draft.copyWith(keepRoundCount: 30)),
                      ),
                      ChoiceChip(
                        label: Text(_roundSheetLabel('长', 50)),
                        selected: draft.keepRoundCount == 50,
                        onSelected: (_) =>
                            apply(draft.copyWith(keepRoundCount: 50)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _TheaterSheetSlider(
                    label: context.t('背景图透明度'),
                    value: draft.backgroundImageOpacity,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    display: '${(draft.backgroundImageOpacity * 100).round()}%',
                    onChanged: (value) =>
                        preview(draft.copyWith(backgroundImageOpacity: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(backgroundImageOpacity: value)),
                  ),
                  _TheaterSheetSlider(
                    label: context.t('背景图模糊度'),
                    value: draft.backgroundBlur,
                    min: 0,
                    max: 12,
                    divisions: 12,
                    display: draft.backgroundBlur.toStringAsFixed(0),
                    onChanged: (value) =>
                        preview(draft.copyWith(backgroundBlur: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(backgroundBlur: value)),
                  ),
                  _TheaterSheetSlider(
                    label: context.t('文本框透明度'),
                    value: draft.bubbleOpacity,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    display: '${(draft.bubbleOpacity * 100).round()}%',
                    onChanged: (value) =>
                        preview(draft.copyWith(bubbleOpacity: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(bubbleOpacity: value)),
                  ),
                  _TheaterSheetSlider(
                    label: context.t('输入框透明度'),
                    value: draft.inputOpacity,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    display: '${(draft.inputOpacity * 100).round()}%',
                    onChanged: (value) =>
                        preview(draft.copyWith(inputOpacity: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(inputOpacity: value)),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      openEditor = true;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.tune),
                    label: Text(context.t('编辑群聊')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    if (openEditor) {
      await _openFullSettings();
    }
  }

  Future<void> _openFullSettings() async {
    final session = await Navigator.of(context).push<TheaterSession>(
      MaterialPageRoute(
        builder: (_) => TheaterEditScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          session: _session,
        ),
      ),
    );
    if (session == null || !mounted) return;
    setState(() => _session = session);
  }

  String _currentModelLabel() {
    if (_session.apiMode == TheaterApiMode.multiApi) {
      return context.t('多 API');
    }
    return _apiConfig.effectiveEndpoint(_session.singleEndpointId)?.name ??
        context.t('未配置 API');
  }

  String _chatCountLabel() {
    return context.isEnglish
        ? '${context.t('聊天条数')}: ${_messages.length}'
        : '${context.t('聊天条数')}：${_messages.length} 条';
  }

  String _keepRoundCountLabel(int count) {
    return context.isEnglish
        ? '${context.t('上下文保留轮数')}: $count'
        : '${context.t('上下文保留轮数')}：$count轮';
  }

  String _theaterSpeedHint() {
    if (_messages.length < 80) return context.t('速度判断：正常');
    if (_messages.length < 180) {
      return context.t('速度判断：聊天变长，模型可能会慢一点');
    }
    return context.t('速度判断：聊天很多，模型读取上下文可能明显变慢');
  }

  String _roundSheetLabel(String label, int count) {
    return context.isEnglish
        ? '${context.t(label)} $count'
        : '${context.t(label)} $count轮';
  }

  Future<void> _copy(TheaterMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    _showSnack('已复制消息');
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(text))));
  }

  SystemUiOverlayStyle _overlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final hasBackground = _session.backgroundImage.trim().isNotEmpty;
    return _TheaterBackground(
      imagePath: _session.backgroundImage,
      opacity: _session.backgroundImageOpacity,
      blur: _session.backgroundBlur,
      child: Scaffold(
        backgroundColor: hasBackground ? Colors.transparent : null,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: _overlayStyle(context),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_session.title),
              Text(
                _session.boundNovelTitle.isEmpty
                    ? '${context.t('我的身份')}：${_session.userParticipant?.name ?? context.t('我自己')}'
                    : '${_session.boundNovelTitle} · ${context.t('我的身份')}：${_session.userParticipant?.name ?? context.t('我自己')}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: context.t('群聊总结'),
              onPressed: _showSummaryDialog,
              icon: const Icon(Icons.summarize_outlined),
            ),
            IconButton(
              tooltip: context.t('清空群聊消息'),
              onPressed: _clearMessages,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
            IconButton(
              tooltip: context.t('群聊设置'),
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_isSummarizing) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildMessages()),
            _TheaterInputComposer(
              controller: _inputController,
              isGenerating: _isGenerating,
              hasBackground: hasBackground,
              inputOpacity: _session.inputOpacity,
              onSend: _send,
              onStop: _stopGeneration,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(child: Text(context.t('当前还没有群聊消息。')));
    }
    final participants = {
      for (final item in _session.participants) item.id: item,
    };
    final showTyping =
        _isGenerating &&
        (_messages.isEmpty ||
            _messages.last.speakerType != TheaterSpeakerType.role);
    return AdaptivePage(
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        itemCount: _messages.length + (showTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (showTyping && index == 0) {
            return const _TheaterTypingBubble();
          }
          final messageIndex =
              _messages.length - 1 - (index - (showTyping ? 1 : 0));
          final message = _messages[messageIndex];
          return _TheaterMessageBubble(
            message: message,
            participant: participants[message.speakerId],
            bubbleOpacity: _session.bubbleOpacity,
            chatTextColor: widget.settings.chatTextColor,
            onCopy: () => _copy(message),
            onRetry: message.isError ? () => _retry(message) : null,
          );
        },
      ),
    );
  }
}

class _TheaterBackground extends StatelessWidget {
  const _TheaterBackground({
    required this.imagePath,
    required this.opacity,
    required this.blur,
    required this.child,
  });

  final String imagePath;
  final double opacity;
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();
    final alpha = opacity.clamp(0, 1).toDouble();
    if (path.isEmpty) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: alpha,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18 * alpha),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _TheaterSettingsInfo extends StatelessWidget {
  const _TheaterSettingsInfo({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _TheaterSheetSlider extends StatelessWidget {
  const _TheaterSheetSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          labelText: label,
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 26,
                child: Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
            SizedBox(width: 52, child: Text(display, textAlign: TextAlign.end)),
          ],
        ),
      ),
    );
  }
}

class _TheaterInputComposer extends StatelessWidget {
  const _TheaterInputComposer({
    required this.controller,
    required this.isGenerating,
    required this.hasBackground,
    required this.inputOpacity,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final bool hasBackground;
  final double inputOpacity;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final alpha = inputOpacity.clamp(0, 1).toDouble();
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface.withValues(alpha: alpha);
    final borderColor = colorScheme.outline.withValues(alpha: alpha);
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: responsiveMaxContentWidth(
              MediaQuery.sizeOf(context).width,
            ),
          ),
          child: Material(
            color: surfaceColor,
            elevation: hasBackground ? 8 * alpha : 0,
            shadowColor: Colors.black.withValues(alpha: alpha),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: context.t('输入消息'),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: colorScheme.primary.withValues(alpha: alpha),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: context.t(isGenerating ? '停止生成' : '发送'),
                    onPressed: isGenerating ? onStop : onSend,
                    icon: Icon(isGenerating ? Icons.stop : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TheaterMessageBubble extends StatelessWidget {
  const _TheaterMessageBubble({
    required this.message,
    required this.participant,
    required this.bubbleOpacity,
    required this.chatTextColor,
    required this.onCopy,
    this.onRetry,
  });

  final TheaterMessage message;
  final TheaterParticipant? participant;
  final double bubbleOpacity;
  final int? chatTextColor;
  final VoidCallback onCopy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final color =
        (isUser
                ? theme.colorScheme.primaryContainer
                : message.isError
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest)
            .withValues(alpha: bubbleOpacity.clamp(0, 1).toDouble());
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final maxWidth = isCompactWidth(MediaQuery.sizeOf(context).width)
        ? MediaQuery.sizeOf(context).width * 0.86
        : 760.0;
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TheaterAvatar(
                    participant: participant,
                    name: message.speakerName,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message.speakerName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MessageContent(text: message.content, textColor: chatTextColor),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDate(message.time),
                    style: theme.textTheme.labelSmall,
                  ),
                  if (message.model.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        message.model,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: context.t('复制消息'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                  ),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(context.t('重试')),
                    ),
                ],
              ),
              if (message.isError && message.errorMessage.isNotEmpty)
                Text(message.errorMessage, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _TheaterSessionAvatar extends StatelessWidget {
  const _TheaterSessionAvatar({required this.avatar, required this.title});

  final String avatar;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (avatar.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: FileImage(File(avatar)),
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      child: Text(title.trim().isEmpty ? '?' : title.trim().characters.first),
    );
  }
}

class _TheaterAvatar extends StatelessWidget {
  const _TheaterAvatar({required this.participant, required this.name});

  final TheaterParticipant? participant;
  final String name;

  @override
  Widget build(BuildContext context) {
    final avatar = participant?.avatar ?? '';
    if (avatar.isNotEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundImage: FileImage(File(avatar)),
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      radius: 14,
      child: Text(name.trim().isEmpty ? '?' : name.trim().characters.first),
    );
  }
}

class _TheaterTypingBubble extends StatelessWidget {
  const _TheaterTypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

String _formatDate(DateTime? time) {
  if (time == null) return '-';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
