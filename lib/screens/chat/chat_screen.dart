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
import '../../models/chat_reply_variant.dart';
import '../../models/chat_session.dart';
import '../../models/chat_summary.dart';
import '../../models/character_memory_entry.dart';
import '../../models/user_profile.dart';
import '../../models/world_book.dart';
import '../../prompts/prompt_builder.dart';
import '../../services/ai/ai_gateway.dart';
import '../../services/ai_service.dart';
import '../../services/chat/chat_summary_service.dart';
import '../../services/chat/memory_context_service.dart';
import '../../services/local_storage_service.dart';
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

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
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
  var _showToolBar = false;
  var _searchQuery = '';
  var _searchResults = <int>[];
  var _activeSearchResult = 0;
  var _generationId = 0;
  int? _variantGenerationIndex;
  AiCancelToken? _cancelToken;
  StreamTextBuffer? _streamBuffer;
  String? _loadError;

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
    _character = widget.character;
    _conversation = ChatConversationController(characterId: _character.id);
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _streamBuffer?.dispose();
    _toolBarTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final apiConfig = await widget.storage.loadApiConfig();
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
            await widget.storage.saveChatBySession(activeSession, messages);
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

      if (!mounted) return;
      setState(() {
        _apiConfig = apiConfig;
        _session = activeSession;
        _selectedEndpointId = selectedEndpointId;
        _conversation.load(messages: messages, summary: summary);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
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
    if (widget.storage.usesSessionStorage) {
      await widget.storage.saveChatBySession(_currentSession, _messages);
    } else {
      await widget.storage.saveChat(_character.id, _messages);
    }
  }

  Future<void> _saveCurrentSummary() async {
    await _saveSummary(_summary);
  }

  Future<void> _saveSummary(ChatSummary summary) async {
    if (widget.storage.usesSessionStorage) {
      await widget.storage.saveSummaryBySession(summary);
    } else {
      await widget.storage.saveSummary(summary);
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    final endpoint = await _reloadEndpoint();
    if (endpoint == null) return;

    final userMessage = ChatMessage(
      role: 'user',
      content: text,
      time: DateTime.now(),
    );
    final previousMessages = [..._messages];

    setState(() {
      _conversation.append(userMessage);
      _isSending = true;
    });
    _inputController.clear();
    _scrollToEnd();

    try {
      await _saveCurrentChat();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _conversation.replaceMessages(previousMessages);
        _isSending = false;
      });
      if (_inputController.text.isEmpty) _inputController.text = text;
      context.showSnack(error.toString());
      return;
    }

    await _requestAssistantReply(endpoint);
  }

  Future<AiEndpointConfig?> _reloadEndpoint() async {
    try {
      final config = await widget.storage.loadApiConfig();
      final endpoint = config.effectiveEndpoint(_selectedEndpointId);
      if (!mounted) return null;
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
      if (mounted) context.showSnack(error.toString());
      return null;
    }
  }

  Future<void> _requestAssistantReply(
    AiEndpointConfig endpoint, {
    int? variantAt,
  }) async {
    final generationId = ++_generationId;
    final sessionId = _currentSession.id;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    StreamTextBuffer? requestBuffer;
    try {
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
        entries: memories,
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
      final streamResponses = widget.settings.streamResponses;
      final assistantMessage = ChatMessage(
        role: 'assistant',
        content: '',
        time: DateTime.now(),
        endpointId: endpoint.id,
        endpointName: endpoint.name,
        model: endpoint.model,
      );
      if (streamResponses && variantAt == null) {
        setState(() {
          _conversation.append(assistantMessage);
        });
      }

      var reply = '';
      requestBuffer = StreamTextBuffer(
        onFlush: (delta) {
          reply += delta;
          if (!streamResponses ||
              !_isCurrentGeneration(generationId, sessionId)) {
            return;
          }
          if (variantAt == null) {
            setState(() {
              _conversation.replaceLast(
                assistantMessage.copyWith(content: reply),
              );
            });
          }
        },
      );
      _streamBuffer = requestBuffer;
      await for (final chunk in widget.aiService.streamMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: requestMessages,
        cancelToken: cancelToken,
        includeReasoning: widget.settings.showReasoningContent,
        onUsage: (usage) => unawaited(
          widget.storage.recordAiUsage(
            requestType: variantAt == null
                ? 'characterChat'
                : 'characterChatVariant',
            model: endpoint.model,
            usage: usage,
            messages: requestMessages,
            summaryUpdated: summaryUpdated,
          ),
        ),
      )) {
        if (!_isCurrentGeneration(generationId, sessionId)) return;
        requestBuffer.add(chunk);
      }
      requestBuffer.flush();
      if (reply.trim().isEmpty) {
        throw AiException('API 没有返回可用回复。');
      }
      if (!_isCurrentGeneration(generationId, sessionId)) return;
      setState(() {
        final finalMessage = assistantMessage.copyWith(content: reply);
        if (variantAt != null) {
          _conversation.addAssistantVariant(
            variantAt,
            ChatReplyVariant(
              content: reply,
              time: DateTime.now(),
              endpointId: endpoint.id,
              endpointName: endpoint.name,
              model: endpoint.model,
            ),
          );
        } else if (streamResponses) {
          _conversation.replaceLast(finalMessage);
        } else {
          _conversation.append(finalMessage);
        }
        _isSending = false;
      });
      await _saveCurrentChat();
    } catch (error) {
      if (!mounted ||
          generationId != _generationId ||
          _session?.id != sessionId) {
        return;
      }
      setState(() {
        if (variantAt == null) _conversation.dropEmptyAssistantTail();
        _isSending = false;
      });
      context.showSnack(error.toString());
    } finally {
      final ownedBuffer = requestBuffer;
      if (ownedBuffer != null) {
        ownedBuffer.flush();
        ownedBuffer.dispose();
        if (identical(_streamBuffer, ownedBuffer)) _streamBuffer = null;
      }
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      if (mounted &&
          generationId == _generationId &&
          _variantGenerationIndex == variantAt) {
        setState(() => _variantGenerationIndex = null);
      }
    }
  }

  bool _isCurrentGeneration(int generationId, String sessionId) =>
      mounted &&
      generationId == _generationId &&
      _isSending &&
      _session?.id == sessionId;

  Future<void> _regenerateAssistantVariant(int messageIndex) async {
    if (_isSending || !_conversation.canRegenerateAssistantAt(messageIndex)) {
      return;
    }
    final endpoint = await _reloadEndpoint();
    if (endpoint == null) return;
    setState(() {
      _isSending = true;
      _variantGenerationIndex = messageIndex;
    });
    await _requestAssistantReply(endpoint, variantAt: messageIndex);
  }

  Future<void> _openSessionList() async {
    final beforeId = _session?.id;
    final selected = await Navigator.of(context).push<ChatSession>(
      MaterialPageRoute(
        builder: (_) => ChatSessionListScreen(
          storage: widget.storage,
          character: _character,
          selectedSessionId: _session?.id,
        ),
      ),
    );
    if (!mounted) return;

    final sessions = await widget.storage.loadChatSessions(_character.id);
    ChatSession? target;
    if (selected != null) {
      target = sessions
          .where((session) => session.id == selected.id)
          .firstOrNull;
    }
    target ??= sessions.where((session) => session.id == beforeId).firstOrNull;
    target ??= await widget.storage.getOrCreateRecentChatSession(_character.id);
    if (!mounted) return;

    if (target.id != beforeId) {
      _cancelActiveGeneration(showMessage: false);
      _session = target;
      await _load();
      return;
    }
    setState(() => _session = target);
  }

  Future<void> _openMemoryManager() async {
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
          fixedScope: scope,
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
    final message = _messages[messageIndex];
    if (variantIndex == message.selectedVariantIndex || _isSending) return;
    if (_conversation.hasMessagesAfter(messageIndex)) {
      final confirmed = await showConfirmDialog(
        context: context,
        title: '切换候选回复',
        content: context.t('切换此候选将删除它之后的消息，并可能清空历史总结，是否继续？'),
        confirmLabel: '继续',
      );
      if (!confirmed) return;
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
    await _saveCurrentSummary();
  }

  Future<void> _retryLastUserMessage() async {
    if (_isSending || _messages.isEmpty || !_messages.last.isUser) return;
    final endpoint = await _reloadEndpoint();
    if (endpoint == null) return;
    setState(() => _isSending = true);
    _scrollToEnd();
    await _requestAssistantReply(endpoint);
  }

  Future<void> _editLastUserMessageAndResend() async {
    if (_isSending) return;
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
    if (!mounted) return;
    if (edited == null || edited.isEmpty) return;

    final endpoint = await _reloadEndpoint();
    if (endpoint == null) return;

    final previousMessages = [..._messages];
    setState(() {
      _conversation.editUserMessageAndTruncate(index, edited, DateTime.now());
      _isSending = true;
    });
    try {
      await _saveCurrentChat();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _conversation.replaceMessages(previousMessages);
        _isSending = false;
      });
      context.showSnack(error.toString());
      return;
    }
    _scrollToEnd();
    await _requestAssistantReply(endpoint);
  }

  void _stopGeneration() => _cancelActiveGeneration();

  void _cancelActiveGeneration({bool showMessage = true}) {
    if (!_isSending) return;
    _streamBuffer?.flush();
    _cancelToken?.cancel();
    _cancelToken = null;
    _generationId++;
    setState(() {
      _conversation.dropEmptyAssistantTail();
      _variantGenerationIndex = null;
      _isSending = false;
    });
    unawaited(_saveCurrentChat());
    if (showMessage) context.showSnack('已停止生成');
  }

  Future<void> _summarize() async {
    if (_messages.isEmpty || _isSummarizing) {
      context.showSnack('当前没有可总结的聊天记录。');
      return;
    }

    final endpoint = await _reloadEndpoint();
    if (endpoint == null) return;

    setState(() => _isSummarizing = true);
    try {
      final messages = _conversation.chatMessagesOnly;
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
        onUsage: (usage) => unawaited(
          widget.storage.recordAiUsage(
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

      final nextSummary = ChatSummary(
        characterId: _character.id,
        sessionId: _currentSession.id,
        summary: PromptBuilder.limitSummary(summaryText, 1500),
        updatedAt: DateTime.now(),
        summarizedMessageCount: messages.length,
      );
      await _saveSummary(nextSummary);

      if (!mounted) return;
      setState(() {
        _conversation.setSummary(nextSummary);
        _isSummarizing = false;
      });
      unawaited(_showSummaryDialog());
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSummarizing = false);
      context.showSnack(error.toString());
    }
  }

  Future<void> _clearChat() async {
    final shouldClear = await showConfirmDialog(
      context: context,
      title: '清空聊天',
      content: context.t('确定清空当前对话的聊天记录吗？历史总结不会被删除。'),
      confirmLabel: '清空',
    );

    if (!shouldClear) return;

    if (widget.storage.usesSessionStorage) {
      await widget.storage.saveChatBySession(_currentSession, const []);
    } else {
      await widget.storage.clearChat(_character.id);
    }
    if (!mounted) return;
    setState(() {
      _conversation.clearMessages();
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

    setState(() => _isSummarizing = true);
    try {
      final nextSummary = await updateChatSummary(
        widget.aiService,
        characterId: _character.id,
        current: _summary,
        messages: _messages,
        summaryLimit: _character.chatSummaryMessageLimit,
        settings: widget.settings,
        endpoint: endpoint,
        cancelToken: cancelToken,
        onUsage: (usage, messages) => unawaited(
          widget.storage.recordAiUsage(
            requestType: 'characterSummary',
            model: endpoint.model,
            usage: usage,
            messages: messages,
            summaryUpdated: true,
          ),
        ),
      );
      if (nextSummary == null) return false;
      if (!_isCurrentGeneration(generationId, sessionId)) return false;
      await _saveSummary(nextSummary);
      if (!_isCurrentGeneration(generationId, sessionId)) {
        return true;
      }
      setState(() => _conversation.setSummary(nextSummary));
      return true;
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  Future<void> _showSummaryDialog() async {
    final text = _summary.summary.trim();
    final controller = TextEditingController(text: text);
    final hasSummary = text.isNotEmpty;

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
                          final confirmed = await showConfirmDialog(
                            context: context,
                            title: '删除历史总结',
                            content: context.t('确定删除当前角色的历史总结吗？'),
                            confirmLabel: '删除',
                          );
                          if (!confirmed || !mounted) return;
                          final nextSummary = ChatSummary.empty(
                            _character.id,
                            _currentSession.id,
                          );
                          await _saveSummary(nextSummary);
                          if (!mounted) return;
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
                    final nextSummary = ChatSummary(
                      characterId: _character.id,
                      sessionId: _currentSession.id,
                      summary: nextText,
                      updatedAt: DateTime.now(),
                      summarizedMessageCount:
                          _summary.summarizedMessageCount == 0
                          ? manualSummaryBoundary(
                              messageCount:
                                  _conversation.chatMessagesOnly.length,
                            )
                          : _summary.summarizedMessageCount,
                    );
                    await _saveSummary(nextSummary);
                    if (!mounted) return;
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
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_clearChat());
                  },
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
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    final deletingVariant = message.isAssistant && message.variantCount > 1;
    final confirmed = await showConfirmDialog(
      context: context,
      title: context.t(deletingVariant ? '删除候选回复' : '删除消息'),
      content: context.t(deletingVariant ? '确定删除当前候选回复吗？' : '确定删除这条消息吗？'),
      confirmLabel: '删除',
    );
    if (!confirmed) return;

    final deletion = _conversation.deleteAt(index);
    if (deletion == ChatMessageDeletion.ignored) return;
    if (deletion == ChatMessageDeletion.summaryInvalidated) {
      await _saveCurrentSummary();
      if (!mounted) return;
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
    return Scaffold(
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
          onTap: _isLoading ? null : _openSessionList,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_character.name),
              if (_session != null)
                Text(
                  _session!.title,
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: context.t('对话管理'),
            onPressed: _isLoading ? null : _openSessionList,
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: context.t('搜索聊天'),
            onPressed: _showSearchDialog,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: context.t('查看历史总结'),
            onPressed: _showSummaryDialog,
            icon: const Icon(Icons.summarize_outlined),
          ),
          IconButton(
            tooltip: context.t('聊天设置'),
            onPressed: _showChatSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: context.t('记忆与世界书'),
            onPressed: _isLoading ? null : _openMemoryManager,
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
      ),
      body: _buildBody(),
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
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: _buildMessages(),
                ),
              ),
              ChatInputComposer(
                controller: _inputController,
                isGenerating: _isSending,
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
          Positioned(
            top: _topInset(context),
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !showTopBar,
              child: AnimatedSlide(
                offset: showTopBar ? Offset.zero : const Offset(0, -1.15),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: showTopBar ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _TopBar(
                    endpoints: _apiConfig.enabledEndpoints,
                    selectedEndpointId: _selectedEndpointId,
                    isSummarizing: _isSummarizing,
                    hasBackground: _character.backgroundImage.trim().isNotEmpty,
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
                  ),
                ),
              ),
            ),
          ),
        ],
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
        padding: EdgeInsets.fromLTRB(0, _topInset(context) + 12, 0, 16),
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
          return _MessageBubble(
            message: message,
            appearance: message.isUser
                ? _userBubbleAppearance
                : _roleBubbleAppearance,
            chatTextColor: widget.settings.chatTextColor,
            isHighlighted: messageIndex == highlightedIndex,
            searchQuery: _searchQuery,
            splitRoleMessages:
                widget.settings.splitRoleMessages && message.isAssistant,
            isGenerating: _isSending,
            onSelectVariant: (variantIndex) =>
                _selectAssistantVariant(messageIndex, variantIndex),
            onRegenerate: _conversation.canRegenerateAssistantAt(messageIndex)
                ? () => _regenerateAssistantVariant(messageIndex)
                : null,
            onAddMemory: () => _addMessageToMemory(message),
            onCopy: () => _copyMessage(message),
            onDelete: _isSending ? null : () => _deleteMessage(messageIndex),
          );
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
    required this.hasBackground,
    required this.onEndpointChanged,
    required this.onSummarize,
  });

  final List<AiEndpointConfig> endpoints;
  final String selectedEndpointId;
  final bool isSummarizing;
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
                    onPressed: isSummarizing ? null : onSummarize,
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
    required this.isGenerating,
    required this.onSelectVariant,
    this.onRegenerate,
    required this.onAddMemory,
    this.showFooter = true,
    this.controlMessage,
    required this.onCopy,
    this.onDelete,
  });

  final ChatMessage message;
  final ChatBubbleAppearance appearance;
  final int? chatTextColor;
  final bool isHighlighted;
  final String searchQuery;
  final bool splitRoleMessages;
  final bool isGenerating;
  final ValueChanged<int> onSelectVariant;
  final VoidCallback? onRegenerate;
  final VoidCallback onAddMemory;
  final bool showFooter;
  final ChatMessage? controlMessage;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;

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
              showFooter: index == segments.length - 1,
              controlMessage: controlMessage ?? message,
              isGenerating: isGenerating,
              onSelectVariant: onSelectVariant,
              onRegenerate: onRegenerate,
              onAddMemory: onAddMemory,
              onCopy: onCopy,
              onDelete: onDelete,
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

    return ChatBubble(
      isUser: isUser,
      appearance: appearance,
      highlighted: isHighlighted,
      fallbackTextColor: chatTextColor,
      maxWidth: maxBubbleWidth,
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
                    ...messageBubbleActions(
                      context,
                      onCopy: onCopy,
                      onDelete: onDelete,
                      onAddMemory: onAddMemory,
                    ),
                  ],
                ),
              if (showFooter && controls.isAssistant)
                ChatVariantControls(
                  selectedIndex: controls.selectedVariantIndex,
                  variantCount: controls.variantCount,
                  isGenerating: isGenerating,
                  onPrevious: controls.selectedVariantIndex > 0
                      ? () => onSelectVariant(controls.selectedVariantIndex - 1)
                      : null,
                  onNext:
                      controls.selectedVariantIndex + 1 < controls.variantCount
                      ? () => onSelectVariant(controls.selectedVariantIndex + 1)
                      : null,
                  onRegenerate: onRegenerate,
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }
}
