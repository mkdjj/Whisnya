import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../controllers/chat_conversation_controller.dart';
import '../../models/api_config.dart';
import '../../models/app_character.dart';
import '../../models/app_settings.dart';
import '../../models/chat_bubble_preset.dart';
import '../../models/chat_bubble_theme.dart';
import '../../models/chat_message.dart';
import '../../models/message_anchor.dart';
import '../../models/formal_reply_receipt.dart';
import '../../models/character_state.dart';
import '../../models/memento.dart';
import '../../services/memento_service.dart';
import '../memento_screen.dart';
import '../../services/story/character_state_service.dart';
import '../../services/story/character_state_prompt.dart';
import '../../services/story/story_checkpoint_service.dart';
import '../../services/speech/role_speech_controller.dart';
import '../character_voice_settings_screen.dart';
import '../../widgets/character_state_card.dart';
import '../../utils/privacy_password_prompt.dart';
import 'story_checkpoints_screen.dart';
import '../../models/chat_reply_variant.dart';
import '../../models/chat_session.dart';
import '../../models/chat_summary.dart';
import '../../models/character_memory_entry.dart';
import '../../models/user_profile.dart';
import '../../models/world_book.dart';
import '../../prompts/prompt_builder.dart';
import '../../services/ai/ai_gateway.dart';
import '../../services/ai_service.dart';
import '../../services/chat/character_inner_voice_service.dart';
import '../../services/chat/reply_inspiration_service.dart';
import '../../widgets/chat/reply_inspiration_sheet.dart';
import '../../services/chat/chat_summary_service.dart';
import '../../services/chat/memory_context_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/storage/session_operation_coordinator.dart';
import '../../utils/app_i18n.dart';
import '../../utils/chat_context_policy.dart';
import '../../utils/chat_search.dart';
import '../../utils/chat_text_export.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/page_layout.dart';
import '../../utils/snack.dart';
import '../../utils/stream_text_buffer.dart';
import '../../utils/role_message_segments.dart';
import '../../widgets/app_background.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/chat_bubble_preset_picker.dart';
import '../../widgets/chat_input_composer.dart';
import '../../widgets/chat_header_panel.dart';
import '../../widgets/chat/character_inner_voice_dialog.dart';
import '../../widgets/chat/character_inner_voice_preview.dart';
import '../../widgets/chat_variant_controls.dart';
import '../../widgets/endpoint_picker.dart';
import '../../widgets/message_content.dart';
import '../../widgets/message_bubble_parts.dart';
import '../../widgets/setting_slider.dart';
import 'chat_session_list_screen.dart';
import 'memory_edit_screen.dart';
import 'memory_manager_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.storage,
    required this.aiService,
    required this.character,
    required this.settings,
    this.session,
    super.key,
  });

  final LocalStorageService storage;
  final AiGateway aiService;
  final AppCharacter character;
  final AppSettings settings;
  final ChatSession? session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final CharacterStateService _stateService;
  CharacterStateView? _characterState;
  bool _stateBusy = false;
  bool _storyScreenOpen = false;
  bool _foreground = true;
  void _stopStoryEffects() {
    unawaited(_speech.stop());
    if (_session != null) _stateService.cancelStateRefresh(_session!.id);
  }

  MementoService get _mementos =>
      MementoService(storage: widget.storage, authorize: _authorizeStory);
  Future<void> _openCollection() async {
    unawaited(_speech.stop());
    _storyScreenOpen = true;
    if (_session != null) _stateService.cancelStateRefresh(_session!.id);
    final chatRoute = ModalRoute.of(context);
    MementoSnapshot? located;
    int? locatedIndex;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MementoScreen(
          service: _mementos,
          innerVoiceEnabled: widget.settings.showCharacterInnerVoice,
          characterId: _character.id,
          onLocate: (snapshot, index, result) async {
            if (result != SourceNavigationResult.found) {
              context.showSnack(context.t('来源消息已删除或改变，不会自动切换候选'));
              return;
            }
            located = snapshot;
            locatedIndex = index;
            Navigator.of(context).popUntil((route) => route == chatRoute);
          },
        ),
      ),
    );
    _storyScreenOpen = false;
    if (located != null && mounted) {
      await _waitForActiveGeneration();
      if (!mounted || _hasUnsavedReply) return;
      final sessions = await widget.storage.loadChatSessions(_character.id);
      final session = sessions
          .where((s) => s.id == located!.sourceSessionId)
          .firstOrNull;
      if (session == null) return;
      _session = session;
      await _load();
      final target = located!.entries[locatedIndex!];
      final index = _messages.indexWhere((m) => m.id == target.sourceMessageId);
      if (index >= 0 && mounted) {
        setState(() {
          _searchResults = [index];
          _activeSearchResult = 0;
        });
        _scrollToSearchResult(index);
      }
    }
  }

  Future<void> _messageStoryActions(int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final choice in [
              ('checkpoint', '保存剧情存档'),
              ('fork', '从这里创建分支'),
              ('collect', '加入回忆册'),
              ('multi', '多选加入回忆册'),
            ])
              ListTile(
                title: Text(c.t(choice.$2)),
                onTap: () => Navigator.pop(c, choice.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'checkpoint' || action == 'fork') {
      await _saveCheckpoint(index, fork: action == 'fork');
      return;
    }
    if (action == 'collect' || action == 'multi') {
      await _collectMessages(index, multiple: action == 'multi');
    }
  }

  Future<void> _collectMessages(int index, {bool multiple = false}) async {
    if (!_canMutateConversation || _hasUnsavedReply) return;
    final session = _currentSession;
    final captured = List<ChatMessage>.of(_messages);
    final epoch = widget.storage.datasetEpoch;
    final selected = <int>{index};
    if (multiple) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, setDialog) => AlertDialog(
            title: Text(c.t('选择 1–50 条消息')),
            content: SizedBox(
              width: 500,
              height: 400,
              child: ListView(
                children: [
                  for (var i = 0; i < captured.length; i++)
                    if (captured[i].effectiveContent.trim().isNotEmpty)
                      CheckboxListTile(
                        value: selected.contains(i),
                        title: Text(
                          captured[i].effectiveContent,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (v) => setDialog(() {
                          if (v == true && selected.length < 50) {
                            selected.add(i);
                          } else {
                            selected.remove(i);
                          }
                        }),
                      ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(c.t('取消')),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(c, true),
                child: Text(c.t('继续')),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    final indices = selected.toList()..sort();
    final metadata = await editMementoMetadata(
      context,
      title: captured[indices.first].effectiveContent.characters
          .take(20)
          .toString(),
    );
    if (metadata == null) return;
    try {
      if (!_canMutateConversation ||
          _hasUnsavedReply ||
          epoch != widget.storage.datasetEpoch ||
          _session?.id != session.id ||
          indices.any(
            (i) => !MessageAnchor.capture(
              session.id,
              captured,
              i,
            ).matches(_messages),
          )) {
        throw StateError('对话已变化，请重新选择');
      }
      final service = _mementos;
      final profile = widget.settings.userProfile;
      final roleAvatar = await service.copyRecognizedAvatar(
        _character.avatar,
        recognizedPaths: {_character.avatar},
      );
      final userAvatar = await service.copyRecognizedAvatar(
        profile.avatar,
        recognizedPaths: {profile.avatar},
      );
      final draft = MementoDraft(
        idempotencyKey: newStoryId(),
        title: metadata.title,
        tags: metadata.tags,
        note: metadata.note,
        characterId: _character.id,
        characterNameSnapshot: _character.name,
        sessionTitleSnapshot: session.title,
        sourceSessionId: session.id,
        requiresUnlock: _character.isLocked,
        entries: [
          for (final i in indices)
            MementoEntry.capture(
              sessionId: session.id,
              messages: captured,
              index: i,
              speakerName: captured[i].isUser ? profile.name : _character.name,
              avatarAssetId: captured[i].isUser ? userAvatar : roleAvatar,
            ),
        ],
      );
      if (await service.hasEquivalentCapture(draft)) {
        if (!mounted ||
            !await showConfirmDialog(
              context: context,
              title: context.isEnglish ? 'Save another copy?' : '再次收藏？',
              content: context.isEnglish
                  ? 'These same messages are already in your collection. Save another snapshot?'
                  : '这些消息已经收藏过，仍要保存一份新的回忆吗？',
            )) {
          return;
        }
      }
      if (epoch != widget.storage.datasetEpoch) throw StateError('数据已更新');
      await service.createMemento(draft);
      if (mounted) context.showSnack(context.t('已加入回忆册'));
    } catch (e) {
      if (mounted) context.showSnack('$e');
    }
  }

  RoleSpeechController get _speech => RoleSpeechController.instance;
  void _speechChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _configureSpeech() => _speech.configure(
    enabled: widget.settings.enableCharacterSpeech,
    allowNetworkVoices: widget.settings.allowNetworkSpeechVoices,
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      unawaited(_speech.stop());
      if (_session != null) _stateService.cancelStateRefresh(_session!.id);
    }
  }

  Future<void> _reloadState() async {
    final session = _session;
    if (session == null ||
        !widget.settings.showCharacterStateCard ||
        !widget.storage.usesSessionStorage) {
      return;
    }
    final epoch = widget.storage.datasetEpoch;
    try {
      final state = await _stateService.loadCurrentState(
        session.id,
        _character.id,
        _messages.where((m) => m.effectiveContent.trim().isNotEmpty).toList(),
      );
      if (mounted &&
          _session?.id == session.id &&
          epoch == widget.storage.datasetEpoch) {
        setState(() => _characterState = state);
      }
    } catch (e) {
      if (mounted) context.showSnack('$e');
    }
  }

  Future<void> _refreshState({
    AiEndpointConfig? endpoint,
    List<ChatMessage>? messages,
  }) async {
    final session = _session;
    if (session == null || !widget.settings.showCharacterStateCard) return;
    endpoint ??= _apiConfig.endpointById(_selectedEndpointId);
    if (endpoint == null) throw StateError('未配置 API');
    final selectedEndpoint = endpoint;
    final snapshot = List<ChatMessage>.of(messages ?? _messages);
    final digest = MessageAnchor.digest(snapshot);
    final epoch = widget.storage.datasetEpoch;
    setState(() => _stateBusy = true);
    try {
      await _stateService.requestStateRefresh(
        StateRefreshContext(
          sessionId: session.id,
          characterId: _character.id,
          messages: snapshot,
          characterContext: PromptBuilder.buildSystemPrompt(_character),
          loadMessages: () => widget.storage.loadChatBySession(session),
          isCurrent: () =>
              mounted &&
              !_storyScreenOpen &&
              widget.settings.showCharacterStateCard &&
              _session?.id == session.id &&
              epoch == widget.storage.datasetEpoch &&
              digest == MessageAnchor.digest(_messages),
          generate: (system, user, token) async {
            final request = [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ];
            return widget.aiService.sendMessage(
              apiKey: selectedEndpoint.apiKey,
              baseUrl: selectedEndpoint.baseUrl,
              model: selectedEndpoint.model,
              messages: request,
              cancelToken: token,
              onUsage: (usage) {
                unawaited(
                  widget.storage
                      .recordAiUsage(
                        requestType: 'characterState',
                        summaryUpdated: false,
                        model: selectedEndpoint.model,
                        usage: usage,
                        messages: request,
                      )
                      .catchError((Object _) {}),
                );
              },
            );
          },
        ),
      );
      await _reloadState();
    } finally {
      if (mounted) setState(() => _stateBusy = false);
    }
  }

  void _dispatchFormalReceipt(FormalReplyReceipt receipt) {
    if (!receipt.persisted ||
        receipt.replyState != 'completed' ||
        receipt.epoch != widget.storage.datasetEpoch ||
        _session?.id != receipt.anchor.sessionId ||
        !receipt.anchor.matches(_messages)) {
      return;
    }
    if (widget.settings.showCharacterStateCard &&
        widget.settings.autoUpdateCharacterState) {
      unawaited(
        _refreshState(
          endpoint: receipt.endpointSnapshot,
          messages: receipt.messages,
        ).catchError((Object e) {
          if (mounted) context.showSnack(context.t('状态更新失败，原状态已保留'));
        }),
      );
    }
    unawaited(
      _speech.autoReadSavedReply(
        message: receipt.messages.last,
        sessionId: receipt.anchor.sessionId,
        messageId: receipt.anchor.messageId,
        variantId: receipt.anchor.variantId ?? '',
        datasetEpoch: receipt.epoch,
        profile: receipt.characterSnapshot.voiceProfiles[_speech.platformKey],
        persisted: true,
        selected: true,
        enabled:
            widget.settings.enableCharacterSpeech &&
            widget.settings.autoReadAssistantReplies &&
            !_storyScreenOpen &&
            _foreground &&
            !_isOpeningSessionList &&
            (ModalRoute.of(context)?.isCurrent ?? false),
      ),
    );
  }

  Future<bool> _authorizeStory(String characterId, bool requiresUnlock) async {
    if (!requiresUnlock) return true;
    final settings = await widget.storage.loadSettings();
    if (!mounted) return false;
    return verifyPrivacyPassword(
      context: context,
      settings: settings,
      storage: widget.storage,
      title: context.t('解锁私密内容'),
    );
  }

  StoryCheckpointService get _checkpoints =>
      StoryCheckpointService(widget.storage, authorize: _authorizeStory);
  Future<void> _openCheckpoints() async {
    unawaited(_speech.stop());
    _storyScreenOpen = true;
    if (_session != null) _stateService.cancelStateRefresh(_session!.id);
    ChatSession? selected;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (c) => StoryCheckpointsScreen(
          service: _checkpoints,
          characterId: _character.id,
          onFork: (s) {
            selected = s;
            Navigator.pop(c);
          },
        ),
      ),
    );
    _storyScreenOpen = false;
    if (selected != null && mounted && !_hasUnsavedReply) {
      await _waitForActiveGeneration();
      if (mounted) {
        _session = selected;
        await _load();
      }
    }
  }

  Future<void> _saveCheckpoint(int index, {bool fork = false}) async {
    if (!_canMutateConversation ||
        _hasUnsavedReply ||
        index >= _messages.length) {
      return;
    }
    final session = _currentSession;
    final anchor = MessageAnchor.capture(session.id, _messages, index);
    final title = await storyNameDialog(
      context,
      fork ? '新分支名称' : '保存剧情存档',
      initial: session.title,
    );
    if (title == null || !mounted) return;
    try {
      if (!_canMutateConversation ||
          _hasUnsavedReply ||
          _session?.id != session.id ||
          !anchor.matches(_messages)) {
        throw StateError('对话已变化，请重新选择');
      }
      final prefix = _messages.take(index + 1).toList();
      final state = await _stateService.loadCurrentState(
        session.id,
        _character.id,
        prefix,
      );
      if (!_canMutateConversation ||
          _hasUnsavedReply ||
          _session?.id != session.id) {
        throw StateError('对话已变化，请重新选择');
      }
      final checkpoint = await _checkpoints.create(
        source: session,
        character: _character,
        anchor: anchor,
        title: title,
        initialState: state.toJson(),
      );
      if (fork) {
        final branch = await _checkpoints.fork(checkpoint.id, title: title);
        if (mounted) {
          _session = branch;
          await _load();
        }
      }
      if (mounted) context.showSnack(context.t(fork ? '剧情分支已创建' : '剧情存档已保存'));
    } catch (e) {
      if (mounted) context.showSnack('$e');
    }
  }

  Future<void> _playReply(ChatMessage message) async {
    final capturedSession = _session;
    if (capturedSession == null) return;
    final epoch = widget.storage.datasetEpoch;
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    final anchor = MessageAnchor.capture(capturedSession.id, _messages, index);
    if (_speech.messageId == message.id && _speech.isPlaying) {
      await _speech.stop();
      return;
    }
    if (message.effectiveReplyState == 'interrupted' &&
        !await showConfirmDialog(
          context: context,
          title: '朗读中断的回复',
          content: context.t('这条回复未完成，仍然朗读已保存的正文？'),
        )) {
      return;
    }
    if (!mounted ||
        !_foreground ||
        epoch != widget.storage.datasetEpoch ||
        _session?.id != capturedSession.id ||
        !anchor.matches(_messages)) {
      return;
    }
    await _speech.playMessage(
      message: message,
      sessionId: _currentSession.id,
      messageId: message.id,
      variantId: logicalVariantId(message),
      datasetEpoch: widget.storage.datasetEpoch,
      profile: _character.voiceProfiles[_speech.platformKey],
    );
    if (mounted &&
        (_speech.error == 'network_unknown' ||
            _speech.error == 'network_voice_blocked') &&
        !widget.settings.allowNetworkSpeechVoices) {
      final allowed = await showConfirmDialog(
        context: context,
        title: context.isEnglish ? 'Allow this system voice?' : '允许此次系统语音？',
        content: context.isEnglish
            ? 'This voice may send the reply text to its engine provider over the network. Allow for this playback only?'
            : '该音色可能通过网络向语音引擎服务商发送正文。仅允许此次朗读吗？',
      );
      if (allowed &&
          mounted &&
          _foreground &&
          epoch == widget.storage.datasetEpoch &&
          _session?.id == capturedSession.id &&
          anchor.matches(_messages)) {
        _speech.configure(enabled: true, allowNetworkVoices: true);
        try {
          await _speech.playMessage(
            message: message,
            sessionId: capturedSession.id,
            messageId: message.id,
            variantId: logicalVariantId(message),
            datasetEpoch: epoch,
            profile: _character.voiceProfiles[_speech.platformKey],
          );
        } finally {
          _configureSpeech();
        }
      }
    }
    if (mounted && _speech.error != null) {
      context.showSnack(
        speechErrorText(_speech.error!, english: context.isEnglish),
      );
    }
  }

  final _inputController = TextEditingController();
  bool _inspirationOpen = false;

  Future<void> _openReplyInspiration() async {
    if (_inspirationOpen || !_canUseNonDestructiveControls) return;
    _inspirationOpen = true;
    final epoch = widget.storage.datasetEpoch;
    final sessionId = _session?.id;
    final revision = _conversationRevision;
    final characterName = _character.name;
    final recent = List<ChatMessage>.of(_messages);
    final draft = _inputController.text;
    const service = ReplyInspirationService();
    bool current() =>
        mounted &&
        _isCurrentConversation(epoch, sessionId) &&
        revision == _conversationRevision;
    try {
      final suggestion = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ReplyInspirationSheet(
          generate: (mode, token) async {
            final config = await widget.storage.loadApiConfig();
            if (!current() || token.isCancelled) throw AiException('请求已取消。');
            final endpoint = config.effectiveEndpoint(_selectedEndpointId);
            final error = endpointValidationError(endpoint);
            if (error != null) throw AiException(error);
            final messages = service.buildMessages(
              characterName: characterName,
              recentMessages: recent,
              draft: draft,
              mode: mode,
            );
            final raw = await widget.aiService.sendMessage(
              apiKey: endpoint!.apiKey,
              baseUrl: endpoint.baseUrl,
              model: endpoint.model,
              messages: messages,
              cancelToken: token,
              onUsage: (usage) {
                if (!current()) return;
                unawaited(
                  _recordUsage(
                    requestType: 'characterReplyInspiration',
                    model: endpoint.model,
                    usage: usage,
                    messages: messages,
                    summaryUpdated: false,
                  ),
                );
              },
            );
            if (!current() || token.isCancelled) throw AiException('请求已取消。');
            return service.parse(raw);
          },
        ),
      );
      if (suggestion == null || !current()) return;
      // Preserve the existing draft; insertion is never a send action.
      final value = _inputController.value;
      final selection = value.selection;
      final start = selection.isValid ? selection.end : value.text.length;
      final inserted = start > 0 && value.text[start - 1] != '\n'
          ? '\n$suggestion'
          : suggestion;
      _inputController.value = TextEditingValue(
        text: value.text.replaceRange(start, start, inserted),
        selection: TextSelection.collapsed(offset: start + inserted.length),
      );
      _inputFocusNode.requestFocus();
    } finally {
      _inspirationOpen = false;
    }
  }

  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _toolBarTimer;

  var _apiConfig = ApiConfig();
  late AppCharacter _character;
  late final ChatConversationController _conversation;
  ChatSession? _session;
  ChatSession get _currentSession => _session!;
  List<ChatMessage> get _messages => _conversation.messages;
  ChatSummary get _summary => _conversation.summary;
  var _selectedEndpointId = '';
  var _isLoading = true;
  var _isSending = false;
  var _isSummarizing = false;
  var _isCancellingGeneration = false;
  var _isOpeningSessionList = false;
  var _showToolBar = false;
  var _searchQuery = '';
  var _searchResults = <int>[];
  var _activeSearchResult = 0;
  var _generationId = 0;
  var _summaryOperationId = 0;
  int? _variantGenerationIndex;
  AiCancelToken? _cancelToken;
  AiCancelToken? _summaryCancelToken;
  Future<void>? _generationCancellationFuture;
  Completer<void>? _generationCompletion;
  StreamTextBuffer? _streamBuffer;
  String? _loadError;
  var _nextInnerVoiceOperationId = 0;
  final _innerVoiceOperations = <int, _InnerVoiceOperation>{};
  final _failedInnerVoiceTargets = <int, _InnerVoiceTarget>{};
  final _innerVoiceFailureTimers = <int, Timer>{};
  Future<void> _chatSaveTail = Future<void>.value();
  final _draft = ValueNotifier<ChatMessage?>(null);
  void Function(String state)? _finalizeDraft;
  int _generationEpoch = 0;
  int _conversationRevision = 0;
  SessionOperationToken? _generationStorageToken;
  bool _hasUnsavedReply = false;
  bool _isClearing = false;
  int _loadOperationId = 0;

  bool get _hasActiveChatOperation =>
      _isLoading ||
      _isSending ||
      _isSummarizing ||
      _isCancellingGeneration ||
      _isOpeningSessionList;
  bool get _canMutateConversation =>
      !_isClearing &&
      !_isLoading &&
      !_isSending &&
      !_isSummarizing &&
      !_isCancellingGeneration &&
      !_isOpeningSessionList;
  bool get _canUseNonDestructiveControls =>
      !_isClearing &&
      !_isLoading &&
      !_isSummarizing &&
      !_isCancellingGeneration;

  ChatBubbleAppearance get _roleBubbleAppearance => resolveBubbleAppearance(
    presetId: _character.roleBubblePresetId,
    fallback: _character.bubbleTheme.role,
    opacityOverride: _character.roleBubbleOpacity,
  );

  ChatBubbleAppearance get _userBubbleAppearance => resolveBubbleAppearance(
    presetId: _character.userBubblePresetId,
    fallback: _character.bubbleTheme.user,
    opacityOverride: _character.userBubbleOpacity,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateService = CharacterStateService(widget.storage);
    _configureSpeech();
    _speech.addListener(_speechChanged);
    _character = widget.character;
    _conversation = ChatConversationController(characterId: _character.id);
    widget.storage.datasetEpochListenable.addListener(_datasetChanged);
    unawaited(_load());
  }

  void _datasetChanged() {
    unawaited(_speech.stop());
    if (_session != null) _stateService.cancelStateRefresh(_session!.id);
    _characterState = null;
    _generationId++;
    _conversationRevision++;
    _cancelToken?.cancel();
    _summaryCancelToken?.cancel();
    _invalidateSummaryOperations();
    _cancelAllInnerVoiceOperations();
    _streamBuffer?.dispose();
    _finalizeDraft = null;
    _draft.value = null;
    if (_generationCompletion != null) {
      _completeGenerationOperation(_generationCompletion!);
    }
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _isSummarizing = false;
      _hasUnsavedReply = false;
      _session = null;
      _conversation.clearMessages();
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureSpeech();
    if (!widget.settings.showCharacterStateCard ||
        !widget.settings.autoUpdateCharacterState) {
      if (_session != null) _stateService.cancelStateRefresh(_session!.id);
    }
    if (widget.settings.showCharacterStateCard &&
        !oldWidget.settings.showCharacterStateCard) {
      unawaited(_reloadState());
    }
    if (oldWidget.settings.showCharacterInnerVoice &&
        !widget.settings.showCharacterInnerVoice) {
      _cancelAllInnerVoiceOperations();
      _clearInnerVoiceFailures();
    }
  }

  @override
  void dispose() {
    _speech.removeListener(_speechChanged);
    unawaited(_speech.stop());
    WidgetsBinding.instance.removeObserver(this);
    if (_session != null) _stateService.cancelStateRefresh(_session!.id);
    widget.storage.datasetEpochListenable.removeListener(_datasetChanged);
    _generationId++;
    _invalidateSummaryOperations();
    _cancelToken?.cancel();
    _summaryCancelToken?.cancel();
    _cancelAllInnerVoiceOperations(updateUi: false);
    _clearInnerVoiceFailures();
    _streamBuffer?.dispose();
    _draft.dispose();
    _toolBarTimer?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final epoch = widget.storage.datasetEpoch;
    final operationId = ++_loadOperationId;
    bool current() =>
        mounted &&
        epoch == widget.storage.datasetEpoch &&
        operationId == _loadOperationId;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final apiConfig = await widget.storage.loadApiConfig();
      if (!current()) return;
      if (widget.storage.usesSessionStorage) {
        final characters = await widget.storage.loadCharacters();
        if (!current()) return;
        final refreshed = characters
            .where((item) => item.id == _character.id)
            .firstOrNull;
        if (refreshed == null) throw StateError('当前数据集中没有此角色，请返回角色列表');
        _character = refreshed;
      }
      var activeSession =
          _session ??
          widget.session ??
          (widget.storage.usesSessionStorage
              ? await widget.storage.getOrCreateRecentChatSession(_character.id)
              : _compatibilitySession());
      if (widget.storage.usesSessionStorage) {
        final storedSessions = await widget.storage.loadChatSessions(
          activeSession.characterId,
        );
        if (!current()) return;
        if (!storedSessions.any((item) => item.id == activeSession.id)) {
          activeSession = await widget.storage.getOrCreateRecentChatSession(
            _character.id,
          );
        }
        for (final storedSession in storedSessions) {
          if (storedSession.id == activeSession.id) {
            activeSession = storedSession;
            break;
          }
        }
      }
      final summary = widget.storage.usesSessionStorage
          ? await widget.storage.loadSummaryBySession(activeSession)
          : await widget.storage.loadSummary(_character.id);
      final chat = widget.storage.usesSessionStorage
          ? await widget.storage.loadChatBySession(activeSession)
          : await widget.storage.loadChat(_character.id);
      final selectedEndpointId =
          apiConfig.effectiveEndpoint(_character.defaultEndpointId)?.id ?? '';
      var messages = [...chat];
      if (!current()) return;

      if (widget.storage.usesSessionStorage) {
        if (!activeSession.openingMessageInitialized) {
          if (messages.isEmpty && _character.openingMessage.trim().isNotEmpty) {
            messages = [
              ChatMessage(
                role: 'assistant',
                content: _character.openingMessage.trim(),
                time: DateTime.now(),
                endpointId: selectedEndpointId,
                endpointName: apiConfig.endpointById(selectedEndpointId)?.name,
              ),
            ];
            final saved = await widget.storage.saveChatBySessionIfExists(
              activeSession,
              messages,
              token: await widget.storage.captureSessionToken(activeSession),
            );
            if (!saved || !current()) return;
          }
          activeSession = await widget.storage.markOpeningMessageInitialized(
            sessionId: activeSession.id,
            characterId: activeSession.characterId,
          );
        }
      } else if (messages.isEmpty &&
          _character.openingMessage.trim().isNotEmpty) {
        messages = [
          ChatMessage(
            role: 'assistant',
            content: _character.openingMessage.trim(),
            time: DateTime.now(),
            endpointId: selectedEndpointId,
            endpointName: apiConfig.endpointById(selectedEndpointId)?.name,
          ),
        ];
        await widget.storage.saveChat(_character.id, messages);
      }

      if (!current()) return;
      setState(() {
        _apiConfig = apiConfig;
        _session = activeSession;
        _selectedEndpointId = selectedEndpointId;
        _conversation.load(messages: messages, summary: summary);
        _isLoading = false;
      });
      unawaited(_reloadState());
    } catch (error) {
      if (!current()) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  ChatSession _compatibilitySession() {
    final now = DateTime.now();
    return ChatSession(
      id: 'legacy_runtime_${_character.id}',
      characterId: _character.id,
      title: '默认对话',
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
  }

  Future<void> _saveCurrentChat() async {
    final session = _currentSession;
    final messages = List<ChatMessage>.of(_messages);
    final epoch = widget.storage.datasetEpoch;
    await _enqueueChatSave(() async {
      if (epoch != widget.storage.datasetEpoch) throw StateError('数据集已更新');
      if (widget.storage.usesSessionStorage) {
        await widget.storage.saveChatBySession(session, messages);
      } else {
        await widget.storage.saveChat(_character.id, messages);
      }
    });
    if (_isCurrentConversation(epoch, session.id) && _hasUnsavedReply) {
      setState(() => _hasUnsavedReply = false);
    }
    unawaited(_reloadState());
  }

  Future<bool> _saveChatSnapshotIfSessionExists(
    ChatSession session,
    List<ChatMessage> messages, {
    SessionOperationToken? token,
  }) async {
    final epoch = widget.storage.datasetEpoch;
    final saved = await _enqueueChatSave(() async {
      if (epoch != widget.storage.datasetEpoch) return false;
      if (widget.storage.usesSessionStorage) {
        return widget.storage.saveChatBySessionIfExists(
          session,
          messages,
          token: token,
        );
      }
      await widget.storage.saveChat(_character.id, messages);
      return true;
    });
    if (saved &&
        _isCurrentConversation(epoch, session.id) &&
        _hasUnsavedReply) {
      setState(() => _hasUnsavedReply = false);
    }
    return saved;
  }

  bool _isCurrentConversation(int epoch, String? sessionId) =>
      mounted &&
      epoch == widget.storage.datasetEpoch &&
      _session?.id == sessionId;

  Future<T> _enqueueChatSave<T>(Future<T> Function() save) {
    final result = Completer<T>();
    _chatSaveTail = _chatSaveTail.then((_) async {
      try {
        result.complete(await save());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _saveCurrentSummary() async {
    await _saveSummary(_summary);
  }

  Future<void> _saveSummary(
    ChatSummary summary, {
    SessionOperationToken? token,
  }) async {
    if (widget.storage.usesSessionStorage) {
      await widget.storage.saveSummaryBySession(summary, token: token);
    } else {
      await widget.storage.saveSummary(summary);
    }
  }

  Future<void> _recordUsage({
    required String requestType,
    required String model,
    required AiUsage usage,
    required List<Map<String, String>> messages,
    required bool summaryUpdated,
  }) async {
    final epoch = widget.storage.datasetEpoch;
    try {
      await widget.storage.recordAiUsage(
        requestType: requestType,
        model: model,
        usage: usage,
        messages: messages,
        summaryUpdated: summaryUpdated,
      );
    } catch (error) {
      if (mounted && epoch == widget.storage.datasetEpoch) {
        context.showSnack('用量统计保存失败：$error');
      }
    }
  }

  Future<void> _send() async {
    final epoch = widget.storage.datasetEpoch;
    final entrySessionId = _session?.id;
    final text = _inputController.text.trim();
    if (text.isEmpty || !_canMutateConversation) {
      return;
    }

    _invalidateSummaryOperations();
    final endpoint = await _reloadEndpoint();
    if (endpoint == null ||
        !_canMutateConversation ||
        !_isCurrentConversation(epoch, entrySessionId)) {
      return;
    }

    final sessionId = _currentSession.id;
    final userMessage = ChatMessage(
      role: 'user',
      content: text,
      time: DateTime.now(),
    );
    final previousMessages = [..._messages];
    final generationCompletion = _beginGenerationOperation();

    try {
      setState(() {
        _conversation.append(userMessage);
        _isSending = true;
      });
      _inputController.clear();
      _scrollToEnd();

      try {
        await _saveCurrentChat();
      } catch (error) {
        if (!mounted || !_isCurrentConversation(epoch, sessionId)) return;
        setState(() {
          _conversation.replaceMessages(previousMessages);
          _isSending = false;
        });
        if (_inputController.text.isEmpty) _inputController.text = text;
        context.showSnack(error.toString());
        return;
      }

      if (!_isCurrentConversation(epoch, sessionId) || !_isSending) return;

      await _requestAssistantReply(endpoint);
    } finally {
      _completeGenerationOperation(generationCompletion);
    }
  }

  Future<AiEndpointConfig?> _reloadEndpoint() async {
    final epoch = widget.storage.datasetEpoch;
    final sessionId = _session?.id;
    try {
      final config = await widget.storage.loadApiConfig();
      final endpoint = config.effectiveEndpoint(_selectedEndpointId);
      if (!mounted || !_isCurrentConversation(epoch, sessionId)) return null;
      setState(() {
        _apiConfig = config;
        _selectedEndpointId = endpoint?.id ?? '';
      });
      final error = endpointValidationError(endpoint);
      if (error != null) {
        context.showSnack(error);
        return null;
      }
      return endpoint;
    } catch (error) {
      if (mounted && _isCurrentConversation(epoch, sessionId)) {
        context.showSnack(error.toString());
      }
      return null;
    }
  }

  Future<void> _requestAssistantReply(
    AiEndpointConfig endpoint, {
    int? variantAt,
  }) async {
    final generationId = ++_generationId;
    final sessionId = _currentSession.id;
    final session = _currentSession;
    _generationEpoch = widget.storage.datasetEpoch;
    final epoch = _generationEpoch;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    StreamTextBuffer? requestBuffer;
    var networkCompleted = false;
    var committed = false;
    ChatMessage? assistantMessage;
    final reply = StringBuffer();
    final reasoning = StringBuffer();
    var placeholder = false;
    SessionOperationToken? storageToken;
    void finalize(String state) {
      if (committed || !_isCurrentGeneration(generationId, sessionId)) return;
      committed = true;
      if (variantAt != null && state != 'completed') return;
      final replyText = reply.toString();
      final reasoningText = reasoning.toString();
      if (replyText.trim().isEmpty) {
        if (placeholder) _conversation.dropEmptyAssistantTail();
        _draft.value = null;
        return;
      }
      final message = assistantMessage!.copyWith(
        content: replyText,
        reasoningContent: reasoningText,
        replyState: state,
      );
      if (variantAt != null) {
        _conversation.addAssistantVariant(
          variantAt,
          ChatReplyVariant(
            content: replyText,
            reasoningContent: reasoningText,
            replyState: state,
            time: message.time,
            endpointId: endpoint.id,
            endpointName: endpoint.name,
            model: endpoint.model,
          ),
        );
      } else if (placeholder) {
        _conversation.replaceLast(message);
      } else {
        _conversation.append(message);
      }
      _draft.value = null;
    }

    _finalizeDraft = finalize;
    try {
      if (widget.storage.usesSessionStorage) {
        storageToken = await widget.storage.captureSessionToken(session);
      }
      if (!_isCurrentGeneration(generationId, sessionId)) return;
      _generationStorageToken = storageToken;
      final summaryUpdated = variantAt == null
          ? await _updateRollingSummary(endpoint, generationId, cancelToken)
          : false;
      if (!_isCurrentGeneration(generationId, sessionId)) return;

      final chatSettings = await widget.storage.loadSettings();
      final userProfile = chatSettings.userProfile;
      final contextMessages = variantAt == null
          ? List<ChatMessage>.of(_messages)
          : _messages.take(variantAt).toList();
      final memories = widget.storage.usesSessionStorage
          ? await widget.storage.loadCharacterMemories(_character.id)
          : const <CharacterMemoryEntry>[];
      if (widget.storage.usesSessionStorage) {
        final refreshedCharacter = (await widget.storage.loadCharacters())
            .where((character) => character.id == _character.id)
            .firstOrNull;
        if (refreshedCharacter != null) {
          _character = refreshedCharacter;
        }
      }
      final allWorldBooks = widget.storage.usesSessionStorage
          ? await widget.storage.loadWorldBooks()
          : const <WorldBook>[];
      final referencedIds = _character.worldBookIds.toSet();
      final worldBooks = allWorldBooks
          .where((worldBook) => referencedIds.contains(worldBook.id))
          .toList();
      final worldBookEntries = <WorldBookEntry>[];
      for (final worldBook in worldBooks.where(
        (worldBook) => worldBook.enabled,
      )) {
        worldBookEntries.addAll(
          await widget.storage.loadWorldBookEntries(worldBook.id),
        );
      }
      if (!_isCurrentGeneration(generationId, sessionId)) return;
      final context = const MemoryContextService().build(
        entries: session.isStoryBranch && !session.allowSharedCharacterMemories
            ? memories.where(
                (entry) =>
                    entry.scope == MemoryScope.session &&
                    entry.sessionId == session.id,
              )
            : memories,
        characterId: _character.id,
        sessionId: sessionId,
        messages: contextMessages,
        maxCharacters: chatSettings.memoryContextMaxCharacters,
        worldBooks: worldBooks,
        worldBookEntries: worldBookEntries,
        worldBookIds: _character.worldBookIds,
      );
      final requestMessages = _buildChatRequestMessages(
        userProfile,
        memoryPrompt: context.memoryPrompt,
        messages: contextMessages,
      );
      if (chatSettings.showCharacterStateCard &&
          chatSettings.useCharacterStateInPrompt &&
          widget.storage.usesSessionStorage) {
        final state = await _stateService.loadCurrentState(
          session.id,
          _character.id,
          contextMessages,
        );
        final prompt = buildCharacterStatePrompt(
          state,
          showCard: true,
          useInPrompt: true,
        );
        if (prompt.isNotEmpty) {
          requestMessages.insert(1, {'role': 'system', 'content': prompt});
        }
      }
      final streamResponses = widget.settings.streamResponses;
      assistantMessage = ChatMessage(
        role: 'assistant',
        content: '',
        time: DateTime.now(),
        endpointId: endpoint.id,
        endpointName: endpoint.name,
        model: endpoint.model,
      );
      if (streamResponses && variantAt == null) {
        setState(() {
          _conversation.append(assistantMessage!);
          placeholder = true;
          _draft.value = assistantMessage;
        });
      }

      requestBuffer = StreamTextBuffer(
        onFlush: (delta) {
          if (!streamResponses ||
              !_isCurrentGeneration(generationId, sessionId)) {
            return;
          }
          if (variantAt == null) {
            _draft.value = assistantMessage!.copyWith(
              content: reply.toString(),
              reasoningContent: reasoning.toString(),
            );
          }
        },
      );
      _streamBuffer = requestBuffer;
      final request = AiRequest(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: requestMessages,
        stream: streamResponses,
        includeReasoning: true,
      );
      await for (final chunk in _responseDeltas(request, cancelToken)) {
        if (!_isCurrentGeneration(generationId, sessionId)) return;
        reply.write(chunk.contentDelta);
        reasoning.write(chunk.reasoningDelta);
        requestBuffer.add(
          chunk.contentDelta.isEmpty ? '\u200b' : chunk.contentDelta,
        );
        final usage = chunk.usage;
        if (usage != null) {
          await widget.storage
              .recordAiUsage(
                requestType: variantAt == null
                    ? 'characterChat'
                    : 'characterChatVariant',
                model: endpoint.model,
                usage: usage,
                messages: requestMessages,
                summaryUpdated: summaryUpdated,
              )
              .catchError((Object error) {
                if (mounted && epoch == widget.storage.datasetEpoch) {
                  this.context.showSnack('用量统计保存失败：$error');
                }
              });
        }
      }
      requestBuffer.flush();
      if (reply.toString().trim().isEmpty) {
        throw AiException('API 没有返回可用回复。');
      }
      if (!_isCurrentGeneration(generationId, sessionId)) return;
      networkCompleted = true;
      setState(() => finalize('completed'));
      final messages = List<ChatMessage>.of(_messages);
      final saved = await _saveChatSnapshotIfSessionExists(
        session,
        messages,
        token: storageToken,
      );
      if (!saved) throw StateError('对话已更新或删除，回复未保存');
      if (_isCurrentGeneration(generationId, sessionId)) {
        setState(() => _isSending = false);
      }
      if (saved &&
          mounted &&
          generationId == _generationId &&
          _session?.id == sessionId) {
        final messageIndex = variantAt ?? _messages.length - 1;
        final variantIndex = variantAt == null
            ? null
            : _messages[messageIndex].selectedVariantIndex;
        _dispatchFormalReceipt(
          FormalReplyReceipt(
            operationId: '$sessionId:$generationId',
            anchor: MessageAnchor.capture(sessionId, messages, messageIndex),
            epoch: epoch,
            sessionToken: storageToken,
            endpointSnapshot: endpoint,
            characterSnapshot: _character,
            messages: messages.take(messageIndex + 1).toList(),
            persisted: true,
          ),
        );
        unawaited(
          _generateInnerVoiceForReply(
            endpoint: endpoint,
            session: session,
            messageIndex: messageIndex,
            variantIndex: variantIndex,
            replySnapshot: reply.toString(),
            characterDefinition: PromptBuilder.buildSystemPrompt(
              _character,
              userProfile: userProfile,
            ),
            recentMessages: contextMessages,
            memoryContext: context.memoryPrompt,
            chatSummary: _summary.summary,
          ),
        );
      }
    } catch (error) {
      if (!mounted ||
          generationId != _generationId ||
          _session?.id != sessionId ||
          epoch != widget.storage.datasetEpoch) {
        return;
      }
      requestBuffer?.flush();
      if (!networkCompleted) {
        setState(() => finalize('interrupted'));
        if (variantAt == null && reply.toString().trim().isNotEmpty) {
          try {
            final saved = await _saveChatSnapshotIfSessionExists(
              session,
              List<ChatMessage>.of(_messages),
              token: storageToken,
            );
            if (!saved) throw StateError('对话已更新');
          } catch (_) {
            if (mounted && epoch == widget.storage.datasetEpoch) {
              _hasUnsavedReply = true;
            }
          }
        }
      } else {
        _hasUnsavedReply = true;
      }
      if (!mounted || epoch != widget.storage.datasetEpoch) return;
      setState(() => _isSending = false);
      context.showSnack(error.toString());
    } finally {
      final ownedBuffer = requestBuffer;
      if (ownedBuffer != null) {
        ownedBuffer.flush();
        ownedBuffer.dispose();
        if (identical(_streamBuffer, ownedBuffer)) _streamBuffer = null;
      }
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      if (identical(_finalizeDraft, finalize)) _finalizeDraft = null;
      if (mounted &&
          generationId == _generationId &&
          _variantGenerationIndex == variantAt) {
        setState(() => _variantGenerationIndex = null);
      }
    }
  }

  Future<void> _generateInnerVoiceForReply({
    required AiEndpointConfig endpoint,
    required ChatSession session,
    required int messageIndex,
    required int? variantIndex,
    required String replySnapshot,
    required String characterDefinition,
    required List<ChatMessage> recentMessages,
    required String memoryContext,
    required String chatSummary,
  }) async {
    final revision = _conversationRevision;
    final epoch = widget.storage.datasetEpoch;
    _InnerVoiceOperation? operation;
    var failed = false;
    try {
      final latestSettings = await widget.storage.loadSettings();
      if (!mounted ||
          revision != _conversationRevision ||
          epoch != widget.storage.datasetEpoch ||
          !widget.settings.showCharacterInnerVoice ||
          !latestSettings.showCharacterInnerVoice ||
          _session?.id != session.id ||
          !_innerVoiceTargetExists(
            messageIndex: messageIndex,
            variantIndex: variantIndex,
            replySnapshot: replySnapshot,
          )) {
        return;
      }

      final previousInnerVoice = _conversation.assistantInnerVoiceAt(
        messageIndex: messageIndex,
        variantIndex: variantIndex,
        replySnapshot: replySnapshot,
      );
      if (previousInnerVoice == null) return;
      final target = _InnerVoiceTarget(
        sessionId: session.id,
        messageIndex: messageIndex,
        variantIndex: variantIndex,
        replySnapshot: replySnapshot,
      );
      final activeOperation = _InnerVoiceOperation(
        id: ++_nextInnerVoiceOperationId,
        target: target,
        cancelToken: AiCancelToken(),
        previousInnerVoice: previousInnerVoice,
        revision: revision,
        epoch: epoch,
      );
      if (widget.storage.usesSessionStorage) {
        activeOperation.storageToken = await widget.storage.captureSessionToken(
          session,
        );
      }
      if (!mounted ||
          revision != _conversationRevision ||
          epoch != widget.storage.datasetEpoch) {
        return;
      }
      operation = activeOperation;
      setState(() {
        _clearInnerVoiceFailureAt(messageIndex);
        _innerVoiceOperations[activeOperation.id] = activeOperation;
      });

      final requestMessages = const CharacterInnerVoiceService().buildMessages(
        characterName: _character.name,
        characterDefinition: characterDefinition,
        assistantReply: replySnapshot,
        recentMessages: recentMessages,
        memoryContext: memoryContext,
        chatSummary: chatSummary,
      );
      final raw = await widget.aiService.sendMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: requestMessages,
        cancelToken: activeOperation.cancelToken,
        onUsage: (usage) => unawaited(
          _recordUsage(
            requestType: 'characterInnerVoice',
            model: endpoint.model,
            usage: usage,
            messages: requestMessages,
            summaryUpdated: false,
          ),
        ),
      );
      final innerVoice = const CharacterInnerVoiceService().normalize(raw);
      if (innerVoice.isEmpty) {
        throw AiException('API 没有返回可用心声。');
      }
      activeOperation.generatedInnerVoice = innerVoice;

      final currentSettings = await widget.storage.loadSettings();
      if (!_isCurrentInnerVoiceOperation(activeOperation) ||
          !currentSettings.showCharacterInnerVoice) {
        return;
      }
      if (widget.storage.usesSessionStorage) {
        final sessions = await widget.storage.loadChatSessions(
          session.characterId,
        );
        if (!_isCurrentInnerVoiceOperation(activeOperation) ||
            !sessions.any((item) => item.id == session.id)) {
          return;
        }
      }

      var updated = false;
      setState(() {
        updated = _conversation.setAssistantInnerVoice(
          messageIndex: messageIndex,
          variantIndex: variantIndex,
          replySnapshot: replySnapshot,
          innerVoice: innerVoice,
        );
      });
      if (!updated || !_isCurrentInnerVoiceOperation(activeOperation)) return;
      activeOperation.applied = true;

      var messages = List<ChatMessage>.of(_messages);
      if (_isSending &&
          _variantGenerationIndex == null &&
          messages.isNotEmpty &&
          messages.last.isAssistant &&
          messageIndex != messages.length - 1) {
        messages = messages.sublist(0, messages.length - 1);
      }
      final saved = await _saveChatSnapshotIfSessionExists(
        session,
        messages,
        token: activeOperation.storageToken,
      );
      if (!saved) throw StateError('当前对话已不存在。');

      final settingsAfterSave = await widget.storage.loadSettings();
      if (!_isCurrentInnerVoiceOperation(activeOperation) ||
          !settingsAfterSave.showCharacterInnerVoice) {
        await _rollbackInnerVoiceOperation(activeOperation);
      }
    } catch (_) {
      final activeOperation = operation;
      if (activeOperation != null) {
        failed = _isCurrentInnerVoiceOperation(activeOperation);
        await _rollbackInnerVoiceOperation(activeOperation);
      }
    } finally {
      final activeOperation = operation;
      if (activeOperation != null &&
          mounted &&
          identical(
            _innerVoiceOperations[activeOperation.id],
            activeOperation,
          )) {
        setState(() {
          _innerVoiceOperations.remove(activeOperation.id);
          if (failed &&
              _innerVoiceTargetExists(
                messageIndex: messageIndex,
                variantIndex: variantIndex,
                replySnapshot: replySnapshot,
              )) {
            _setInnerVoiceFailure(activeOperation.target);
          }
        });
      }
    }
  }

  bool _innerVoiceTargetExists({
    required int messageIndex,
    required int? variantIndex,
    required String replySnapshot,
  }) {
    if (messageIndex < 0 || messageIndex >= _messages.length) return false;
    final message = _messages[messageIndex];
    if (!message.isAssistant) return false;
    if (variantIndex != null) {
      return variantIndex >= 0 &&
          variantIndex < message.variants.length &&
          message.variants[variantIndex].content == replySnapshot;
    }
    if (message.variants.isNotEmpty) {
      return message.variants.first.content == replySnapshot;
    }
    return message.content == replySnapshot;
  }

  bool _isCurrentInnerVoiceOperation(_InnerVoiceOperation operation) =>
      mounted &&
      operation.revision == _conversationRevision &&
      operation.epoch == widget.storage.datasetEpoch &&
      widget.settings.showCharacterInnerVoice &&
      !operation.cancelled &&
      identical(_innerVoiceOperations[operation.id], operation) &&
      _session?.id == operation.target.sessionId &&
      _innerVoiceTargetExists(
        messageIndex: operation.target.messageIndex,
        variantIndex: operation.target.variantIndex,
        replySnapshot: operation.target.replySnapshot,
      );

  _InnerVoiceDisplayStatus _innerVoiceStatus(
    int messageIndex,
    ChatMessage message,
  ) {
    final sessionId = _session?.id;
    if (sessionId == null) return _InnerVoiceDisplayStatus.idle;
    for (final operation in _innerVoiceOperations.values) {
      if (operation.target.matchesSelected(sessionId, messageIndex, message)) {
        return _InnerVoiceDisplayStatus.generating;
      }
    }
    final failedTarget = _failedInnerVoiceTargets[messageIndex];
    if (failedTarget != null &&
        failedTarget.matchesSelected(sessionId, messageIndex, message)) {
      return _InnerVoiceDisplayStatus.failed;
    }
    return _InnerVoiceDisplayStatus.idle;
  }

  void _setInnerVoiceFailure(_InnerVoiceTarget target) {
    _clearInnerVoiceFailureAt(target.messageIndex);
    _failedInnerVoiceTargets[target.messageIndex] = target;
    _innerVoiceFailureTimers[target.messageIndex] = Timer(
      const Duration(seconds: 4),
      () {
        final current = _failedInnerVoiceTargets[target.messageIndex];
        if (!mounted || current == null || !current.sameIdentity(target)) {
          return;
        }
        setState(() => _clearInnerVoiceFailureAt(target.messageIndex));
      },
    );
  }

  void _clearInnerVoiceFailureAt(int messageIndex) {
    _innerVoiceFailureTimers.remove(messageIndex)?.cancel();
    _failedInnerVoiceTargets.remove(messageIndex);
  }

  void _clearInnerVoiceFailures() {
    for (final timer in _innerVoiceFailureTimers.values) {
      timer.cancel();
    }
    _innerVoiceFailureTimers.clear();
    _failedInnerVoiceTargets.clear();
  }

  Future<void> _rollbackInnerVoiceOperation(
    _InnerVoiceOperation operation, {
    bool updateUi = true,
  }) async {
    if (!operation.applied) return;
    operation.applied = false;
    if (operation.epoch != widget.storage.datasetEpoch) return;
    final generatedInnerVoice = operation.generatedInnerVoice;
    final session = _session;
    if (generatedInnerVoice == null ||
        session == null ||
        session.id != operation.target.sessionId) {
      return;
    }

    var restored = false;
    void restore() {
      restored = _conversation.restoreAssistantInnerVoice(
        messageIndex: operation.target.messageIndex,
        variantIndex: operation.target.variantIndex,
        replySnapshot: operation.target.replySnapshot,
        expectedInnerVoice: generatedInnerVoice,
        previousInnerVoice: operation.previousInnerVoice,
      );
    }

    if (updateUi && mounted) {
      setState(restore);
    } else {
      restore();
    }
    if (!restored) return;

    final messages = List<ChatMessage>.of(_messages);
    try {
      await _saveChatSnapshotIfSessionExists(
        session,
        messages,
        token: operation.storageToken,
      );
    } on Object {
      // The in-memory rollback is still authoritative for later chat saves.
    }
  }

  void _cancelAllInnerVoiceOperations({bool updateUi = true}) {
    _conversationRevision++;
    final operations = _innerVoiceOperations.values.toList();
    for (final operation in operations) {
      operation.cancelled = true;
      operation.cancelToken.cancel();
      unawaited(_rollbackInnerVoiceOperation(operation, updateUi: false));
    }
    if (operations.isEmpty) return;
    if (updateUi && mounted) {
      setState(_innerVoiceOperations.clear);
    } else {
      _innerVoiceOperations.clear();
    }
  }

  bool _isCurrentGeneration(int generationId, String sessionId) =>
      mounted &&
      _generationEpoch == widget.storage.datasetEpoch &&
      generationId == _generationId &&
      _isSending &&
      _session?.id == sessionId;

  Stream<AiResponseDelta> _responseDeltas(
    AiRequest request,
    AiCancelToken token,
  ) async* {
    final gateway = widget.aiService;
    if (gateway is StructuredAiGateway) {
      if (request.stream) {
        await for (final delta
            in (gateway as StructuredAiGateway).streamResponse(
              request,
              cancelToken: token,
            )) {
          yield delta;
        }
      } else {
        final response = await (gateway as StructuredAiGateway).sendResponse(
          request,
          cancelToken: token,
        );
        yield AiResponseDelta(
          contentDelta: response.content,
          reasoningDelta: response.reasoningContent,
          usage: response.usage,
        );
      }
      return;
    }
    AiUsage? usage;
    await for (final text in gateway.streamMessage(
      apiKey: request.apiKey,
      baseUrl: request.baseUrl,
      model: request.model,
      messages: request.messages,
      cancelToken: token,
      onUsage: (value) => usage = value,
    )) {
      yield AiResponseDelta(contentDelta: text);
    }
    if (usage != null) yield AiResponseDelta(usage: usage);
  }

  Future<void> _retryReplySave() async {
    if (!_hasUnsavedReply || !_canMutateConversation) return;
    final session = _currentSession;
    final epoch = widget.storage.datasetEpoch;
    try {
      final saved = await _saveChatSnapshotIfSessionExists(
        session,
        List.of(_messages),
      );
      if (!saved) throw StateError('目标对话不存在');
      if (mounted &&
          epoch == widget.storage.datasetEpoch &&
          _session?.id == session.id) {
        setState(() => _hasUnsavedReply = false);
      }
    } catch (error) {
      if (mounted) context.showSnack('保存失败：$error');
    }
  }

  Completer<void> _beginGenerationOperation() {
    final completion = Completer<void>();
    _generationCompletion = completion;
    return completion;
  }

  void _completeGenerationOperation(Completer<void> completion) {
    if (!completion.isCompleted) completion.complete();
    if (identical(_generationCompletion, completion)) {
      _generationCompletion = null;
    }
  }

  Future<void> _waitForActiveGeneration() async {
    final completion = _generationCompletion;
    if (completion != null) await completion.future;
  }

  int _beginSummaryOperation() => ++_summaryOperationId;

  void _invalidateSummaryOperations() => _summaryOperationId++;

  bool _isCurrentSummaryOperation(int operationId, String sessionId) =>
      mounted &&
      operationId == _summaryOperationId &&
      _session?.id == sessionId;

  Future<void> _regenerateAssistantVariant(int messageIndex) async {
    if (!_canUseNonDestructiveControls) return;
    final epoch = widget.storage.datasetEpoch;
    final sessionId = _session?.id;
    await _waitForActiveGeneration();
    if (!mounted ||
        !_isCurrentConversation(epoch, sessionId) ||
        !_canMutateConversation ||
        !_conversation.canRegenerateAssistantAt(messageIndex)) {
      return;
    }
    _invalidateSummaryOperations();
    final endpoint = await _reloadEndpoint();
    if (endpoint == null ||
        !_canMutateConversation ||
        !_isCurrentConversation(epoch, sessionId)) {
      return;
    }
    final generationCompletion = _beginGenerationOperation();
    setState(() {
      _isSending = true;
      _variantGenerationIndex = messageIndex;
    });
    try {
      await _requestAssistantReply(endpoint, variantAt: messageIndex);
    } finally {
      _completeGenerationOperation(generationCompletion);
    }
  }

  Future<void> _openSessionList() async {
    if (_isLoading || _isOpeningSessionList) return;
    unawaited(_speech.stop());
    if (_session != null) _stateService.cancelStateRefresh(_session!.id);
    final epoch = widget.storage.datasetEpoch;
    setState(() => _isOpeningSessionList = true);
    try {
      _cancelActiveSummary();
      final beforeId = _session?.id;
      final selected = await Navigator.of(context).push<ChatSession>(
        MaterialPageRoute(
          builder: (_) => ChatSessionListScreen(
            storage: widget.storage,
            character: _character,
            selectedSessionId: _session?.id,
            deletionDisabled: _isSending || _hasUnsavedReply,
          ),
        ),
      );
      if (!mounted || epoch != widget.storage.datasetEpoch) return;

      if (selected != null && selected.id != beforeId) {
        await _waitForActiveGeneration();
        if (!mounted || epoch != widget.storage.datasetEpoch) return;
      }

      final sessions = await widget.storage.loadChatSessions(_character.id);
      ChatSession? target;
      if (selected != null) {
        target = sessions
            .where((session) => session.id == selected.id)
            .firstOrNull;
      }
      target ??= sessions
          .where((session) => session.id == beforeId)
          .firstOrNull;
      target ??= await widget.storage.getOrCreateRecentChatSession(
        _character.id,
      );
      if (!mounted || epoch != widget.storage.datasetEpoch) return;

      if (_hasUnsavedReply && target.id != beforeId) {
        context.showSnack('当前回复未保存，请先重试保存后再切换对话');
        return;
      }

      if (target.id != beforeId) {
        _cancelAllInnerVoiceOperations();
        _clearInnerVoiceFailures();
        _invalidateSummaryOperations();
        _session = target;
        await _load();
        return;
      }
      setState(() => _session = target);
    } finally {
      if (mounted) setState(() => _isOpeningSessionList = false);
    }
  }

  Future<void> _openMemoryManager() async {
    if (!_canUseNonDestructiveControls) return;
    final session = _session;
    if (session == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemoryManagerScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          character: _character,
          session: session,
          selectedEndpointId: _selectedEndpointId,
        ),
      ),
    );
    try {
      final refreshed = (await widget.storage.loadCharacters())
          .where((character) => character.id == _character.id)
          .firstOrNull;
      if (refreshed != null && mounted) {
        setState(() => _character = refreshed);
      }
    } catch (_) {
      // The chat remains usable with the in-memory character if refresh fails.
    }
  }

  Future<void> _addMessageToMemory(ChatMessage message) async {
    if (!_canUseNonDestructiveControls) return;
    final session = _session;
    if (session == null) return;
    final scope = await showModalBottomSheet<MemoryScope>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(context.t('长期记忆')),
              onTap: () => Navigator.pop(context, MemoryScope.character),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: Text(context.t('当前对话记忆')),
              onTap: () => Navigator.pop(context, MemoryScope.session),
            ),
          ],
        ),
      ),
    );
    if (scope == null || !mounted) return;
    final entry = await Navigator.of(context).push(
      MaterialPageRoute<CharacterMemoryEntry>(
        builder: (_) => MemoryEditScreen(
          character: _character,
          session: session,
          initialContent: message.effectiveContent,
          initialScope: scope,
          allowScopeChange: false,
        ),
      ),
    );
    if (entry == null) return;
    try {
      await widget.storage.saveCharacterMemory(entry);
      if (mounted) context.showSnack('记忆已保存');
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    }
  }

  Future<void> _selectAssistantVariant(
    int messageIndex,
    int variantIndex,
  ) async {
    _stopStoryEffects();
    if (!_canUseNonDestructiveControls) return;
    final epoch = widget.storage.datasetEpoch;
    final sessionId = _session?.id;
    await _waitForActiveGeneration();
    if (!mounted ||
        !_isCurrentConversation(epoch, sessionId) ||
        !_canMutateConversation ||
        messageIndex < 0 ||
        messageIndex >= _messages.length) {
      return;
    }
    final message = _messages[messageIndex];
    if (variantIndex == message.selectedVariantIndex) {
      return;
    }
    if (_conversation.hasMessagesAfter(messageIndex)) {
      final confirmed = await showConfirmDialog(
        context: context,
        title: '切换候选回复',
        content: context.t('切换此候选将删除它之后的消息，并可能清空历史总结，是否继续？'),
        confirmLabel: '继续',
      );
      if (!confirmed || !_isCurrentConversation(epoch, sessionId)) return;
    }
    if (!_conversation.selectAssistantVariant(messageIndex, variantIndex)) {
      return;
    }
    if (_conversation.hasMessagesAfter(messageIndex)) {
      _conversation.truncateAfter(messageIndex);
    }
    setState(() {
      _searchResults = findChatSearchResults(
        _messages.map((item) => item.effectiveContent),
        _searchQuery,
      );
      _activeSearchResult = _searchResults.isEmpty
          ? 0
          : _activeSearchResult.clamp(0, _searchResults.length - 1).toInt();
    });
    await _saveCurrentChat();
    if (!_isCurrentConversation(epoch, sessionId)) return;
    await _saveCurrentSummary();
  }

  Future<void> _retryLastUserMessage() async {
    if (!_canMutateConversation ||
        _messages.isEmpty ||
        !_messages.last.isUser) {
      return;
    }
    _invalidateSummaryOperations();
    final endpoint = await _reloadEndpoint();
    if (endpoint == null || !_canMutateConversation) return;
    final generationCompletion = _beginGenerationOperation();
    setState(() => _isSending = true);
    _scrollToEnd();
    try {
      await _requestAssistantReply(endpoint);
    } finally {
      _completeGenerationOperation(generationCompletion);
    }
  }

  Future<void> _editLastUserMessageAndResend() async {
    _stopStoryEffects();
    if (!_canMutateConversation) return;
    final epoch = widget.storage.datasetEpoch;
    final entrySessionId = _session?.id;
    _invalidateSummaryOperations();
    final index = _conversation.lastUserMessageIndex;
    if (index == -1) {
      context.showSnack('没有可编辑的用户消息。');
      return;
    }

    final edited = await showTextInputDialog(
      context: context,
      title: '编辑并重发',
      initialText: _messages[index].content,
      label: '输入消息',
      confirmLabel: '重新生成',
      minLines: 3,
      maxLines: 8,
    );
    if (!_isCurrentConversation(epoch, entrySessionId)) return;
    if (edited == null || edited.isEmpty) return;
    if (!_canMutateConversation) return;

    final endpoint = await _reloadEndpoint();
    if (endpoint == null ||
        !_canMutateConversation ||
        !_isCurrentConversation(epoch, entrySessionId)) {
      return;
    }

    final sessionId = _currentSession.id;
    final previousMessages = [..._messages];
    final generationCompletion = _beginGenerationOperation();
    try {
      _cancelAllInnerVoiceOperations();
      setState(() {
        _conversation.editUserMessageAndTruncate(index, edited, DateTime.now());
        _isSending = true;
      });
      try {
        await _saveCurrentChat();
      } catch (error) {
        if (!mounted || !_isCurrentConversation(epoch, sessionId)) return;
        setState(() {
          _conversation.replaceMessages(previousMessages);
          _isSending = false;
        });
        context.showSnack(error.toString());
        return;
      }
      if (!_isCurrentConversation(epoch, sessionId) || !_isSending) return;
      _scrollToEnd();
      await _requestAssistantReply(endpoint);
    } finally {
      _completeGenerationOperation(generationCompletion);
    }
  }

  void _stopGeneration() {
    _cancelAllInnerVoiceOperations();
    unawaited(_cancelActiveGeneration());
  }

  void _cancelActiveSummary() {
    if (!_isSummarizing) return;
    _summaryCancelToken?.cancel();
    _summaryCancelToken = null;
    _invalidateSummaryOperations();
    if (mounted) setState(() => _isSummarizing = false);
  }

  Future<void> _cancelActiveGeneration({
    bool showMessage = true,
    bool persistPartialReply = true,
  }) {
    final active = _generationCancellationFuture;
    if (active != null) return active;
    if (!_isSending) return Future<void>.value();

    final generationCompletion = _generationCompletion;
    late final Future<void> owned;
    owned =
        _performGenerationCancellation(
          showMessage: showMessage,
          persistPartialReply: persistPartialReply,
        ).whenComplete(() {
          if (generationCompletion != null) {
            _completeGenerationOperation(generationCompletion);
          }
          if (!identical(_generationCancellationFuture, owned)) return;
          _generationCancellationFuture = null;
          if (mounted) setState(() => _isCancellingGeneration = false);
        });
    _generationCancellationFuture = owned;
    return owned;
  }

  Future<void> _performGenerationCancellation({
    required bool showMessage,
    required bool persistPartialReply,
  }) async {
    final epoch = widget.storage.datasetEpoch;
    _cancelAllInnerVoiceOperations();
    _streamBuffer?.flush();
    _finalizeDraft?.call('interrupted');
    _cancelToken?.cancel();
    _cancelToken = null;
    _generationId++;
    final cancellationId = _generationId;
    _invalidateSummaryOperations();
    final session = _currentSession;
    setState(() {
      _conversation.dropEmptyAssistantTail();
      _variantGenerationIndex = null;
      _isSending = false;
      _isSummarizing = false;
      _isCancellingGeneration = true;
    });
    final messages = List<ChatMessage>.of(_messages);
    var saveFailed = false;
    if (persistPartialReply) {
      try {
        final saved = await _saveChatSnapshotIfSessionExists(
          session,
          messages,
          token: _generationStorageToken,
        );
        if (!saved) throw StateError('目标对话已更新');
      } catch (error) {
        saveFailed = true;
        if (mounted &&
            _isCurrentConversation(epoch, session.id) &&
            cancellationId == _generationId) {
          setState(() => _hasUnsavedReply = true);
          context.showSnack(error.toString());
        }
      }
    }
    if (showMessage &&
        mounted &&
        _isCurrentConversation(epoch, session.id) &&
        cancellationId == _generationId &&
        !saveFailed) {
      context.showSnack('已停止生成');
    }
  }

  Future<void> _summarize() async {
    if (_messages.isEmpty) {
      context.showSnack('当前没有可总结的聊天记录。');
      return;
    }
    if (!_canMutateConversation) return;

    final session = _currentSession;
    final sessionId = session.id;
    final messages = List<ChatMessage>.of(_conversation.chatMessagesOnly);
    final operationId = _beginSummaryOperation();
    final cancelToken = AiCancelToken();
    _summaryCancelToken = cancelToken;
    var showSummaryDialog = false;
    setState(() => _isSummarizing = true);

    final endpoint = await _reloadEndpoint();
    if (endpoint == null ||
        !_isCurrentSummaryOperation(operationId, sessionId)) {
      if (identical(_summaryCancelToken, cancelToken)) {
        _summaryCancelToken = null;
      }
      if (_isCurrentSummaryOperation(operationId, sessionId)) {
        setState(() => _isSummarizing = false);
      }
      return;
    }

    try {
      final storageToken = widget.storage.usesSessionStorage
          ? await widget.storage.captureSessionToken(session)
          : null;
      final prompt = PromptBuilder.buildSummaryPrompt(
        messages,
        useCustomItems: widget.settings.useCustomChatSummaryItems,
        customItems: widget.settings.customChatSummaryItems,
      );
      final summaryText = await widget.aiService.sendMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: [
          {'role': 'system', 'content': '你负责总结聊天记录，并只输出总结内容。'},
          {'role': 'user', 'content': prompt},
        ],
        temperature: 0.2,
        cancelToken: cancelToken,
        onUsage: (usage) => unawaited(
          _recordUsage(
            requestType: 'characterSummary',
            model: endpoint.model,
            usage: usage,
            messages: [
              {'role': 'system', 'content': '你负责总结聊天记录，并只输出总结内容。'},
              {'role': 'user', 'content': prompt},
            ],
            summaryUpdated: true,
          ),
        ),
      );

      if (!_isCurrentSummaryOperation(operationId, sessionId)) return;
      final nextSummary = ChatSummary(
        characterId: _character.id,
        sessionId: sessionId,
        summary: PromptBuilder.limitSummary(summaryText, 1500),
        updatedAt: DateTime.now(),
        summarizedMessageCount: messages.length,
      );
      await _saveSummary(nextSummary, token: storageToken);

      if (!_isCurrentSummaryOperation(operationId, sessionId)) return;
      setState(() => _conversation.setSummary(nextSummary));
      showSummaryDialog = true;
    } catch (error) {
      if (mounted && _isCurrentSummaryOperation(operationId, sessionId)) {
        context.showSnack(error.toString());
      }
    } finally {
      if (identical(_summaryCancelToken, cancelToken)) {
        _summaryCancelToken = null;
      }
      if (_isCurrentSummaryOperation(operationId, sessionId)) {
        setState(() => _isSummarizing = false);
        if (showSummaryDialog) unawaited(_showSummaryDialog());
      }
    }
  }

  Future<void> _clearChat() async {
    _stopStoryEffects();
    if (!_canMutateConversation) return;
    final epoch = widget.storage.datasetEpoch;
    final sessionId = _session?.id;
    final shouldClear = await showConfirmDialog(
      context: context,
      title: '清空聊天',
      content: context.t('确定清空当前对话的聊天记录吗？历史总结不会被删除。'),
      confirmLabel: '清空',
    );

    if (!shouldClear ||
        !_canMutateConversation ||
        !_isCurrentConversation(epoch, sessionId)) {
      return;
    }

    setState(() => _isClearing = true);
    _cancelAllInnerVoiceOperations();
    _invalidateSummaryOperations();
    _clearInnerVoiceFailures();
    final session = _currentSession;
    ChatSummary next;
    try {
      next = await _enqueueChatSave(() async {
        if (epoch != widget.storage.datasetEpoch) throw StateError('数据集已更新');
        if (widget.storage.usesSessionStorage) {
          return widget.storage.clearChatPreservingSummary(session);
        }
        final summary = summaryAfterChatClear(_summary, DateTime.now());
        await widget.storage.saveSummary(summary);
        await widget.storage.clearChat(_character.id);
        return summary;
      });
    } catch (error) {
      if (mounted) context.showSnack('清空保存失败：$error');
      return;
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
    if (!mounted ||
        epoch != widget.storage.datasetEpoch ||
        _session?.id != session.id) {
      return;
    }
    setState(() {
      _conversation.clearMessages();
      _conversation.setSummary(next);
      _hasUnsavedReply = false;
      _searchQuery = '';
      _searchResults = [];
      _activeSearchResult = 0;
    });
    context.showSnack('聊天记录已清空');
  }

  Future<void> _exportHistory() async {
    if (_messages.every((message) => message.effectiveContent.trim().isEmpty)) {
      context.showSnack('当前没有可导出的聊天记录');
      return;
    }
    final userName = context.t('我');
    final systemName = context.t('系统');
    final dialogTitle = context.t('保存聊天记录');
    try {
      final saved = await exportChatText(
        dialogTitle: dialogTitle,
        title: '${_character.name} - ${_currentSession.title}',
        entries: [
          for (final message in _messages)
            (
              time: message.effectiveTime,
              speaker: message.isUser
                  ? userName
                  : message.isAssistant
                  ? _character.name
                  : systemName,
              content: message.effectiveContent,
            ),
        ],
      );
      if (saved && mounted) context.showSnack('聊天记录已导出');
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    }
  }

  Future<void> _showSearchDialog() async {
    if (_messages.isEmpty) {
      context.showSnack('当前没有可搜索的聊天记录');
      return;
    }
    await showChatSearchDialog(
      context: context,
      contents: _messages.map((message) => message.effectiveContent).toList(),
      initialQuery: _searchQuery,
      initialActiveIndex: _activeSearchResult,
      onChanged: (update) {
        if (!mounted) return;
        setState(() {
          _searchQuery = update.query;
          _searchResults = update.results;
          _activeSearchResult = update.activeIndex;
        });
        if (update.results.isNotEmpty) {
          _scrollToSearchResult(update.results[update.activeIndex]);
        }
      },
    );
  }

  List<Map<String, String>> _buildChatRequestMessages(
    UserProfile userProfile, {
    required String memoryPrompt,
    required List<ChatMessage> messages,
  }) {
    return PromptBuilder.buildChatRequestMessages(
      character: _character,
      userProfile: userProfile,
      memoryPrompt: memoryPrompt,
      historySummary: _summary.summary,
      summarizedMessageCount: _summary.summarizedMessageCount,
      messages: messages,
      useFullContext: _character.useFullChatContext,
    );
  }

  Future<bool> _updateRollingSummary(
    AiEndpointConfig endpoint,
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    if (_character.useFullChatContext) return false;
    final sessionId = _currentSession.id;
    final messages = List<ChatMessage>.of(_messages);
    final summary = _summary;
    final operationId = _beginSummaryOperation();

    setState(() => _isSummarizing = true);
    try {
      final storageToken = widget.storage.usesSessionStorage
          ? await widget.storage.captureSessionToken(_currentSession)
          : null;
      final nextSummary = await updateChatSummary(
        widget.aiService,
        characterId: _character.id,
        current: summary,
        messages: messages,
        summaryLimit: _character.chatSummaryMessageLimit,
        settings: widget.settings,
        endpoint: endpoint,
        cancelToken: cancelToken,
        onUsage: (usage, messages) => unawaited(
          _recordUsage(
            requestType: 'characterSummary',
            model: endpoint.model,
            usage: usage,
            messages: messages,
            summaryUpdated: true,
          ),
        ),
      );
      if (nextSummary == null) return false;
      if (!_isCurrentGeneration(generationId, sessionId) ||
          !_isCurrentSummaryOperation(operationId, sessionId)) {
        return false;
      }
      await _saveSummary(nextSummary, token: storageToken);
      if (!_isCurrentGeneration(generationId, sessionId) ||
          !_isCurrentSummaryOperation(operationId, sessionId)) {
        return true;
      }
      setState(() => _conversation.setSummary(nextSummary));
      return true;
    } finally {
      if (_isCurrentSummaryOperation(operationId, sessionId)) {
        setState(() => _isSummarizing = false);
      }
    }
  }

  Future<void> _showSummaryDialog() async {
    if (_isLoading || _isSending || _isSummarizing) return;
    final sessionId = _currentSession.id;
    final initialSummary = _summary;
    final messageCount = _conversation.chatMessagesOnly.length;
    final text = initialSummary.summary.trim();
    final controller = TextEditingController(text: text);
    final hasSummary = text.isNotEmpty;

    bool closeIfSessionChanged(NavigatorState navigator) {
      if (!mounted) return true;
      if (_session?.id == sessionId) return false;
      navigator.pop();
      context.showSnack('当前对话已切换，请重新打开历史总结');
      return true;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('历史总结')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              hintText: hasSummary ? null : context.t('可以直接填写历史总结'),
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: hasSummary
                      ? () async {
                          final navigator = Navigator.of(dialogContext);
                          if (closeIfSessionChanged(navigator)) return;
                          final confirmed = await showConfirmDialog(
                            context: context,
                            title: '删除历史总结',
                            content: context.t('确定删除当前角色的历史总结吗？'),
                            confirmLabel: '删除',
                          );
                          if (!confirmed || !mounted) return;
                          if (closeIfSessionChanged(navigator)) return;
                          final nextSummary = ChatSummary.empty(
                            _character.id,
                            sessionId,
                          );
                          await _saveSummary(nextSummary);
                          if (!mounted) return;
                          if (closeIfSessionChanged(navigator)) return;
                          setState(() => _conversation.setSummary(nextSummary));
                          navigator.pop();
                          context.showSnack('历史总结已删除');
                        }
                      : null,
                  child: Text(context.t('删除历史总结')),
                ),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(dialogContext);
                    if (closeIfSessionChanged(navigator)) return;
                    final nextText = controller.text.trim();
                    if (nextText.isEmpty) {
                      context.showSnack('总结内容不能为空，想删除请点删除历史总结');
                      return;
                    }
                    if (nextText == text) {
                      navigator.pop();
                      return;
                    }
                    final confirmed = await showConfirmDialog(
                      context: context,
                      title: '保存历史总结',
                      content: context.t('确定保存对历史总结的改动吗？'),
                      confirmLabel: '保存',
                    );
                    if (!confirmed || !mounted) return;
                    if (closeIfSessionChanged(navigator)) return;
                    final nextSummary = ChatSummary(
                      characterId: _character.id,
                      sessionId: sessionId,
                      summary: nextText,
                      updatedAt: DateTime.now(),
                      summarizedMessageCount:
                          initialSummary.summarizedMessageCount == 0
                          ? manualSummaryBoundary(messageCount: messageCount)
                          : initialSummary.summarizedMessageCount,
                    );
                    await _saveSummary(nextSummary);
                    if (!mounted) return;
                    if (closeIfSessionChanged(navigator)) return;
                    setState(() => _conversation.setSummary(nextSummary));
                    navigator.pop();
                    context.showSnack('历史总结已保存');
                  },
                  child: Text(context.t('保存')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(context.t('关闭')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showChatSettings() async {
    if (!_canUseNonDestructiveControls) return;
    _stopStoryEffects();
    var draft = _character;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void preview(AppCharacter character) {
            draft = character;
            setSheetState(() {});
            setState(() => _character = character);
          }

          void apply(AppCharacter character) {
            final saved = character.copyWith(updatedAt: DateTime.now());
            preview(saved);
            unawaited(
              widget.storage.saveCharacter(saved).onError((error, _) {
                if (mounted) this.context.showSnack(error.toString());
              }),
            );
          }

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              shrinkWrap: true,
              children: [
                Text(
                  context.t('聊天设置'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(context.t('聊天条数：${_messages.length} 条')),
                  subtitle: Text(_speedHint(_messages.length)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.memory),
                  title: Text(context.t('当前模型')),
                  subtitle: Text(
                    _apiConfig.endpointById(_selectedEndpointId)?.name ??
                        context.t('未配置 API'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _apiConfig.enabledEndpoints.isEmpty
                      ? null
                      : () async {
                          final endpointId = await showEndpointPicker(
                            context: context,
                            endpoints: _apiConfig.enabledEndpoints,
                            selectedId: _selectedEndpointId,
                          );
                          if (endpointId == null || !mounted) return;
                          final next = draft.copyWith(
                            defaultEndpointId: endpointId,
                          );
                          setState(() => _selectedEndpointId = endpointId);
                          apply(next);
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_history),
                  title: Text(context.t('上下文模式')),
                  subtitle: Text(_contextModeSubtitle(draft)),
                ),
                if (_session?.isStoryBranch == true)
                  SwitchListTile(
                    title: Text(
                      context.isEnglish
                          ? 'Use shared character memories in this branch'
                          : '本分支使用角色共享长期记忆',
                    ),
                    subtitle: Text(
                      context.isEnglish
                          ? 'May introduce facts from other routes. Source summaries and session memories remain excluded.'
                          : '可能引入其他路线的信息；来源总结和来源对话记忆仍不继承。',
                    ),
                    value: _session!.allowSharedCharacterMemories,
                    onChanged: (value) async {
                      final session = _currentSession;
                      if (value &&
                          !await showConfirmDialog(
                            context: context,
                            title: context.isEnglish
                                ? 'Enable shared memories?'
                                : '启用共享长期记忆？',
                            content: context.isEnglish
                                ? 'This can expose facts learned after the checkpoint.'
                                : '这可能带入存档时间之后才获得的信息。',
                          )) {
                        return;
                      }
                      if (!mounted || _session?.id != session.id) return;
                      final updated = session.copyWith(
                        allowSharedCharacterMemories: value,
                      );
                      await widget.storage.saveChatSession(updated);
                      if (mounted) {
                        setState(() => _session = updated);
                        setSheetState(() {});
                      }
                    },
                  ),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.all_inclusive),
                      label: Text(context.t('全部上下文')),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.compress),
                      label: Text(context.t('总结 + 最近消息')),
                    ),
                  ],
                  selected: {draft.useFullChatContext},
                  onSelectionChanged: (values) {
                    final useFullContext = values.first;
                    final next = draft.copyWith(
                      useFullChatContext: useFullContext,
                    );
                    apply(next);
                  },
                ),
                if (!draft.useFullChatContext) ...[
                  const SizedBox(height: 8),
                  SettingSlider(
                    label: '自动总结阈值',
                    value: draft.chatSummaryMessageLimit.toDouble(),
                    min: AppCharacter.minChatSummaryMessageLimit.toDouble(),
                    max: AppCharacter.maxChatSummaryMessageLimit.toDouble(),
                    divisions:
                        AppCharacter.maxChatSummaryMessageLimit -
                        AppCharacter.minChatSummaryMessageLimit,
                    display: context.isEnglish
                        ? '${draft.chatSummaryMessageLimit} msgs'
                        : '${draft.chatSummaryMessageLimit} 条',
                    onChanged: (value) {
                      preview(
                        draft.copyWith(chatSummaryMessageLimit: value.round()),
                      );
                    },
                    onChangeEnd: (value) {
                      apply(
                        draft.copyWith(chatSummaryMessageLimit: value.round()),
                      );
                    },
                  ),
                ],
                const Divider(),
                SettingSlider.opacity(
                  key: const ValueKey('chat-background-transparency-setting'),
                  label: '背景图透明度',
                  opacity: draft.backgroundImageOpacity,
                  onChanged: (opacity) {
                    preview(draft.copyWith(backgroundImageOpacity: opacity));
                  },
                  onChangeEnd: (opacity) {
                    apply(draft.copyWith(backgroundImageOpacity: opacity));
                  },
                ),
                SettingSlider(
                  label: '背景图模糊度',
                  value: draft.backgroundBlur,
                  min: 0,
                  max: 12,
                  divisions: 12,
                  display: draft.backgroundBlur.toStringAsFixed(0),
                  onChanged: (value) {
                    preview(draft.copyWith(backgroundBlur: value));
                  },
                  onChangeEnd: (value) {
                    apply(draft.copyWith(backgroundBlur: value));
                  },
                ),
                SettingSlider.transparency(
                  key: const ValueKey('chat-top-bar-transparency-setting'),
                  label: '顶部状态栏透明度',
                  opacity: draft.topBarOpacity,
                  onChanged: (opacity) {
                    preview(draft.copyWith(topBarOpacity: opacity));
                  },
                  onChangeEnd: (opacity) {
                    apply(draft.copyWith(topBarOpacity: opacity));
                  },
                ),
                SettingSlider.transparency(
                  key: const ValueKey('chat-input-opacity-setting'),
                  label: '输入框透明度',
                  opacity: draft.inputOpacity,
                  onChanged: (opacity) {
                    preview(draft.copyWith(inputOpacity: opacity));
                  },
                  onChangeEnd: (opacity) {
                    apply(draft.copyWith(inputOpacity: opacity));
                  },
                ),
                ChatBubblePresetSelectionTile(
                  key: const ValueKey('chat-role-bubble-preset-setting'),
                  title: '角色气泡',
                  presetId: draft.roleBubblePresetId,
                  isUser: false,
                  onChanged: (value) {
                    final next = draft.copyWith(
                      roleBubblePresetId: value,
                      clearRoleBubbleOpacity: true,
                    );
                    apply(next);
                  },
                ),
                SettingSlider.transparency(
                  key: const ValueKey('chat-role-bubble-transparency-setting'),
                  label: '角色气泡透明度',
                  opacity: _roleBubbleAppearance.opacity,
                  onChanged: (opacity) {
                    preview(draft.copyWith(roleBubbleOpacity: opacity));
                  },
                  onChangeEnd: (opacity) {
                    apply(draft.copyWith(roleBubbleOpacity: opacity));
                  },
                ),
                ChatBubblePresetSelectionTile(
                  key: const ValueKey('chat-user-bubble-preset-setting'),
                  title: '我的气泡',
                  presetId: draft.userBubblePresetId,
                  isUser: true,
                  onChanged: (value) {
                    final next = draft.copyWith(
                      userBubblePresetId: value,
                      clearUserBubbleOpacity: true,
                    );
                    apply(next);
                  },
                ),
                SettingSlider.transparency(
                  key: const ValueKey('chat-user-bubble-transparency-setting'),
                  label: '我的气泡透明度',
                  opacity: _userBubbleAppearance.opacity,
                  onChanged: (opacity) {
                    preview(draft.copyWith(userBubbleOpacity: opacity));
                  },
                  onChangeEnd: (opacity) {
                    apply(draft.copyWith(userBubbleOpacity: opacity));
                  },
                ),
                const Divider(),
                ListTile(
                  key: const ValueKey('chat-export-history-setting'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: Text(context.t('导出聊天记录')),
                  subtitle: Text(context.t('导出为 UTF-8 TXT')),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_exportHistory());
                  },
                ),
                const Divider(),
                ListTile(
                  key: const ValueKey('chat-clear-history-setting'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_sweep_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    context.t('清空聊天记录'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(context.t('历史总结不会被删除')),
                  onTap: _canMutateConversation
                      ? () {
                          Navigator.of(context).pop();
                          unawaited(_clearChat());
                        }
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _contextModeSubtitle(AppCharacter character) {
    final count = _estimatedRequestMessageCount(character);
    if (character.useFullChatContext) {
      return context.isEnglish
          ? 'Send all chat messages this time: $count'
          : '本次请求携带全部聊天消息：$count 条';
    }
    return context.isEnglish
        ? 'Summary + latest $count messages, auto summary after ${character.chatSummaryMessageLimit}'
        : '历史总结 + 最近 $count 条，超过 ${character.chatSummaryMessageLimit} 条自动总结';
  }

  int _estimatedRequestMessageCount(AppCharacter character) {
    final count = _conversation.chatMessagesOnly.length;
    if (character.useFullChatContext) return count;
    final startIndex = PromptBuilder.recentContextStartIndex(
      messageCount: count,
      summaryLimit: character.chatSummaryMessageLimit,
    );
    return count - startIndex;
  }

  String _speedHint(int count) {
    if (count < 100) {
      return context.t('速度判断：正常');
    }
    if (count < 200) {
      return context.t('速度判断：聊天变长，模型可能会慢一点');
    }
    return context.t('速度判断：聊天很多，模型读取上下文可能明显变慢');
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.effectiveContent));
    if (!mounted) return;
    context.showSnack('已复制消息');
  }

  Future<void> _deleteMessage(int index) async {
    _stopStoryEffects();
    if (!_canMutateConversation || index < 0 || index >= _messages.length) {
      return;
    }
    final epoch = widget.storage.datasetEpoch;
    final sessionId = _session?.id;
    final message = _messages[index];
    final deletingVariant = message.isAssistant && message.variantCount > 1;
    final hasFollowingMessages = _conversation.hasMessagesAfter(index);
    final confirmed = await showConfirmDialog(
      context: context,
      title: context.t(deletingVariant ? '删除候选回复' : '删除消息'),
      content: context.t(
        deletingVariant && hasFollowingMessages
            ? '删除当前候选后将自动切换到其他候选，并删除它之后的消息，同时可能清空历史总结。是否继续？'
            : deletingVariant
            ? '确定删除当前候选回复吗？'
            : '确定删除这条消息吗？',
      ),
      confirmLabel: '删除',
    );
    if (!confirmed ||
        !_canMutateConversation ||
        !_isCurrentConversation(epoch, sessionId)) {
      return;
    }

    _cancelAllInnerVoiceOperations();
    _clearInnerVoiceFailures();
    final deletion = _conversation.deleteAt(index);
    if (deletion == ChatMessageDeletion.ignored) return;
    final truncatedTimeline = deletingVariant && hasFollowingMessages;
    if (truncatedTimeline) {
      _conversation.truncateAfter(index);
    }
    if (truncatedTimeline ||
        deletion == ChatMessageDeletion.summaryInvalidated) {
      await _saveCurrentSummary();
      if (!_isCurrentConversation(epoch, sessionId)) return;
    }
    setState(() {
      _searchResults = findChatSearchResults(
        _messages.map((message) => message.effectiveContent),
        _searchQuery,
      );
      _activeSearchResult = _searchResults.isEmpty
          ? 0
          : _activeSearchResult.clamp(0, _searchResults.length - 1);
    });
    await _saveCurrentChat();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _scrollToSearchResult(int messageIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || _messages.isEmpty) return;
      final listIndex =
          _messages.length - 1 - messageIndex + (_isSending ? 1 : 0);
      final target = (listIndex * 140.0)
          .clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          )
          .toDouble();
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.reverse) {
      _showToolsTemporarily();
    }
    return false;
  }

  void _showToolsTemporarily() {
    _toolBarTimer?.cancel();
    if (!_showToolBar) {
      setState(() => _showToolBar = true);
    }
    _toolBarTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isSummarizing) {
        return;
      }
      setState(() => _showToolBar = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_hasUnsavedReply,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _hasUnsavedReply) {
          context.showSnack('回复尚未保存，请先重试保存或复制正文');
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          key: const ValueKey('character-chat-app-bar'),
          backgroundColor: Theme.of(context).colorScheme.surface.withValues(
            alpha: _character.topBarOpacity.clamp(0, 1).toDouble(),
          ),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: appSystemOverlayStyle(context),
          title: InkWell(
            onTap: _isLoading || _isOpeningSessionList
                ? null
                : _openSessionList,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _character.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_session != null)
                  Text(
                    _session!.title,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: context.t('对话管理'),
              onPressed: _isLoading || _isOpeningSessionList
                  ? null
                  : _openSessionList,
              icon: const Icon(Icons.forum_outlined),
            ),
            IconButton(
              tooltip: context.t('搜索聊天'),
              onPressed: _showSearchDialog,
              icon: const Icon(Icons.search),
            ),
            PopupMenuButton<String>(
              tooltip: context.t('更多'),
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'memory') {
                  unawaited(_openMemoryManager());
                } else if (value == 'checkpoints') {
                  unawaited(_openCheckpoints());
                } else if (value == 'collection') {
                  unawaited(_openCollection());
                } else if (value == 'summary' && !_hasActiveChatOperation) {
                  unawaited(_showSummaryDialog());
                } else if (value == 'settings' &&
                    _canUseNonDestructiveControls) {
                  unawaited(_showChatSettings());
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(
                  value: 'summary',
                  enabled: !_hasActiveChatOperation,
                  child: Text(c.t('查看历史总结')),
                ),
                PopupMenuItem(
                  value: 'settings',
                  enabled: _canUseNonDestructiveControls,
                  child: Text(c.t('聊天设置')),
                ),
                PopupMenuItem(
                  value: 'memory',
                  enabled: _canUseNonDestructiveControls,
                  child: Text(c.t('记忆与世界书')),
                ),
                PopupMenuItem(value: 'checkpoints', child: Text(c.t('剧情存档'))),
                PopupMenuItem(value: 'collection', child: Text(c.t('回忆册'))),
              ],
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return PageStatusView.error(message: _loadError!, onRetry: _load);
    }

    final showTopBar = _showToolBar || _isSummarizing;
    return MediaBackground(
      imagePath: _character.backgroundImage,
      region: _character.backgroundImageRegion,
      opacity: _character.backgroundImageOpacity,
      blur: _character.backgroundBlur,
      overlayOpacity: 0.18,
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.only(top: _topInset(context)),
          child: Column(
            children: [
              ChatHeaderPanel(
                maxHeight:
                    (constraints.maxHeight - _topInset(context)).clamp(
                      0,
                      double.infinity,
                    ) *
                    .35,
                tools: showTopBar
                    ? _TopBar(
                        endpoints: _apiConfig.enabledEndpoints,
                        selectedEndpointId: _selectedEndpointId,
                        isSummarizing: _isSummarizing,
                        canSummarize:
                            !_isSending &&
                            !_isSummarizing &&
                            _messages.isNotEmpty,
                        hasBackground: _character.backgroundImage
                            .trim()
                            .isNotEmpty,
                        onEndpointChanged: (endpointId) {
                          if (endpointId != null) {
                            setState(() => _selectedEndpointId = endpointId);
                            _showToolsTemporarily();
                          }
                        },
                        onSummarize: () {
                          _showToolsTemporarily();
                          unawaited(_summarize());
                        },
                      )
                    : null,
                stateCard:
                    widget.settings.showCharacterStateCard &&
                        _characterState != null
                    ? CharacterStateCard(
                        key: ValueKey(_session?.id),
                        view: _characterState!,
                        busy: _stateBusy,
                        english: context.isEnglish,
                        onEdit: (edit) async {
                          final s = _currentSession;
                          await _stateService.editState(
                            s.id,
                            _character.id,
                            _messages,
                            edit,
                          );
                          await _reloadState();
                        },
                        onRefresh: () => _refreshState(),
                        onReset: () async {
                          await _stateService.resetState(
                            _currentSession.id,
                            _character.id,
                            _messages,
                          );
                          await _reloadState();
                        },
                      )
                    : null,
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: _buildMessages(),
                ),
              ),
              ChatInputComposer(
                onInspiration: _openReplyInspiration,
                controller: _inputController,
                focusNode: _inputFocusNode,
                isGenerating: _isSending,
                enabled: _canUseNonDestructiveControls,
                hasBackground: _character.backgroundImage.trim().isNotEmpty,
                inputOpacity: _character.inputOpacity,
                onSend: _send,
                onStop: _stopGeneration,
                onRetry: _messages.isNotEmpty && _messages.last.isUser
                    ? _retryLastUserMessage
                    : null,
                onEditResend: _conversation.lastUserMessageIndex == -1
                    ? null
                    : _editLastUserMessageAndResend,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(child: Text(context.t('当前还没有聊天记录。')));
    }

    final highlightedIndex = _searchResults.isEmpty
        ? -1
        : _searchResults[_activeSearchResult
              .clamp(0, _searchResults.length - 1)
              .toInt()];

    final showTyping =
        _isSending &&
        (_variantGenerationIndex != null ||
            _messages.isEmpty ||
            !_messages.last.isAssistant);

    return AdaptivePage(
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        itemCount: _messages.length + (showTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (showTyping && index == 0) {
            return TypingBubble(
              appearance: _roleBubbleAppearance,
              chatTextColor: widget.settings.chatTextColor,
            );
          }
          final messageIndex =
              _messages.length - 1 - (index - (showTyping ? 1 : 0));
          final message = _messages[messageIndex];
          final innerVoiceStatus = _innerVoiceStatus(messageIndex, message);
          Widget bubble(ChatMessage message) => _MessageBubble(
            message: message,
            appearance: message.isUser
                ? _userBubbleAppearance
                : _roleBubbleAppearance,
            chatTextColor: widget.settings.chatTextColor,
            isHighlighted: messageIndex == highlightedIndex,
            searchQuery: _searchQuery,
            splitRoleMessages:
                widget.settings.splitRoleMessages && message.isAssistant,
            showCharacterInnerVoice: widget.settings.showCharacterInnerVoice,
            showReasoningContent: widget.settings.showReasoningContent,
            isUnsaved: _hasUnsavedReply && messageIndex == _messages.length - 1,
            onRetrySave: _retryReplySave,
            isInnerVoiceGenerating:
                innerVoiceStatus == _InnerVoiceDisplayStatus.generating,
            isInnerVoiceFailed:
                innerVoiceStatus == _InnerVoiceDisplayStatus.failed,
            onOpenInnerVoice:
                message.isAssistant &&
                    message.effectiveInnerVoice.trim().isNotEmpty
                ? () => showCharacterInnerVoiceDialog(
                    context: context,
                    character: _character,
                    innerVoice: message.effectiveInnerVoice,
                    messagesProvider: () => List<ChatMessage>.of(_messages),
                  )
                : null,
            isBusy: _isSummarizing,
            onSelectVariant: _canUseNonDestructiveControls
                ? (variantIndex) =>
                      _selectAssistantVariant(messageIndex, variantIndex)
                : null,
            onRegenerate:
                _canUseNonDestructiveControls &&
                    messageIndex == _messages.length - 1 &&
                    message.isAssistant &&
                    message.effectiveContent.trim().isNotEmpty
                ? () => _regenerateAssistantVariant(messageIndex)
                : null,
            onAddMemory: _canUseNonDestructiveControls
                ? () => _addMessageToMemory(message)
                : null,
            onCopy: () => _copyMessage(message),
            onStoryActions:
                _canMutateConversation &&
                    !_hasUnsavedReply &&
                    message.effectiveContent.trim().isNotEmpty
                ? () => _messageStoryActions(messageIndex)
                : null,
            onSpeak:
                widget.settings.enableCharacterSpeech &&
                    message.isAssistant &&
                    message.effectiveContent.trim().isNotEmpty &&
                    !_isSending &&
                    !_hasUnsavedReply
                ? () => _playReply(message)
                : null,
            isSpeaking:
                _speech.messageId == message.id &&
                _speech.variantId == logicalVariantId(message) &&
                _speech.isPlaying,
            onDelete: _canMutateConversation
                ? () => _deleteMessage(messageIndex)
                : null,
          );
          if (_isSending &&
              _variantGenerationIndex == null &&
              messageIndex == _messages.length - 1 &&
              message.isAssistant) {
            return ValueListenableBuilder<ChatMessage?>(
              valueListenable: _draft,
              builder: (context, draft, _) => bubble(draft ?? message),
            );
          }
          return bubble(message);
        },
      ),
    );
  }

  double _topInset(BuildContext context) {
    return MediaQuery.paddingOf(context).top + kToolbarHeight;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.endpoints,
    required this.selectedEndpointId,
    required this.isSummarizing,
    required this.canSummarize,
    required this.hasBackground,
    required this.onEndpointChanged,
    required this.onSummarize,
  });

  final List<AiEndpointConfig> endpoints;
  final String selectedEndpointId;
  final bool isSummarizing;
  final bool canSummarize;
  final bool hasBackground;
  final ValueChanged<String?> onEndpointChanged;
  final VoidCallback onSummarize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: responsiveMaxContentWidth(width)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            elevation: hasBackground ? 8 : 2,
            color: colorScheme.surface.withValues(
              alpha: hasBackground ? 0.90 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: endpoints.isEmpty
                        ? Text(context.t('请先添加 API 配置'))
                        : DropdownButton<String>(
                            value:
                                endpoints.any(
                                  (endpoint) =>
                                      endpoint.id == selectedEndpointId,
                                )
                                ? selectedEndpointId
                                : null,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(8),
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final endpoint in endpoints)
                                DropdownMenuItem(
                                  value: endpoint.id,
                                  child: Text(endpoint.name),
                                ),
                            ],
                            onChanged: onEndpointChanged,
                          ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canSummarize ? onSummarize : null,
                    icon: isSummarizing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.done_all),
                    label: Text(context.t('结束并总结')),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.appearance,
    required this.chatTextColor,
    required this.isHighlighted,
    required this.searchQuery,
    required this.splitRoleMessages,
    required this.showCharacterInnerVoice,
    this.showReasoningContent = false,
    this.isUnsaved = false,
    this.onRetrySave,
    required this.isInnerVoiceGenerating,
    required this.isInnerVoiceFailed,
    this.onOpenInnerVoice,
    required this.isBusy,
    required this.onSelectVariant,
    this.onRegenerate,
    this.onAddMemory,
    this.showFooter = true,
    this.controlMessage,
    required this.onCopy,
    this.onDelete,
    this.onStoryActions,
    this.onSpeak,
    this.isSpeaking = false,
  });

  final ChatMessage message;
  final ChatBubbleAppearance appearance;
  final int? chatTextColor;
  final bool isHighlighted;
  final String searchQuery;
  final bool splitRoleMessages;
  final bool showCharacterInnerVoice;
  final bool showReasoningContent;
  final bool isUnsaved;
  final VoidCallback? onRetrySave;
  final bool isInnerVoiceGenerating;
  final bool isInnerVoiceFailed;
  final VoidCallback? onOpenInnerVoice;
  final bool isBusy;
  final ValueChanged<int>? onSelectVariant;
  final VoidCallback? onRegenerate;
  final VoidCallback? onAddMemory;
  final bool showFooter;
  final ChatMessage? controlMessage;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;
  final VoidCallback? onStoryActions, onSpeak;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final segments = roleMessageSegments(
      message.effectiveContent,
      enabled: splitRoleMessages,
    );
    if (segments.length > 1) {
      return Column(
        children: [
          for (var index = 0; index < segments.length; index++)
            _MessageBubble(
              message: message.copyWith(
                content: segments[index],
                variants: const [],
              ),
              appearance: appearance,
              chatTextColor: chatTextColor,
              isHighlighted: isHighlighted,
              searchQuery: searchQuery,
              splitRoleMessages: false,
              showCharacterInnerVoice: showCharacterInnerVoice,
              showReasoningContent: showReasoningContent,
              isUnsaved: isUnsaved,
              onRetrySave: onRetrySave,
              isInnerVoiceGenerating: isInnerVoiceGenerating,
              isInnerVoiceFailed: isInnerVoiceFailed,
              onOpenInnerVoice: onOpenInnerVoice,
              showFooter: index == segments.length - 1,
              controlMessage: controlMessage ?? message,
              isBusy: isBusy,
              onSelectVariant: onSelectVariant,
              onRegenerate: onRegenerate,
              onAddMemory: onAddMemory,
              onCopy: onCopy,
              onDelete: onDelete,
              onStoryActions: onStoryActions,
              onSpeak: onSpeak,
              isSpeaking: isSpeaking,
            ),
        ],
      );
    }
    final isUser = message.isUser;
    final controls = controlMessage ?? message;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = isCompactWidth(screenWidth)
        ? screenWidth * 0.82
        : 760.0;
    final showInnerVoiceCard =
        showFooter &&
        controls.isAssistant &&
        showCharacterInnerVoice &&
        (controls.effectiveInnerVoice.trim().isNotEmpty ||
            isInnerVoiceGenerating ||
            isInnerVoiceFailed);

    final bubble = ChatBubble(
      isUser: isUser,
      appearance: appearance,
      highlighted: isHighlighted,
      fallbackTextColor: chatTextColor,
      maxWidth: maxBubbleWidth,
      margin: showInnerVoiceCard
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 10),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MessageContent(
                text: message.effectiveContent,
                textColor: appearance.textColor ?? chatTextColor,
                highlightQuery: searchQuery,
              ),
              if (showFooter &&
                  showReasoningContent &&
                  controls.effectiveReasoningContent.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: ExpansionTile(
                    title: const Text('接口思考'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      SelectableText(controls.effectiveReasoningContent),
                    ],
                  ),
                ),
              if (showFooter && controls.effectiveReplyState == 'interrupted')
                const Text('回复中断'),
              if (showFooter && isUnsaved)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('未保存'),
                    TextButton(
                      onPressed: onRetrySave,
                      child: const Text('重试保存'),
                    ),
                  ],
                ),
              if (showFooter) const SizedBox(height: 4),
              if (showFooter)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.effectiveTime),
                      style: theme.textTheme.labelSmall,
                    ),
                    if (message.effectiveModel != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          message.effectiveModel!,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ],
                ),
              if (showFooter)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: messageBubbleActions(
                      context,
                      onCopy: onCopy,
                      onDelete: onDelete,
                      onAddMemory: onAddMemory,
                      onStoryActions: onStoryActions,
                      onSpeak: onSpeak,
                      isSpeaking: isSpeaking,
                      scale: 1.2,
                    ),
                  ),
                ),
              if (showFooter && controls.isAssistant)
                ChatVariantControls(
                  selectedIndex: controls.selectedVariantIndex,
                  variantCount: controls.variantCount,
                  isGenerating: isBusy,
                  onPrevious: controls.selectedVariantIndex > 0
                      ? () => onSelectVariant?.call(
                          controls.selectedVariantIndex - 1,
                        )
                      : null,
                  onNext:
                      controls.selectedVariantIndex + 1 < controls.variantCount
                      ? () => onSelectVariant?.call(
                          controls.selectedVariantIndex + 1,
                        )
                      : null,
                  onRegenerate: onRegenerate,
                ),
            ],
          );
        },
      ),
    );
    if (!showInnerVoiceCard) {
      return GestureDetector(onLongPress: onStoryActions, child: bubble);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bubble,
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CharacterInnerVoicePreview(
            innerVoice: controls.effectiveInnerVoice,
            isGenerating: isInnerVoiceGenerating,
            isFailed: isInnerVoiceFailed,
            onTap: onOpenInnerVoice,
            maxWidth: maxBubbleWidth,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }
}

enum _InnerVoiceDisplayStatus { idle, generating, failed }

final class _InnerVoiceTarget {
  const _InnerVoiceTarget({
    required this.sessionId,
    required this.messageIndex,
    required this.variantIndex,
    required this.replySnapshot,
  });

  final String sessionId;
  final int messageIndex;
  final int? variantIndex;
  final String replySnapshot;

  bool sameIdentity(_InnerVoiceTarget other) =>
      sessionId == other.sessionId &&
      messageIndex == other.messageIndex &&
      variantIndex == other.variantIndex &&
      replySnapshot == other.replySnapshot;

  bool matchesSelected(
    String currentSessionId,
    int currentMessageIndex,
    ChatMessage message,
  ) {
    if (sessionId != currentSessionId || messageIndex != currentMessageIndex) {
      return false;
    }
    if (variantIndex != null) {
      return variantIndex! >= 0 &&
          variantIndex! < message.variants.length &&
          message.selectedVariantIndex == variantIndex &&
          message.variants[variantIndex!].content == replySnapshot;
    }
    if (message.variants.isNotEmpty) {
      return message.selectedVariantIndex == 0 &&
          message.variants.first.content == replySnapshot;
    }
    return message.content == replySnapshot;
  }
}

final class _InnerVoiceOperation {
  _InnerVoiceOperation({
    required this.id,
    required this.target,
    required this.cancelToken,
    required this.previousInnerVoice,
    required this.revision,
    required this.epoch,
  });

  final int id;
  final _InnerVoiceTarget target;
  final AiCancelToken cancelToken;
  final String previousInnerVoice;
  final int revision;
  final int epoch;
  SessionOperationToken? storageToken;
  String? generatedInnerVoice;
  var cancelled = false;
  var applied = false;
}
