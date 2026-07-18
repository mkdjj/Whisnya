import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../controllers/chat_conversation_controller.dart';
import '../../models/api_config.dart';
import '../../models/app_character.dart';
import '../../models/app_settings.dart';
import '../../models/chat_bubble_theme.dart';
import '../../models/chat_message.dart';
import '../../models/chat_summary.dart';
import '../../models/user_profile.dart';
import '../../prompts/prompt_builder.dart';
import '../../services/ai/ai_gateway.dart';
import '../../services/ai_service.dart';
import '../../services/chat/chat_summary_service.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/chat_context_policy.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/page_layout.dart';
import '../../utils/snack.dart';
import '../../utils/stream_text_buffer.dart';
import '../../widgets/app_background.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/chat_bubble_theme_editor.dart';
import '../../widgets/endpoint_picker.dart';
import '../../widgets/message_content.dart';
import '../../widgets/setting_slider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.storage,
    required this.aiService,
    required this.character,
    required this.settings,
    super.key,
  });

  final LocalStorageService storage;
  final AiGateway aiService;
  final AppCharacter character;
  final AppSettings settings;

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
  AiCancelToken? _cancelToken;
  StreamTextBuffer? _streamBuffer;
  String? _loadError;

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
      await widget.storage.markCharacterUsed(_character.id);
      final apiConfig = await widget.storage.loadApiConfig();
      final summary = await widget.storage.loadSummary(_character.id);
      final chat = await widget.storage.loadChat(_character.id);
      final selectedEndpointId =
          apiConfig.effectiveEndpoint(_character.defaultEndpointId)?.id ?? '';
      var messages = [...chat.messages];

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
        await widget.storage.saveChat(_character.id, messages);
      }

      if (!mounted) return;
      setState(() {
        _apiConfig = apiConfig;
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

    setState(() {
      _conversation.append(userMessage);
      _isSending = true;
    });
    _inputController.clear();
    _scrollToEnd();

    await widget.storage.saveChat(_character.id, _messages);

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

  Future<void> _requestAssistantReply(AiEndpointConfig endpoint) async {
    final generationId = ++_generationId;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    try {
      final summaryUpdated = await _updateRollingSummary(
        endpoint,
        generationId,
        cancelToken,
      );
      if (!mounted || generationId != _generationId || !_isSending) return;

      final userProfile = (await widget.storage.loadSettings()).userProfile;
      final requestMessages = _buildChatRequestMessages(userProfile);
      final streamResponses = widget.settings.streamResponses;
      final assistantMessage = ChatMessage(
        role: 'assistant',
        content: '',
        time: DateTime.now(),
        endpointId: endpoint.id,
        endpointName: endpoint.name,
        model: endpoint.model,
      );
      if (streamResponses) {
        setState(() {
          _conversation.append(assistantMessage);
        });
      }

      var reply = '';
      final streamBuffer = StreamTextBuffer(
        onFlush: (delta) {
          reply += delta;
          if (!streamResponses ||
              !mounted ||
              generationId != _generationId ||
              !_isSending) {
            return;
          }
          setState(() {
            _conversation.replaceLast(
              assistantMessage.copyWith(content: reply),
            );
          });
        },
      );
      _streamBuffer = streamBuffer;
      await for (final chunk in widget.aiService.streamMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: requestMessages,
        cancelToken: cancelToken,
        includeReasoning: widget.settings.showReasoningContent,
        onUsage: (usage) => unawaited(
          widget.storage.recordAiUsage(
            requestType: 'characterChat',
            model: endpoint.model,
            usage: usage,
            messages: requestMessages,
            summaryUpdated: summaryUpdated,
          ),
        ),
      )) {
        if (!mounted || generationId != _generationId || !_isSending) return;
        streamBuffer.add(chunk);
      }
      streamBuffer.flush();
      if (reply.trim().isEmpty) {
        throw AiException('API 没有返回可用回复。');
      }
      if (!mounted || generationId != _generationId || !_isSending) return;
      setState(() {
        final finalMessage = assistantMessage.copyWith(content: reply);
        if (streamResponses) {
          _conversation.replaceLast(finalMessage);
        } else {
          _conversation.append(finalMessage);
        }
        _isSending = false;
      });
      await widget.storage.saveChat(_character.id, _messages);
    } catch (error) {
      if (!mounted || generationId != _generationId) return;
      setState(() {
        _conversation.dropEmptyAssistantTail();
        _isSending = false;
      });
      context.showSnack(error.toString());
    } finally {
      final streamBuffer = _streamBuffer;
      if (streamBuffer != null) {
        streamBuffer.flush();
        streamBuffer.dispose();
        if (identical(_streamBuffer, streamBuffer)) _streamBuffer = null;
      }
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
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

    final controller = TextEditingController(text: _messages[index].content);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('编辑并重发')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(labelText: context.t('输入消息')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(context.t('重新生成')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (edited == null || edited.isEmpty) return;

    final endpoint = await _reloadEndpoint();
    if (endpoint == null) return;

    setState(() {
      _conversation.editUserMessageAndTruncate(index, edited, DateTime.now());
      _isSending = true;
    });
    await widget.storage.saveChat(_character.id, _messages);
    _scrollToEnd();
    await _requestAssistantReply(endpoint);
  }

  void _stopGeneration() {
    if (!_isSending) return;
    _streamBuffer?.flush();
    _cancelToken?.cancel();
    _cancelToken = null;
    _generationId++;
    setState(() {
      _conversation.dropEmptyAssistantTail();
      _isSending = false;
    });
    unawaited(widget.storage.saveChat(_character.id, _messages));
    context.showSnack('已停止生成');
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
        summary: PromptBuilder.limitSummary(summaryText, 1500),
        updatedAt: DateTime.now(),
        summarizedMessageCount: messages.length,
      );
      await widget.storage.saveSummary(nextSummary);

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
      content: context.t('确定清空当前角色的聊天记录吗？历史总结不会被删除。'),
      confirmLabel: '清空',
    );

    if (!shouldClear) return;

    await widget.storage.clearChat(_character.id);
    if (!mounted) return;
    setState(() {
      _conversation.clearMessages();
      _searchQuery = '';
      _searchResults = [];
      _activeSearchResult = 0;
    });
    context.showSnack('聊天记录已清空');
  }

  Future<void> _showSearchDialog() async {
    if (_messages.isEmpty) {
      context.showSnack('当前没有可搜索的聊天记录');
      return;
    }

    final controller = TextEditingController(text: _searchQuery);
    var query = _searchQuery;
    var results = _findSearchResults(query);
    var active = results.isEmpty
        ? 0
        : _activeSearchResult.clamp(0, results.length - 1).toInt();

    void applySearch(String nextQuery, List<int> nextResults, int nextActive) {
      final safeActive = nextResults.isEmpty
          ? 0
          : nextActive.clamp(0, nextResults.length - 1).toInt();
      setState(() {
        _searchQuery = nextQuery;
        _searchResults = nextResults;
        _activeSearchResult = safeActive;
      });
      if (nextResults.isNotEmpty) {
        _scrollToSearchResult(nextResults[safeActive]);
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void runSearch() {
            final nextQuery = controller.text;
            final nextResults = _findSearchResults(nextQuery);
            setDialogState(() {
              query = nextQuery;
              results = nextResults;
              active = 0;
            });
            applySearch(nextQuery, nextResults, 0);
          }

          void move(int delta) {
            if (results.isEmpty) return;
            final nextActive =
                (active + delta + results.length) % results.length;
            setDialogState(() => active = nextActive);
            applySearch(query, results, nextActive);
          }

          final status = query.trim().isEmpty
              ? context.t('输入关键词开始搜索')
              : results.isEmpty
              ? context.t('没有找到结果')
              : context.t('第 ${active + 1} / ${results.length} 个结果');

          return AlertDialog(
            title: Text(context.t('搜索聊天记录')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: context.t('输入关键词'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onSubmitted: (_) => runSearch(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: context.t('上一个'),
                      onPressed: results.isEmpty ? null : () => move(-1),
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    Expanded(child: Text(status, textAlign: TextAlign.center)),
                    IconButton(
                      tooltip: context.t('下一个'),
                      onPressed: results.isEmpty ? null : () => move(1),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _searchResults = [];
                    _activeSearchResult = 0;
                  });
                  Navigator.of(dialogContext).pop();
                },
                child: Text(context.t('关闭')),
              ),
              FilledButton(onPressed: runSearch, child: Text(context.t('搜索'))),
            ],
          );
        },
      ),
    );
    controller.dispose();
  }

  List<int> _findSearchResults(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const [];
    }

    final results = <int>[];
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].content.toLowerCase().contains(needle)) {
        results.add(i);
      }
    }
    return results;
  }

  List<Map<String, String>> _buildChatRequestMessages(UserProfile userProfile) {
    return PromptBuilder.buildChatRequestMessages(
      character: _character,
      userProfile: userProfile,
      historySummary: _summary.summary,
      summarizedMessageCount: _summary.summarizedMessageCount,
      messages: _messages,
      useFullContext: _character.useFullChatContext,
    );
  }

  Future<bool> _updateRollingSummary(
    AiEndpointConfig endpoint,
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    if (_character.useFullChatContext) return false;

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
      await widget.storage.saveSummary(nextSummary);
      if (!mounted || generationId != _generationId || !_isSending) {
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
                          final nextSummary = ChatSummary.empty(_character.id);
                          await widget.storage.saveSummary(nextSummary);
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
                    await widget.storage.saveSummary(nextSummary);
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
                          preview(next);
                          _applyCharacterSettings(next);
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
                    preview(next);
                    _applyCharacterSettings(next);
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
                      _applyCharacterSettings(
                        draft.copyWith(chatSummaryMessageLimit: value.round()),
                      );
                    },
                  ),
                ],
                const Divider(),
                SettingSlider(
                  label: '背景图透明度',
                  value: draft.backgroundImageOpacity,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  display: '${(draft.backgroundImageOpacity * 100).round()}%',
                  onChanged: (value) {
                    preview(draft.copyWith(backgroundImageOpacity: value));
                  },
                  onChangeEnd: (value) {
                    _applyCharacterSettings(
                      draft.copyWith(backgroundImageOpacity: value),
                    );
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
                    _applyCharacterSettings(
                      draft.copyWith(backgroundBlur: value),
                    );
                  },
                ),
                SettingSlider(
                  key: const ValueKey('chat-input-opacity-setting'),
                  label: '输入框透明度',
                  value: draft.inputOpacity,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  display: '${(draft.inputOpacity * 100).round()}%',
                  onChanged: (value) {
                    preview(draft.copyWith(inputOpacity: value));
                  },
                  onChangeEnd: (value) {
                    _applyCharacterSettings(
                      draft.copyWith(inputOpacity: value),
                    );
                  },
                ),
                ExpansionTile(
                  key: const ValueKey('chat-bubble-theme-expansion'),
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  title: Text(context.t('聊天气泡样式')),
                  children: [
                    ChatBubbleThemeEditor(
                      theme: draft.bubbleTheme,
                      defaultTheme: ChatBubbleTheme.characterDefault,
                      onPreview: (theme) =>
                          preview(draft.copyWith(bubbleTheme: theme)),
                      onSave: (theme) => _applyCharacterSettings(
                        draft.copyWith(bubbleTheme: theme),
                      ),
                    ),
                  ],
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

  void _applyCharacterSettings(AppCharacter character) {
    final next = character.copyWith(updatedAt: DateTime.now());
    setState(() => _character = next);
    unawaited(widget.storage.saveCharacter(next));
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
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    context.showSnack('已复制消息');
  }

  Future<void> _deleteMessage(int index) async {
    final deletion = _conversation.deleteAt(index);
    if (deletion == ChatMessageDeletion.ignored) return;
    if (deletion == ChatMessageDeletion.summaryInvalidated) {
      await widget.storage.saveSummary(_summary);
      if (!mounted) return;
    }
    setState(() {
      _searchResults = _findSearchResults(_searchQuery);
      _activeSearchResult = _searchResults.isEmpty
          ? 0
          : _activeSearchResult.clamp(0, _searchResults.length - 1);
    });
    await widget.storage.saveChat(_character.id, _messages);
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: appSystemOverlayStyle(context),
        title: Text(_character.name),
        actions: [
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
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
              _InputComposer(
                controller: _inputController,
                isSending: _isSending,
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
        _isSending && (_messages.isEmpty || !_messages.last.isAssistant);

    return AdaptivePage(
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, _topInset(context) + 12, 0, 16),
        itemCount: _messages.length + (showTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (showTyping && index == 0) {
            return _TypingBubble(
              appearance: _character.bubbleTheme.role,
              chatTextColor: widget.settings.chatTextColor,
            );
          }
          final messageIndex =
              _messages.length - 1 - (index - (showTyping ? 1 : 0));
          final message = _messages[messageIndex];
          return _MessageBubble(
            message: message,
            appearance: message.isUser
                ? _character.bubbleTheme.user
                : _character.bubbleTheme.role,
            chatTextColor: widget.settings.chatTextColor,
            isHighlighted: messageIndex == highlightedIndex,
            searchQuery: _searchQuery,
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

class _InputComposer extends StatelessWidget {
  const _InputComposer({
    required this.controller,
    required this.isSending,
    required this.hasBackground,
    required this.inputOpacity,
    required this.onSend,
    required this.onStop,
    this.onRetry,
    this.onEditResend,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool hasBackground;
  final double inputOpacity;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onRetry;
  final VoidCallback? onEditResend;

  @override
  Widget build(BuildContext context) {
    final alpha = inputOpacity.clamp(0, 1).toDouble();
    final surfaceColor = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: alpha);
    final borderColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: alpha);
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: responsiveMaxContentWidth(width),
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
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: context.t('输入消息'),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: alpha),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!isSending && onRetry != null) ...[
                    IconButton(
                      tooltip: context.t('重试上一条'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (!isSending && onEditResend != null) ...[
                    IconButton(
                      tooltip: context.t('编辑并重发'),
                      onPressed: onEditResend,
                      icon: const Icon(Icons.edit_note),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton.filled(
                    tooltip: context.t(isSending ? '停止生成' : '发送'),
                    onPressed: isSending ? onStop : onSend,
                    icon: isSending
                        ? const Icon(Icons.stop)
                        : const Icon(Icons.send),
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
    required this.onCopy,
    this.onDelete,
  });

  final ChatMessage message;
  final ChatBubbleAppearance appearance;
  final int? chatTextColor;
  final bool isHighlighted;
  final String searchQuery;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
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
                text: message.content,
                textColor: appearance.textColor ?? chatTextColor,
                highlightQuery: searchQuery,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.time),
                    style: theme.textTheme.labelSmall,
                  ),
                  if (message.model != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        message.model!,
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
                  IconButton(
                    tooltip: context.t('删除消息'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                  ),
                ],
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

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.appearance, this.chatTextColor});

  final ChatBubbleAppearance appearance;
  final int? chatTextColor;

  @override
  Widget build(BuildContext context) {
    return ChatBubble(
      isUser: false,
      appearance: appearance,
      fallbackTextColor: chatTextColor,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(context.t('生成中')),
        ],
      ),
    );
  }
}
