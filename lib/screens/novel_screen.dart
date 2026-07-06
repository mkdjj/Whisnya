import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/ai_provider.dart';
import '../models/api_config.dart';
import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/novel_book.dart';
import '../prompts.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../services/novel_parser.dart';
import '../services/novel_summary_service.dart';
import '../utils/app_i18n.dart';
import '../utils/page_layout.dart';
import '../utils/password_lock.dart';
import '../widgets/message_content.dart';

class NovelScreen extends StatefulWidget {
  const NovelScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    this.useGridView = false,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final AppSettings settings;
  final bool useGridView;

  @override
  State<NovelScreen> createState() => NovelScreenState();
}

class NovelScreenState extends State<NovelScreen> {
  var _isLoading = true;
  String? _error;
  List<NovelBook> _books = const [];

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
      final books = await widget.storage.loadNovels();
      if (!mounted) return;
      setState(() {
        _books = books;
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

  Future<void> importNovel() => _importNovel();

  Future<void> _importNovel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    final filePath = result?.files.single.path;
    if (filePath == null) {
      return;
    }

    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final content = await _decodePickedNovel(bytes);
      final title = result!.files.single.name.replaceFirst(
        RegExp(r'\.txt$', caseSensitive: false),
        '',
      );
      final book = await widget.storage.importNovelText(
        title: title,
        content: content,
      );
      if (!mounted) return;
      await _openBook(book);
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    }
  }

  Future<String> _decodePickedNovel(List<int> bytes) async {
    try {
      return decodeNovelBytes(bytes);
    } on NovelDecodeException {
      final encoding = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(context.t('选择 TXT 编码')),
          children: [
            for (final encoding in supportedNovelEncodings)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(encoding),
                child: Text(encoding.toUpperCase()),
              ),
          ],
        ),
      );
      if (encoding == null) {
        throw const NovelDecodeException('已取消导入。');
      }
      return decodeNovelBytes(bytes, encoding: encoding);
    }
  }

  Future<void> _openBook(NovelBook book) async {
    if (!await _verifyBookOperation(book, '打开小说')) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovelReaderScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          settings: widget.settings,
          book: book,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _toggleBookHidden(NovelBook book) async {
    if (!await _verifyBookOperation(book, book.isHidden ? '显示书名' : '隐藏书名')) {
      return;
    }
    if (!mounted) return;

    await widget.storage.saveNovel(
      book.copyWith(isHidden: !book.isHidden, updatedAt: DateTime.now()),
    );
    if (!mounted) return;
    _showSnack(book.isHidden ? '已显示设定' : '已隐藏设定');
    await _load();
  }

  Future<void> _toggleBookLock(NovelBook book) async {
    if (!book.isLocked && !widget.settings.hasPrivacyPassword) {
      _showSnack('请先到设置里设置隐私密码');
      return;
    }
    if (book.isLocked && !await _verifyBookOperation(book, '解除上锁')) {
      return;
    }
    await widget.storage.saveNovel(
      book.copyWith(isLocked: !book.isLocked, updatedAt: DateTime.now()),
    );
    if (!mounted) return;
    _showSnack(book.isLocked ? '已解除上锁' : '已上锁');
    await _load();
  }

  Future<bool> _verifyBookOperation(NovelBook book, String title) async {
    if (!book.isLocked) {
      return true;
    }
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

  Future<void> _deleteBook(NovelBook book) async {
    if (!await _verifyBookOperation(book, '删除小说')) {
      return;
    }
    if (!mounted) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('删除小说')),
        content: Text(
          context.isEnglish
              ? 'Delete "${book.title}"? Novel chats will also be deleted.'
              : '确定删除《${book.title}》吗？小说内聊天也会一起删除。',
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
    if (shouldDelete != true) return;

    await widget.storage.deleteNovel(book);
    if (!mounted) return;
    _showSnack('已删除小说');
    await _load();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(message))));
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

    final content = _books.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(context.t('还没有导入小说')),
                ],
              ),
            ),
          )
        : widget.useGridView
        ? GridView.builder(
            padding: EdgeInsets.fromLTRB(
              0,
              homeListTop(context) - kToolbarHeight,
              0,
              50,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 72,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _books.length,
            itemBuilder: (context, index) {
              final book = _books[index];
              return Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openBook(book),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      children: [
                        Icon(book.isChatMode ? Icons.chat : Icons.menu_book),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                book.isHidden ? '******' : book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _bookStatus(book),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 36, child: _bookMenu(book)),
                      ],
                    ),
                  ),
                ),
              );
            },
          )
        : ListView.separated(
            padding: EdgeInsets.fromLTRB(
              0,
              homeListTop(context) - kToolbarHeight,
              0,
              50,
            ),
            itemCount: _books.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final book = _books[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(book.isChatMode ? Icons.chat : Icons.menu_book),
                  title: Text(
                    _bookListTitle(book),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                  subtitle: Text(_bookStatus(book)),
                  onTap: () => _openBook(book),
                  trailing: _bookMenu(book),
                ),
              );
            },
          );

    return AdaptivePage(child: content);
  }

  String _bookListTitle(NovelBook book) {
    if (book.isHidden) return '******';
    final title = book.title.trim();
    const maxLength = 14;
    if (title.characters.length <= maxLength) return title;
    return '${title.characters.take(maxLength)}*';
  }

  String _bookStatus(NovelBook book) {
    return book.summary.trim().isEmpty
        ? context.t('阅读模式')
        : context.isEnglish
        ? '${book.roles.length} roles generated'
        : '已生成 ${book.roles.length} 个角色';
  }

  Widget _bookMenu(NovelBook book) {
    return PopupMenuButton<_NovelAction>(
      onSelected: (action) {
        switch (action) {
          case _NovelAction.hide:
            _toggleBookHidden(book);
            break;
          case _NovelAction.lock:
            _toggleBookLock(book);
            break;
          case _NovelAction.delete:
            _deleteBook(book);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _NovelAction.hide,
          child: ListTile(
            leading: Icon(
              book.isHidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            title: Text(context.t(book.isHidden ? '显示设定' : '隐藏设定')),
          ),
        ),
        PopupMenuItem(
          value: _NovelAction.lock,
          child: ListTile(
            leading: Icon(
              book.isLocked ? Icons.lock_open_outlined : Icons.lock_outline,
            ),
            title: Text(context.t(book.isLocked ? '解除上锁' : '上锁')),
          ),
        ),
        PopupMenuItem(
          value: _NovelAction.delete,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.t('删除小说')),
          ),
        ),
      ],
    );
  }
}

enum _NovelAction { hide, lock, delete }

enum _NovelSummaryMode { low, range, full }

int novelRoleIndexAfterDelete({
  required int selectedIndex,
  required int deletedIndex,
  required int newLength,
  required bool keepReplacement,
}) {
  if (selectedIndex < 0 || newLength <= 0) {
    return -1;
  }
  if (selectedIndex == deletedIndex) {
    return keepReplacement ? deletedIndex.clamp(0, newLength - 1).toInt() : -1;
  }
  if (selectedIndex > deletedIndex) {
    return selectedIndex - 1;
  }
  return selectedIndex.clamp(0, newLength - 1).toInt();
}

class NovelReaderScreen extends StatefulWidget {
  const NovelReaderScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    required this.book,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final AppSettings settings;
  final NovelBook book;

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
  final _inputController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _readScrollController = ScrollController();

  late NovelBook _book;
  var _apiConfig = ApiConfig.defaults();
  var _selectedEndpointId = '';
  var _content = '';
  var _readChunks = <String>[];
  var _chapters = <NovelChapter>[];
  var _messages = <ChatMessage>[];
  NovelSummaryCache? _summaryCache;
  var _isLoading = true;
  var _isBusy = false;
  var _busyText = '';
  var _isSending = false;
  AiCancelToken? _cancelToken;
  var _readerSearchQuery = '';
  var _readProgress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _readScrollController.addListener(_updateReadProgress);
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _readScrollController.dispose();
    _inputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final apiConfig = await widget.storage.loadApiConfig();
      final content = await widget.storage.loadNovelText(_book);
      final chat = await widget.storage.loadNovelChat(_book.id);
      final summaryCache = await NovelSummaryService(
        widget.storage,
      ).loadCache(_book.id);
      if (!mounted) return;
      setState(() {
        _apiConfig = apiConfig;
        _selectedEndpointId =
            apiConfig.effectiveEndpoint(_selectedEndpointId)?.id ?? '';
        _content = content;
        _readChunks = splitNovelText(content, 1600);
        _chapters = _applyManualChapterTitles(buildNovelChapters(content));
        _messages = chat.messages;
        _summaryCache = summaryCache;
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

  Future<void> _saveBook(NovelBook book) async {
    final next = book.copyWith(updatedAt: DateTime.now());
    await widget.storage.saveNovel(next);
    if (!mounted) return;
    setState(() => _book = next);
  }

  List<NovelChapter> _applyManualChapterTitles(List<NovelChapter> chapters) {
    final titles = _book.manualChapterTitles;
    if (titles.length != chapters.length) return chapters;
    return [
      for (var i = 0; i < chapters.length; i++)
        NovelChapter(
          title: titles[i].trim().isEmpty ? chapters[i].title : titles[i],
          content: chapters[i].content,
        ),
    ];
  }

  Future<void> _summarizeNovel() async {
    if (_content.trim().isEmpty || _isBusy) {
      return;
    }

    final endpoint = _apiConfig.effectiveEndpoint(_selectedEndpointId);
    if (endpoint == null || !endpoint.isComplete) {
      _showSnack('请先到 API 设置添加完整配置。');
      return;
    }

    final cached = _summaryCache;
    final resume = cached != null && cached.canResume
        ? await _askResumeSummary()
        : false;
    if (resume == null) return;

    final chunks = resume
        ? cached.selectedChunks
        : await _chooseSummaryChunks();
    if (chunks == null || chunks.isEmpty || !mounted) return;

    final summaries = resume ? [...cached.completedSummaries] : <String>[];
    var startIndex = resume ? cached.currentIndex : 0;
    if (startIndex > chunks.length) startIndex = chunks.length;
    var cache = resume
        ? cached
        : NovelSummaryCache(
            novelId: _book.id,
            selectedChunkIndexes: [
              for (var index = 0; index < chunks.length; index++) index,
            ],
            selectedChunks: chunks,
            completedSummaries: const [],
            currentIndex: 0,
            endpointId: endpoint.id,
            updatedAt: DateTime.now(),
          );
    final summaryService = NovelSummaryService(widget.storage);
    await summaryService.saveCache(cache);
    _summaryCache = cache;

    if (!mounted) return;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    Future<String> streamText(List<Map<String, String>> messages) async {
      var text = '';
      await for (final chunk in widget.aiService.streamMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: messages,
        cancelToken: cancelToken,
      )) {
        text += chunk;
      }
      if (text.trim().isEmpty) {
        throw AiException('API 没有返回可用回复。');
      }
      return text;
    }

    final useEnglish = context.isEnglish;
    setState(() {
      _isBusy = true;
      _busyText = '准备总结小说';
    });

    try {
      for (var i = startIndex; i < chunks.length; i++) {
        if (!mounted) return;
        setState(() => _busyText = '正在总结 ${i + 1} / ${chunks.length}');
        final summary = await streamText([
          {'role': 'system', 'content': '你是小说分析助手，只提炼原文信息。'},
          {
            'role': 'user',
            'content': PromptBuilder.buildNovelChunkPrompt(
              chunks[i],
              i + 1,
              chunks.length,
            ),
          },
        ]);
        summaries.add(summary);
        cache = cache.copyWith(
          completedSummaries: summaries,
          currentIndex: i + 1,
          updatedAt: DateTime.now(),
        );
        await summaryService.saveCache(cache);
        _summaryCache = cache;
      }

      if (!mounted) return;
      setState(() => _busyText = '正在合并总结并生成角色');
      final merged = await streamText([
        {'role': 'system', 'content': '你只输出可解析 JSON。'},
        {
          'role': 'user',
          'content': PromptBuilder.buildNovelMergePrompt(summaries),
        },
      ]);

      final result = _parseNovelResult(merged);
      final roles = result.roles.isEmpty
          ? [
              NovelRoleCandidate(
                name: useEnglish ? 'Novel role' : '小说角色',
                description: useEnglish
                    ? 'AI could not parse a clear role. Summarize again or chat with this role first.'
                    : 'AI 未能解析出明确角色，可重新总结或先用此角色聊天。',
                personality: useEnglish
                    ? 'Refer to the novel profile.'
                    : '参考小说设定档。',
                speakingStyle: useEnglish
                    ? 'Refer to the original novel text.'
                    : '参考小说原文。',
                background: result.summary,
              ),
            ]
          : result.roles;
      await _saveBook(
        _book.copyWith(
          summary: result.summary,
          roles: roles,
          selectedRoleIndex: 0,
          userRoleIndex: -1,
          isChatMode: true,
        ),
      );
      await summaryService.deleteCache(_book.id);
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _summaryCache = null;
      });
      await _chooseRole();
      _showSnack('小说总结完成');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _showSnack(error.toString());
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  Future<bool?> _askResumeSummary() async {
    final cache = _summaryCache;
    if (cache == null || !cache.canResume) return false;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('继续上次总结')),
        content: Text(
          context.isEnglish
              ? 'Last run finished ${cache.currentIndex} / ${cache.selectedChunks.length} chunks. Continue?'
              : '上次已完成 ${cache.currentIndex} / ${cache.selectedChunks.length} 个片段，是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(context.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('重新开始')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('继续')),
          ),
        ],
      ),
    );
  }

  Future<List<String>?> _chooseSummaryChunks() async {
    if (_chapters.length <= 30) {
      return splitNovelText(_content, 12000);
    }

    final mode = await showDialog<_NovelSummaryMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          context.isEnglish
              ? 'Choose summary mode (${_chapters.length} chapters)'
              : '选择总结方式（共 ${_chapters.length} 章）',
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_NovelSummaryMode.low),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.savings_outlined),
              title: Text(context.t('低成本总结')),
              subtitle: Text(context.t('前 10 章 + 自选多个十章范围')),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_NovelSummaryMode.range),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune),
              title: Text(context.t('自选章节范围总结')),
              subtitle: Text(context.t('只总结一个连续章节范围')),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_NovelSummaryMode.full),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(context.t('全文总结')),
              subtitle: Text(context.t('最完整，费用最高')),
            ),
          ),
        ],
      ),
    );

    switch (mode) {
      case _NovelSummaryMode.low:
        return _showLowCostSummaryDialog();
      case _NovelSummaryMode.range:
        return _showRangeSummaryDialog();
      case _NovelSummaryMode.full:
        return splitNovelText(_content, 12000);
      case null:
        return null;
    }
  }

  Future<List<String>?> _showLowCostSummaryDialog() async {
    final total = _chapters.length;
    final controllers = [
      TextEditingController(
        text: '${((total / 2).floor() - 4).clamp(1, total)}',
      ),
      TextEditingController(text: '${(total - 9).clamp(1, total)}'),
    ];

    final starts = await showDialog<List<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.t('低成本总结')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.isEnglish
                        ? 'Always includes: chapters 1-${10.clamp(1, total)}'
                        : '固定包含：第 1-${10.clamp(1, total)} 章',
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < controllers.length; i++) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controllers[i],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.isEnglish
                                  ? 'Focus range ${i + 1} start chapter'
                                  : '重点范围 ${i + 1} 起始章节',
                              helperText: _rangePreview(controllers[i].text),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        IconButton(
                          tooltip: context.t('删除范围'),
                          onPressed: () {
                            controllers.removeAt(i).dispose();
                            setDialogState(() {});
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () {
                      controllers.add(TextEditingController());
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: Text(context.t('添加范围')),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.isEnglish
                        ? 'Will summarize: first 10 chapters + ${controllers.length} focus ranges, about ${10 + controllers.length * 10} chapters'
                        : '将总结：前 10 章 + ${controllers.length} 个重点范围，约 ${10 + controllers.length * 10} 章',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('取消')),
            ),
            FilledButton(
              onPressed: () {
                final starts = <int>[];
                for (final controller in controllers) {
                  final start = int.tryParse(controller.text.trim());
                  if (start == null || start < 1 || start > total) {
                    _showSnack('起始章节必须在 1-$total 之间');
                    return;
                  }
                  starts.add(start);
                }
                Navigator.of(context).pop(starts);
              },
              child: Text(context.t('开始总结')),
            ),
          ],
        ),
      ),
    );

    for (final controller in controllers) {
      controller.dispose();
    }
    if (starts == null) return null;

    return [
      ..._chapterRangeChunks(1, 10),
      for (final start in starts) ..._chapterRangeChunks(start, 10),
    ];
  }

  Future<List<String>?> _showRangeSummaryDialog() async {
    final total = _chapters.length;
    final startController = TextEditingController(text: '1');
    final endController = TextEditingController(text: '${30.clamp(1, total)}');

    final range = await showDialog<({int start, int end})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.isEnglish
              ? 'Custom chapter range ($total chapters)'
              : '自选章节范围（共 $total 章）',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.t('起始章节')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: endController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.t('结束章节')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final start = int.tryParse(startController.text.trim());
              final end = int.tryParse(endController.text.trim());
              if (start == null ||
                  end == null ||
                  start < 1 ||
                  end > total ||
                  start > end) {
                _showSnack('请输入 1-$total 之间的有效范围');
                return;
              }
              Navigator.of(context).pop((start: start, end: end));
            },
            child: Text(context.t('开始总结')),
          ),
        ],
      ),
    );

    startController.dispose();
    endController.dispose();
    if (range == null) return null;
    return _chapterRangeChunks(range.start, range.end - range.start + 1);
  }

  String _rangePreview(String value) {
    final start = int.tryParse(value.trim());
    if (start == null || _chapters.isEmpty) {
      return context.t('请输入起始章节');
    }
    final safeStart = start.clamp(1, _chapters.length).toInt();
    final end = (safeStart + 9).clamp(1, _chapters.length).toInt();
    return context.isEnglish
        ? 'Actual summary: chapters $safeStart-$end'
        : '实际总结：第 $safeStart-$end 章';
  }

  List<String> _chapterRangeChunks(int startChapter, int count) {
    final indexes = chapterRangeIndexes(_chapters.length, startChapter, count);
    if (indexes.isEmpty) return const [];
    final text = indexes
        .map((index) => _chapters[index])
        .map((chapter) => '【${chapter.title}】\n${chapter.content}')
        .join('\n\n');
    return splitNovelText(text, 12000);
  }

  _NovelAiResult _parseNovelResult(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) {
        throw const FormatException('missing json');
      }
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('bad json');
      }
      final rawRoles = decoded['roles'];
      final roles = rawRoles is List
          ? rawRoles
                .whereType<Map<String, dynamic>>()
                .map(NovelRoleCandidate.fromJson)
                .where((role) => role.name.trim().isNotEmpty)
                .take(5)
                .toList()
          : <NovelRoleCandidate>[];
      return _NovelAiResult(
        summary: decoded['summary'] as String? ?? raw,
        roles: roles,
      );
    } on FormatException {
      return _NovelAiResult(summary: raw, roles: const []);
    }
  }

  Future<void> _chooseRole() async {
    if (_book.roles.isEmpty) {
      _showSnack('还没有角色，请先总结小说。');
      return;
    }

    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.t('选择 AI 扮演的角色')),
        children: [
          for (var i = 0; i < _book.roles.length; i++)
            _roleOption(
              context,
              role: _book.roles[i],
              index: i,
              isSelected: i == _book.selectedRoleIndex,
            ),
        ],
      ),
    );
    if (selected == null) return;
    await _saveBook(_book.copyWith(selectedRoleIndex: selected));
  }

  Future<void> _chooseUserRole() async {
    if (_book.roles.isEmpty) {
      _showSnack('还没有角色，请先总结小说。');
      return;
    }

    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.t('选择你扮演的角色')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(-1),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _book.userRoleIndex < 0
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(context.t('不选择固定角色')),
              subtitle: Text(context.t('聊天时自由扮演自己或临时角色')),
            ),
          ),
          for (var i = 0; i < _book.roles.length; i++)
            _roleOption(
              context,
              role: _book.roles[i],
              index: i,
              isSelected: i == _book.userRoleIndex,
            ),
        ],
      ),
    );
    if (selected == null) return;
    await _saveBook(_book.copyWith(userRoleIndex: selected));
  }

  SimpleDialogOption _roleOption(
    BuildContext dialogContext, {
    required NovelRoleCandidate role,
    required int index,
    required bool isSelected,
  }) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(dialogContext).pop(index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () async {
          final deleted = await _showRoleDetail(role, index);
          if (deleted && dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        },
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          title: Text(role.name),
          subtitle: Text(
            role.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Future<bool> _showRoleDetail(NovelRoleCandidate role, int index) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(role.name),
            content: SingleChildScrollView(
              child: SelectableText(_roleDetailText(role)),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: () async {
                  final navigator = Navigator.of(dialogContext);
                  final deleted = await _deleteNovelRole(role, index);
                  if (!deleted || !mounted) return;
                  navigator.pop(true);
                  _showSnack('已删除角色：${role.name}');
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(context.t('删除')),
              ),
              TextButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(dialogContext);
                  final exported = await _exportRoleToCharacter(role);
                  if (!exported || !mounted) return;
                  navigator.pop();
                  _showSnack('已导出到角色：${role.name}');
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(context.t('导出到角色')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.t('关闭')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _exportRoleToCharacter(NovelRoleCandidate role) async {
    final useEnglish = context.isEnglish;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('导出到角色')),
        content: Text(
          context.isEnglish
              ? 'Export "${role.name}" to the character list? Opening message and extra prompt will be left empty.'
              : '确定把“${role.name}”导出到角色列表吗？开场白和补充设定会留空。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('导出')),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    final now = DateTime.now();
    await widget.storage.saveCharacter(
      AppCharacter(
        id: 'character_${now.microsecondsSinceEpoch}',
        name: role.name.trim().isEmpty
            ? (useEnglish ? 'Novel role' : '小说角色')
            : role.name.trim(),
        avatar: '',
        backgroundImage: '',
        backgroundImageOpacity: 1,
        backgroundBlur: 0,
        bubbleOpacity: 0.92,
        inputOpacity: 0.92,
        description: role.description.trim(),
        personality: role.personality.trim(),
        background: role.background.trim(),
        speakingStyle: role.speakingStyle.trim(),
        openingMessage: '',
        extraPrompt: '',
        defaultProvider: AiProviderX.fromId(_selectedEndpointId),
        defaultEndpointId: _selectedEndpointId,
        sourceType: 'novelExport',
        sourceNovelId: _book.id,
        sourceNovelTitle: _book.title,
        sourceNovelRoleName: role.name,
        createdAt: now,
        updatedAt: now,
        lastUsedAt: now,
      ),
    );
    return true;
  }

  Future<bool> _deleteNovelRole(NovelRoleCandidate role, int index) async {
    if (index < 0 || index >= _book.roles.length) {
      return false;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('删除角色')),
        content: Text(
          context.isEnglish ? 'Delete "${role.name}"?' : '确定删除“${role.name}”吗？',
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
    if (ok != true) return false;

    final roles = [..._book.roles]..removeAt(index);
    await _saveBook(
      _book.copyWith(
        roles: roles,
        selectedRoleIndex: novelRoleIndexAfterDelete(
          selectedIndex: _book.selectedRoleIndex,
          deletedIndex: index,
          newLength: roles.length,
          keepReplacement: true,
        ),
        userRoleIndex: novelRoleIndexAfterDelete(
          selectedIndex: _book.userRoleIndex,
          deletedIndex: index,
          newLength: roles.length,
          keepReplacement: false,
        ),
        isChatMode: roles.isNotEmpty && _book.isChatMode,
      ),
    );
    return true;
  }

  String _roleDetailText(NovelRoleCandidate role) {
    if (context.isEnglish) {
      return '''
Name:
${role.name}

Description:
${role.description}

Personality:
${role.personality}

Backstory:
${role.background}

Speaking style:
${role.speakingStyle}
'''
          .trim();
    }
    return '''
名称：
${role.name}

简介：
${role.description}

性格：
${role.personality}

背景故事：
${role.background}

说话风格：
${role.speakingStyle}
'''
        .trim();
  }

  Future<void> _showSettings() async {
    var endpointId = _selectedEndpointId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              shrinkWrap: true,
              children: [
                Text(
                  context.t('小说设置'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.memory),
                  title: Text(context.t('总结和聊天模型')),
                  subtitle: _apiConfig.enabledEndpoints.isEmpty
                      ? Text(context.t('请先添加 API 配置'))
                      : DropdownButton<String>(
                          value:
                              _apiConfig.enabledEndpoints.any(
                                (endpoint) => endpoint.id == endpointId,
                              )
                              ? endpointId
                              : null,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final endpoint in _apiConfig.enabledEndpoints)
                              DropdownMenuItem(
                                value: endpoint.id,
                                child: Text(endpoint.name),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => endpointId = value);
                            setState(() => _selectedEndpointId = value);
                          },
                        ),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.view_agenda_outlined),
                  title: Text(context.t('按章节阅读')),
                  subtitle: Text(
                    _chapters.isEmpty
                        ? context.t('小说正文为空')
                        : context.t('目录 ${_chapters.length} 条'),
                  ),
                  value: _book.readingMode == 1 && _chapters.isNotEmpty,
                  onChanged: _chapters.isEmpty
                      ? null
                      : (value) async {
                          await _saveBook(
                            _book.copyWith(
                              readingMode: value ? 1 : 0,
                              chapterIndex: 0,
                            ),
                          );
                          if (mounted) {
                            setSheetState(() {});
                          }
                        },
                ),
                if (_chapters.isNotEmpty && _book.readingMode == 1)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.format_list_numbered),
                    title: Text(context.t('目录')),
                    subtitle: Text(_chapters[_safeChapterIndex].title),
                    onTap: () {
                      Navigator.of(context).pop();
                      _chooseChapter();
                    },
                  ),
                if (_chapters.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.edit_note_outlined),
                    title: Text(context.t('编辑目录')),
                    subtitle: Text(context.t('每行一个章节标题')),
                    onTap: () {
                      Navigator.of(context).pop();
                      _editCatalog();
                    },
                  ),
                _readerSlider(
                  label: '阅读字体大小',
                  value: _book.fontSize,
                  min: 14,
                  max: 28,
                  divisions: 14,
                  display: _book.fontSize.toStringAsFixed(0),
                  onChanged: (value) {
                    setState(() => _book = _book.copyWith(fontSize: value));
                    setSheetState(() {});
                  },
                  onChangeEnd: (value) {
                    unawaited(_saveBook(_book.copyWith(fontSize: value)));
                  },
                ),
                _readerSlider(
                  label: '阅读行距',
                  value: _book.lineHeight,
                  min: 1.2,
                  max: 2.2,
                  divisions: 10,
                  display: _book.lineHeight.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() => _book = _book.copyWith(lineHeight: value));
                    setSheetState(() {});
                  },
                  onChangeEnd: (value) {
                    unawaited(_saveBook(_book.copyWith(lineHeight: value)));
                  },
                ),
                _readerThemePicker(setSheetState),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.swap_horiz),
                  title: Text(context.t('聊天模式')),
                  subtitle: Text(
                    _book.selectedRole == null
                        ? context.t('需要先总结小说并选择角色')
                        : context.t('在小说内聊天'),
                  ),
                  value: _book.isChatMode && _book.selectedRole != null,
                  onChanged: _book.selectedRole == null
                      ? null
                      : (value) async {
                          final navigator = Navigator.of(context);
                          await _saveBook(_book.copyWith(isChatMode: value));
                          if (mounted) navigator.pop();
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(context.t('总结小说并生成角色')),
                  subtitle: Text(
                    context.t(_book.summary.isEmpty ? '首次生成' : '重新生成'),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _summarizeNovel();
                  },
                ),
                if (_book.roles.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_search),
                    title: Text(context.t('选择 AI 角色')),
                    subtitle: Text(
                      _book.selectedRole?.name ?? context.t('未选择'),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _chooseRole();
                    },
                  ),
                if (_book.roles.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(context.t('选择用户角色')),
                    subtitle: Text(
                      _book.selectedUserRole?.name ?? context.t('不选择固定角色'),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _chooseUserRole();
                    },
                  ),
                if (_book.summary.trim().isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.article_outlined),
                    title: Text(context.t('查看小说设定档')),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showSummaryDialog();
                    },
                  ),
                if (_summaryCache?.canResume == true)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore_page_outlined),
                    title: Text(context.t('继续上次总结')),
                    subtitle: Text(
                      context.isEnglish
                          ? '${_summaryCache!.currentIndex} / ${_summaryCache!.selectedChunks.length} chunks completed'
                          : '已完成 ${_summaryCache!.currentIndex} / ${_summaryCache!.selectedChunks.length} 个片段',
                    ),
                    trailing: IconButton(
                      tooltip: context.t('清理总结缓存'),
                      onPressed: () async {
                        await NovelSummaryService(
                          widget.storage,
                        ).deleteCache(_book.id);
                        if (!mounted) return;
                        setState(() => _summaryCache = null);
                        setSheetState(() {});
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _summarizeNovel();
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
                    context.t('清空小说聊天'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _clearNovelChat();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSummaryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('小说设定档')),
        content: SingleChildScrollView(child: SelectableText(_book.summary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('关闭')),
          ),
        ],
      ),
    );
  }

  Widget _readerSlider({
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
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
            SizedBox(width: 48, child: Text(display, textAlign: TextAlign.end)),
          ],
        ),
      ),
    );
  }

  Widget _readerThemePicker(StateSetter setSheetState) {
    const items = [(0, '默认'), (1, '纸白'), (2, '护眼'), (3, '夜间')];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          labelText: context.t('阅读背景'),
        ),
        child: Wrap(
          spacing: 8,
          children: [
            for (final item in items)
              ChoiceChip(
                label: Text(context.t(item.$2)),
                selected: _book.readerTheme == item.$1,
                onSelected: (_) {
                  final next = _book.copyWith(readerTheme: item.$1);
                  setState(() => _book = next);
                  setSheetState(() {});
                  unawaited(_saveBook(next));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCatalog() async {
    if (_chapters.isEmpty) return;
    final controller = TextEditingController(
      text: _chapters.map((chapter) => chapter.title).join('\n'),
    );
    final titles = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('编辑目录')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 12,
            maxLines: 18,
            decoration: InputDecoration(helperText: context.t('每行一个章节标题')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(const <String>[]),
            child: Text(context.t('重置')),
          ),
          FilledButton(
            onPressed: () {
              final lines = controller.text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
              if (lines.length != _chapters.length) {
                _showSnack('目录行数必须和当前章节数一致');
                return;
              }
              Navigator.of(context).pop(lines);
            },
            child: Text(context.t('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (titles == null) return;
    final next = _book.copyWith(manualChapterTitles: titles);
    await _saveBook(next);
    if (!mounted) return;
    setState(() {
      _book = next;
      _chapters = _applyManualChapterTitles(buildNovelChapters(_content));
    });
  }

  Future<void> _clearNovelChat() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('清空小说聊天')),
        content: Text(context.t('确定清空这本小说里的聊天记录吗？小说正文和总结不会被删除。')),
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
    await widget.storage.clearNovelChat(_book.id);
    if (!mounted) return;
    setState(() => _messages = []);
    _showSnack('小说聊天已清空');
  }

  Future<void> _sendNovelMessage() async {
    final text = _inputController.text.trim();
    final role = _book.selectedRole;
    if (text.isEmpty || _isSending || role == null) {
      return;
    }

    final endpoint = _apiConfig.effectiveEndpoint(_selectedEndpointId);
    if (endpoint == null || !endpoint.isComplete) {
      _showSnack('请先到 API 设置添加完整配置。');
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
    _scrollChatToEnd();
    await widget.storage.saveNovelChat(_book.id, _messages);

    final requestMessages = [
      {
        'role': 'system',
        'content': PromptBuilder.buildNovelChatSystemPrompt(
          _book,
          role,
          _book.selectedUserRole,
        ),
      },
      for (final message
          in _messages.length > 30
              ? _messages.sublist(_messages.length - 30)
              : _messages)
        if (message.isUser || message.isAssistant)
          {'role': message.role, 'content': message.content},
    ];
    final assistantMessage = ChatMessage(
      role: 'assistant',
      content: '',
      time: DateTime.now(),
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      model: endpoint.model,
    );
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    try {
      final streamResponses = widget.settings.streamResponses;
      if (streamResponses) {
        setState(() => _messages = [..._messages, assistantMessage]);
      }

      var reply = '';
      await for (final chunk in widget.aiService.streamMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: requestMessages,
        cancelToken: cancelToken,
        includeReasoning: widget.settings.showReasoningContent,
      )) {
        if (!mounted) return;
        reply += chunk;
        if (streamResponses) {
          setState(() {
            _messages = [
              ..._messages.take(_messages.length - 1),
              assistantMessage.copyWith(content: reply),
            ];
          });
        }
      }
      if (reply.trim().isEmpty) {
        throw AiException('API 没有返回可用回复。');
      }
      if (!mounted) return;
      setState(() {
        final finalMessage = assistantMessage.copyWith(content: reply);
        _messages = streamResponses
            ? [..._messages.take(_messages.length - 1), finalMessage]
            : [..._messages, finalMessage];
        _isSending = false;
      });
      await widget.storage.saveNovelChat(_book.id, _messages);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dropEmptyAssistantTail();
        _isSending = false;
      });
      _showSnack(error.toString());
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  void _dropEmptyAssistantTail() {
    if (_messages.isNotEmpty &&
        _messages.last.isAssistant &&
        _messages.last.content.trim().isEmpty) {
      _messages = _messages.sublist(0, _messages.length - 1);
    }
  }

  int get _safeChapterIndex {
    if (_chapters.isEmpty) {
      return 0;
    }
    return _book.chapterIndex.clamp(0, _chapters.length - 1).toInt();
  }

  Future<void> _setChapter(int index) async {
    if (_chapters.isEmpty) {
      return;
    }
    await _saveBook(
      _book.copyWith(
        chapterIndex: index.clamp(0, _chapters.length - 1).toInt(),
      ),
    );
    if (_readScrollController.hasClients) {
      _readScrollController.jumpTo(0);
    }
    setState(() => _readProgress = 0);
  }

  Future<void> _chooseChapter() async {
    if (_chapters.isEmpty) {
      _showSnack('小说正文为空');
      return;
    }

    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.t('目录')),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 420,
            child: ListView.builder(
              itemCount: _chapters.length,
              itemBuilder: (context, index) => ListTile(
                selected: index == _safeChapterIndex,
                title: Text(
                  _chapters[index].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _book.bookmarkedChapterIndexes.contains(index)
                    ? const Icon(Icons.bookmark)
                    : null,
                onTap: () => Navigator.of(context).pop(index),
              ),
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await _setChapter(selected);
  }

  bool get _isCurrentChapterBookmarked =>
      _book.bookmarkedChapterIndexes.contains(_safeChapterIndex);

  Future<void> _toggleBookmark() async {
    if (_chapters.isEmpty) return;
    final bookmarks = _book.bookmarkedChapterIndexes.toSet();
    if (!bookmarks.remove(_safeChapterIndex)) {
      bookmarks.add(_safeChapterIndex);
    }
    final next = bookmarks.toList()..sort();
    await _saveBook(_book.copyWith(bookmarkedChapterIndexes: next));
  }

  Future<void> _showReaderSearchDialog() async {
    final controller = TextEditingController(text: _readerSearchQuery);
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('搜索正文')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: context.t('输入关键词'),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(context.t('清除')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(context.t('搜索')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null) return;
    setState(() => _readerSearchQuery = query);
    if (query.isEmpty) return;

    final lower = query.toLowerCase();
    if (_book.readingMode == 1 && _chapters.isNotEmpty) {
      final index = _chapters.indexWhere(
        (chapter) =>
            chapter.title.toLowerCase().contains(lower) ||
            chapter.content.toLowerCase().contains(lower),
      );
      if (index >= 0) {
        await _setChapter(index);
        return;
      }
    } else {
      final index = _readChunks.indexWhere(
        (chunk) => chunk.toLowerCase().contains(lower),
      );
      if (index >= 0 && _readScrollController.hasClients) {
        final max = _readScrollController.position.maxScrollExtent;
        _readScrollController.animateTo(
          (index * 260.0).clamp(0, max).toDouble(),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      }
    }
    _showSnack('没有找到匹配内容');
  }

  void _updateReadProgress() {
    if (!_readScrollController.hasClients) return;
    final position = _readScrollController.position;
    final max = position.maxScrollExtent;
    final next = max <= 0
        ? 1.0
        : (position.pixels / max).clamp(0, 1).toDouble();
    if ((next - _readProgress).abs() > 0.01 && mounted) {
      setState(() => _readProgress = next);
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  bool get _showNovelTypingBubble =>
      _isSending && (_messages.isEmpty || !_messages.last.isAssistant);

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(message))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_book.title),
        actions: [
          IconButton(
            tooltip: context.t('小说设置'),
            onPressed: _showSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_isBusy)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.28),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(context.t(_busyText)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(context.t(_error!), textAlign: TextAlign.center),
      );
    }
    if (_book.isChatMode && _book.selectedRole != null) {
      return _buildChatMode();
    }
    return _buildReadMode();
  }

  Widget _buildReadMode() {
    final useChapterMode = _book.readingMode == 1 && _chapters.isNotEmpty;
    final chunks = useChapterMode
        ? splitNovelText(_chapters[_safeChapterIndex].content, 1600)
        : _readChunks;
    if (chunks.isEmpty) {
      return Center(child: Text(context.t('小说正文为空')));
    }
    final colors = _readerColors(context);
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: _book.fontSize,
      height: _book.lineHeight,
      color: colors.text,
    );
    final title = useChapterMode
        ? '${_safeChapterIndex + 1}/${_chapters.length} · ${_chapters[_safeChapterIndex].title}'
        : '${context.t('阅读进度')} ${(_readProgress * 100).round()}%';
    return ColoredBox(
      color: colors.background,
      child: Column(
        children: [
          Material(
            color: colors.bar,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  if (useChapterMode)
                    IconButton(
                      tooltip: context.t('上一章'),
                      onPressed: _safeChapterIndex == 0
                          ? null
                          : () => _setChapter(_safeChapterIndex - 1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  Expanded(
                    child: TextButton(
                      onPressed: useChapterMode ? _chooseChapter : null,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('搜索正文'),
                    onPressed: _showReaderSearchDialog,
                    icon: const Icon(Icons.search),
                  ),
                  if (useChapterMode)
                    IconButton(
                      tooltip: context.t('书签'),
                      onPressed: _toggleBookmark,
                      icon: Icon(
                        _isCurrentChapterBookmarked
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                      ),
                    ),
                  if (useChapterMode)
                    IconButton(
                      tooltip: context.t('下一章'),
                      onPressed: _safeChapterIndex >= _chapters.length - 1
                          ? null
                          : () => _setChapter(_safeChapterIndex + 1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: ValueKey(
                useChapterMode ? 'chapter-$_safeChapterIndex' : 'continuous',
              ),
              controller: _readScrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: chunks.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ReaderText(
                  text: chunks[index],
                  style: textStyle,
                  highlightQuery: _readerSearchQuery,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({Color background, Color text, Color bar}) _readerColors(
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (_book.readerTheme) {
      1 => (
        background: const Color(0xFFFFFCF4),
        text: const Color(0xFF222222),
        bar: const Color(0xFFF6EEDC),
      ),
      2 => (
        background: const Color(0xFFF1F5E8),
        text: const Color(0xFF1F2A1F),
        bar: const Color(0xFFE2EAD6),
      ),
      3 => (
        background: const Color(0xFF101214),
        text: const Color(0xFFE7E4DC),
        bar: const Color(0xFF1A1D21),
      ),
      _ => (
        background: scheme.surface,
        text: scheme.onSurface,
        bar: scheme.surfaceContainerHighest,
      ),
    };
  }

  Widget _buildChatMode() {
    return _NovelChatBackground(
      imagePath: _book.chatBackgroundImage,
      opacity: _book.chatBackgroundOpacity,
      blur: _book.chatBackgroundBlur,
      child: Column(
        children: [
          Material(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.theater_comedy_outlined),
              title: Text(
                context.isEnglish
                    ? 'AI role: ${_book.selectedRole!.name}'
                    : 'AI 扮演：${_book.selectedRole!.name}',
              ),
              subtitle: Text(
                context.isEnglish
                    ? 'You: ${_book.selectedUserRole?.name ?? 'Not set'} · ${_apiConfig.endpointById(_selectedEndpointId)?.name ?? 'No API'}'
                    : '你：${_book.selectedUserRole?.name ?? '未指定'} · ${_apiConfig.endpointById(_selectedEndpointId)?.name ?? '未配置 API'}',
              ),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Text(context.t('开始小说内聊天吧。')))
                : AdaptivePage(
                    child: ListView.builder(
                      controller: _chatScrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                      itemCount:
                          _messages.length + (_showNovelTypingBubble ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_showNovelTypingBubble && index == 0) {
                          return _NovelBubble(
                            text: context.t('生成中'),
                            isUser: false,
                          );
                        }
                        final messageIndex =
                            _messages.length -
                            1 -
                            (index - (_showNovelTypingBubble ? 1 : 0));
                        final message = _messages[messageIndex];
                        return _NovelBubble(
                          text: message.content,
                          isUser: message.isUser,
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: responsiveMaxContentWidth(
                    MediaQuery.sizeOf(context).width,
                  ),
                ),
                child: Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.92),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText: context.t('输入消息'),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: context.t('发送'),
                          onPressed: _isSending ? null : _sendNovelMessage,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NovelAiResult {
  const _NovelAiResult({required this.summary, required this.roles});

  final String summary;
  final List<NovelRoleCandidate> roles;
}

class _ReaderText extends StatelessWidget {
  const _ReaderText({
    required this.text,
    required this.style,
    required this.highlightQuery,
  });

  final String text;
  final TextStyle? style;
  final String highlightQuery;

  @override
  Widget build(BuildContext context) {
    final query = highlightQuery.trim();
    if (query.isEmpty) {
      return SelectableText(text, style: style);
    }
    final matches = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.isEmpty) {
      return SelectableText(text, style: style);
    }

    final highlightStyle = style?.copyWith(
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      color: Theme.of(context).colorScheme.onTertiaryContainer,
    );
    var cursor = 0;
    final spans = <TextSpan>[];
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: highlightStyle,
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}

class _NovelChatBackground extends StatelessWidget {
  const _NovelChatBackground({
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
    if (path.isEmpty) {
      return child;
    }

    final file = File(path);
    final alpha = opacity.clamp(0, 1).toDouble();
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
            color: Colors.black.withValues(alpha: 0.16 * alpha),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _NovelBubble extends StatelessWidget {
  const _NovelBubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = isCompactWidth(screenWidth)
        ? screenWidth * 0.82
        : 760.0;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: MessageContent(text: text),
        ),
      ),
    );
  }
}
