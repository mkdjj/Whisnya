import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/ai_provider.dart';
import '../models/api_config.dart';
import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/chat_summary.dart';
import '../prompts.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.storage,
    required this.aiService,
    required this.character,
    required this.settings,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final AppCharacter character;
  final AppSettings settings;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _toolBarTimer;

  var _apiConfig = ApiConfig.defaults();
  late AppCharacter _character;
  var _summary = ChatSummary.empty('');
  var _messages = <ChatMessage>[];
  var _selectedProvider = AiProvider.deepseek;
  var _isLoading = true;
  var _isSending = false;
  var _isSummarizing = false;
  var _showToolBar = false;
  var _searchQuery = '';
  var _searchResults = <int>[];
  var _activeSearchResult = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _character = widget.character;
    _selectedProvider = _character.defaultProvider;
    _summary = ChatSummary.empty(_character.id);
    _load();
  }

  @override
  void dispose() {
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
      final summary = await widget.storage.loadSummary(_character.id);
      final chat = await widget.storage.loadChat(_character.id);
      var messages = [...chat.messages];

      if (messages.isEmpty && _character.openingMessage.trim().isNotEmpty) {
        messages = [
          ChatMessage(
            role: 'assistant',
            content: _character.openingMessage.trim(),
            time: DateTime.now(),
            provider: _character.defaultProvider.id,
          ),
        ];
        await widget.storage.saveChat(_character.id, messages);
      }

      if (!mounted) return;
      setState(() {
        _apiConfig = apiConfig;
        _summary = summary;
        _messages = messages;
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

    final providerConfig = _apiConfig.get(_selectedProvider);
    final configError = _validateProviderConfig(providerConfig);
    if (configError != null) {
      _showSnack(configError);
      return;
    }

    final userMessage = ChatMessage(
      role: 'user',
      content: text,
      time: DateTime.now(),
    );

    setState(() {
      _messages = [..._messages, userMessage];
      _isSending = true;
    });
    _inputController.clear();
    _scrollToEnd();

    await widget.storage.saveChat(_character.id, _messages);
    await widget.storage.markCharacterUsed(_character.id);

    try {
      final reply = await widget.aiService.sendMessage(
        provider: _selectedProvider.id,
        apiKey: providerConfig.apiKey,
        baseUrl: providerConfig.baseUrl,
        model: providerConfig.model,
        messages: _buildChatRequestMessages(),
      );

      final assistantMessage = ChatMessage(
        role: 'assistant',
        content: reply,
        time: DateTime.now(),
        provider: _selectedProvider.id,
        model: providerConfig.model,
      );

      if (!mounted) return;
      setState(() {
        _messages = [..._messages, assistantMessage];
        _isSending = false;
      });
      await widget.storage.saveChat(_character.id, _messages);
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _showSnack(error.toString());
    }
  }

  Future<void> _summarize() async {
    if (_messages.isEmpty || _isSummarizing) {
      _showSnack('当前没有可总结的聊天记录。');
      return;
    }

    final providerConfig = _apiConfig.get(_selectedProvider);
    final configError = _validateProviderConfig(providerConfig);
    if (configError != null) {
      _showSnack(configError);
      return;
    }

    setState(() => _isSummarizing = true);
    try {
      final prompt = PromptBuilder.buildSummaryPrompt(_messages);
      final summaryText = await widget.aiService.sendMessage(
        provider: _selectedProvider.id,
        apiKey: providerConfig.apiKey,
        baseUrl: providerConfig.baseUrl,
        model: providerConfig.model,
        messages: [
          {'role': 'system', 'content': '你负责总结聊天记录，并只输出总结内容。'},
          {'role': 'user', 'content': prompt},
        ],
      );

      final nextSummary = ChatSummary(
        characterId: _character.id,
        summary: summaryText,
        updatedAt: DateTime.now(),
      );
      await widget.storage.saveSummary(nextSummary);

      if (!mounted) return;
      setState(() {
        _summary = nextSummary;
        _isSummarizing = false;
      });
      _showSummaryDialog();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSummarizing = false);
      _showSnack(error.toString());
    }
  }

  Future<void> _clearChat() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('清空聊天')),
        content: Text(context.t('确定清空当前角色的聊天记录吗？历史总结不会被删除。')),
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

    if (shouldClear != true) return;

    await widget.storage.clearChat(_character.id);
    if (!mounted) return;
    setState(() {
      _messages = [];
      _searchQuery = '';
      _searchResults = [];
      _activeSearchResult = 0;
    });
    _showSnack('聊天记录已清空');
  }

  Future<void> _showSearchDialog() async {
    if (_messages.isEmpty) {
      _showSnack('当前没有可搜索的聊天记录');
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

  List<Map<String, String>> _buildChatRequestMessages() {
    final systemPrompt = PromptBuilder.buildSystemPrompt(
      _character,
      _summary.summary,
    );
    return [
      {'role': 'system', 'content': systemPrompt},
      for (final message in _messages)
        if (message.isUser || message.isAssistant)
          {'role': message.role, 'content': message.content},
    ];
  }

  String? _validateProviderConfig(ApiProviderConfig config) {
    if (config.apiKey.trim().isEmpty) {
      return 'API Key 为空，请先配置。';
    }
    if (config.baseUrl.trim().isEmpty) {
      return 'Base URL 为空，请先配置。';
    }
    if (config.model.trim().isEmpty) {
      return 'Model 为空，请先配置。';
    }
    return null;
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
            enabled: hasSummary,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              hintText: hasSummary ? null : context.t('暂无历史总结，请先生成历史总结。'),
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
                          final confirmed = await _confirmSummaryAction(
                            title: '删除历史总结',
                            content: '确定删除当前角色的历史总结吗？',
                            confirmLabel: '删除',
                          );
                          if (!confirmed || !mounted) return;
                          final nextSummary = ChatSummary.empty(_character.id);
                          await widget.storage.saveSummary(nextSummary);
                          if (!mounted) return;
                          setState(() => _summary = nextSummary);
                          navigator.pop();
                          _showSnack('历史总结已删除');
                        }
                      : null,
                  child: Text(context.t('删除历史总结')),
                ),
                FilledButton(
                  onPressed: hasSummary
                      ? () async {
                          final navigator = Navigator.of(dialogContext);
                          final nextText = controller.text.trim();
                          if (nextText.isEmpty) {
                            _showSnack('总结内容不能为空，想删除请点删除历史总结');
                            return;
                          }
                          if (nextText == text) {
                            navigator.pop();
                            return;
                          }
                          final confirmed = await _confirmSummaryAction(
                            title: '保存历史总结',
                            content: '确定保存对历史总结的改动吗？',
                            confirmLabel: '保存',
                          );
                          if (!confirmed || !mounted) return;
                          final nextSummary = ChatSummary(
                            characterId: _character.id,
                            summary: nextText,
                            updatedAt: DateTime.now(),
                          );
                          await widget.storage.saveSummary(nextSummary);
                          if (!mounted) return;
                          setState(() => _summary = nextSummary);
                          navigator.pop();
                          _showSnack('历史总结已保存');
                        }
                      : null,
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

  Future<bool> _confirmSummaryAction({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.t(title)),
            content: Text(context.t(content)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.t(confirmLabel)),
              ),
            ],
          ),
        ) ??
        false;
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
                  subtitle: Text(_selectedProvider.label),
                ),
                const Divider(),
                _settingsSlider(
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
                _settingsSlider(
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
                _settingsSlider(
                  label: '聊天气泡透明度',
                  value: draft.bubbleOpacity,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  display: '${(draft.bubbleOpacity * 100).round()}%',
                  onChanged: (value) {
                    preview(draft.copyWith(bubbleOpacity: value));
                  },
                  onChangeEnd: (value) {
                    _applyCharacterSettings(
                      draft.copyWith(bubbleOpacity: value),
                    );
                  },
                ),
                _settingsSlider(
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
                const Divider(),
                ListTile(
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
                    _clearChat();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
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

  Widget _settingsSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: context.t(label)),
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
            SizedBox(width: 48, child: Text(display, textAlign: TextAlign.end)),
          ],
        ),
      ),
    );
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    _showSnack('已复制消息');
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
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
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward) {
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(message))));
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
        systemOverlayStyle: _overlayStyle(context),
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

    return _ChatBackground(
      imagePath: _character.backgroundImage,
      opacity: _character.backgroundImageOpacity,
      blur: _character.backgroundBlur,
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
              ),
            ],
          ),
          Positioned(
            top: _topInset(context),
            left: 0,
            right: 0,
            child: _AnimatedTopBar(
              isVisible: _showToolBar || _isSummarizing,
              child: _TopBar(
                selectedProvider: _selectedProvider,
                isSummarizing: _isSummarizing,
                hasBackground: _character.backgroundImage.trim().isNotEmpty,
                onProviderChanged: (provider) {
                  if (provider != null) {
                    setState(() => _selectedProvider = provider);
                    _showToolsTemporarily();
                  }
                },
                onSummarize: () {
                  _showToolsTemporarily();
                  _summarize();
                },
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

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, _topInset(context) + 12, 12, 16),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isSending && index == 0) {
          return const _TypingBubble();
        }
        final messageIndex =
            _messages.length - 1 - (index - (_isSending ? 1 : 0));
        final message = _messages[messageIndex];
        return _MessageBubble(
          message: message,
          bubbleOpacity: _character.bubbleOpacity,
          chatTextColor: widget.settings.chatTextColor,
          isHighlighted: messageIndex == highlightedIndex,
          onCopy: () => _copyMessage(message),
        );
      },
    );
  }

  double _topInset(BuildContext context) {
    return MediaQuery.paddingOf(context).top + kToolbarHeight;
  }

  SystemUiOverlayStyle _overlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selectedProvider,
    required this.isSummarizing,
    required this.hasBackground,
    required this.onProviderChanged,
    required this.onSummarize,
  });

  final AiProvider selectedProvider;
  final bool isSummarizing;
  final bool hasBackground;
  final ValueChanged<AiProvider?> onProviderChanged;
  final VoidCallback onSummarize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        elevation: hasBackground ? 8 : 2,
        color: colorScheme.surface.withValues(alpha: hasBackground ? 0.90 : 1),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<AiProvider>(
                  value: selectedProvider,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(8),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final provider in AiProvider.values)
                      DropdownMenuItem(
                        value: provider,
                        child: Text(provider.label),
                      ),
                  ],
                  onChanged: onProviderChanged,
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
    );
  }
}

class _AnimatedTopBar extends StatelessWidget {
  const _AnimatedTopBar({required this.isVisible, required this.child});

  final bool isVisible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !isVisible,
      child: AnimatedSlide(
        offset: isVisible ? Offset.zero : const Offset(0, -1.15),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: isVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: child,
        ),
      ),
    );
  }
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground({
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

    if (path.isEmpty) {
      return child;
    }
    final file = File(path);

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: alpha,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Image.file(
              file,
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

class _InputComposer extends StatelessWidget {
  const _InputComposer({
    required this.controller,
    required this.isSending,
    required this.hasBackground,
    required this.inputOpacity,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool hasBackground;
  final double inputOpacity;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final alpha = inputOpacity.clamp(0, 1).toDouble();
    final surfaceColor = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: alpha);
    final borderColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: alpha);
    return SafeArea(
      top: false,
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
              IconButton.filled(
                tooltip: context.t('发送'),
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.bubbleOpacity,
    required this.chatTextColor,
    required this.isHighlighted,
    required this.onCopy,
  });

  final ChatMessage message;
  final double bubbleOpacity;
  final int? chatTextColor;
  final bool isHighlighted;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final baseColor = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final color = baseColor.withValues(
      alpha: bubbleOpacity.clamp(0, 1).toDouble(),
    );
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.circular(8);

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: radius,
            border: isHighlighted
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                message.content,
                style: chatTextColor == null
                    ? null
                    : TextStyle(color: Color(chatTextColor!)),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
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
      ),
    );
  }
}
