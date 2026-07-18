part of 'novel_screens.dart';

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
  final _readScrollController = ScrollController();

  late final NovelReaderController _reader;
  NovelBook get _book => _reader.book;
  List<String> get _readChunks => _reader.readChunks;
  List<NovelChapter> get _chapters => _reader.chapters;
  String get _readerSearchQuery => _reader.searchQuery;
  double get _readProgress => _reader.readProgress;
  var _apiConfig = ApiConfig();
  var _selectedEndpointId = '';
  var _content = '';
  NovelSummaryCache? _summaryCache;
  var _isLoading = true;
  var _isBusy = false;
  var _busyText = '';
  AiCancelToken? _cancelToken;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reader = NovelReaderController(widget.book);
    _readScrollController.addListener(_updateReadProgress);
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _readScrollController.dispose();
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
      final summaryCache = await NovelSummaryService(
        widget.storage,
      ).loadCache(_book.id);
      if (!mounted) return;
      setState(() {
        _apiConfig = apiConfig;
        _selectedEndpointId =
            apiConfig.effectiveEndpoint(_selectedEndpointId)?.id ?? '';
        _content = content;
        _reader.load(
          readChunks: splitNovelText(content, 1600),
          chapters: _applyManualChapterTitles(buildNovelChapters(content)),
        );
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
    setState(() => _reader.updateBook(next));
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
      context.showSnack('请先到 API 设置添加完整配置。');
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
        onUsage: (usage) => unawaited(
          widget.storage.recordAiUsage(
            requestType: 'novelSummary',
            model: endpoint.model,
            usage: usage,
            messages: messages,
            summaryUpdated: true,
          ),
        ),
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
                    ? 'AI could not parse a clear role. Summarize again to retry.'
                    : 'AI 未能解析出明确角色，可重新总结后再试。',
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
      await _saveBook(_book.copyWith(summary: result.summary, roles: roles));
      await summaryService.deleteCache(_book.id);
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _summaryCache = null;
      });
      context.showSnack('小说总结完成');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      context.showSnack(error.toString());
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
                    context.showSnack('起始章节必须在 1-$total 之间');
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
                context.showSnack('请输入 1-$total 之间的有效范围');
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

  ({String summary, List<NovelRoleCandidate> roles}) _parseNovelResult(
    String raw,
  ) {
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
      return (summary: decoded['summary'] as String? ?? raw, roles: roles);
    } on FormatException {
      return (summary: raw, roles: const []);
    }
  }

  Future<void> _manageRoles() async {
    if (_book.roles.isEmpty) {
      context.showSnack('还没有角色，请先总结小说。');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('小说角色')),
        content: SizedBox(
          width: 520,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _book.roles.length,
            itemBuilder: (context, index) {
              final role = _book.roles[index];
              return ListTile(
                title: Text(role.name),
                subtitle: Text(
                  role.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final deleted = await _showRoleDetail(role, index);
                  if (deleted && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.t('关闭')),
          ),
        ],
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
                  context.showSnack('已删除角色：${role.name}');
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
                  context.showSnack('已导出到角色：${role.name}');
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
        inputOpacity: 0.92,
        description: role.description.trim(),
        personality: role.personality.trim(),
        background: role.background.trim(),
        speakingStyle: role.speakingStyle.trim(),
        openingMessage: '',
        extraPrompt: '',
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
    await _saveBook(_book.copyWith(roles: roles));
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

  Future<void> _createNovelTheater() async {
    TheaterSession? draft;
    while (draft == null) {
      if (!mounted) return;
      final choice = await showNovelTheaterIdentityPicker(context);
      if (choice == null || !mounted) return;
      switch (choice) {
        case NovelTheaterIdentityChoice.defaultProfile:
          final profile = (await widget.storage.loadSettings()).userProfile;
          draft = const NovelTheaterFactory().createDraftFromNovel(
            _book,
            userProfile: profile,
          );
        case NovelTheaterIdentityChoice.novelRole:
          final role = await showDialog<NovelRoleCandidate>(
            context: context,
            builder: (context) => SimpleDialog(
              title: Text(context.t('扮演小说角色')),
              children: [
                for (final role in _book.roles)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(role),
                    child: ListTile(
                      title: Text(role.name),
                      subtitle: role.description.trim().isEmpty
                          ? null
                          : Text(role.description),
                    ),
                  ),
              ],
            ),
          );
          if (role != null) {
            draft = const NovelTheaterFactory().createDraftFromNovel(
              _book,
              userRole: role,
            );
          }
        case NovelTheaterIdentityChoice.temporary:
          final profile = await Navigator.of(context).push<UserProfile>(
            MaterialPageRoute(
              builder: (_) => UserProfileEditScreen(
                storage: widget.storage,
                profile: const UserProfile(),
                title: '自定义临时身份',
              ),
            ),
          );
          if (profile != null) {
            draft = const NovelTheaterFactory().createDraftFromNovel(
              _book,
              userProfile: profile,
            );
          }
      }
    }
    if (!mounted) return;
    final session = await Navigator.of(context).push<TheaterSession>(
      MaterialPageRoute(
        builder: (_) => TheaterEditScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          session: draft,
        ),
      ),
    );
    if (session != null && mounted) {
      context.showSnack('小说群聊已创建');
    }
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
                  title: Text(context.t('当前模型')),
                  subtitle: Text(
                    _apiConfig.endpointById(endpointId)?.name ??
                        context.t('请先添加 API 配置'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _apiConfig.enabledEndpoints.isEmpty
                      ? null
                      : () async {
                          final value = await showEndpointPicker(
                            context: context,
                            endpoints: _apiConfig.enabledEndpoints,
                            selectedId: endpointId,
                          );
                          if (value == null || !mounted) return;
                          setSheetState(() => endpointId = value);
                          setState(() => _selectedEndpointId = value);
                        },
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
                      unawaited(_chooseChapter());
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
                      unawaited(_editCatalog());
                    },
                  ),
                SettingSlider(
                  label: '阅读字体大小',
                  value: _book.fontSize,
                  min: 14,
                  max: 28,
                  divisions: 14,
                  display: _book.fontSize.toStringAsFixed(0),
                  onChanged: (value) {
                    setState(
                      () => _reader.updateBook(_book.copyWith(fontSize: value)),
                    );
                    setSheetState(() {});
                  },
                  onChangeEnd: (value) {
                    unawaited(_saveBook(_book.copyWith(fontSize: value)));
                  },
                ),
                SettingSlider(
                  label: '阅读行距',
                  value: _book.lineHeight,
                  min: 1.2,
                  max: 2.2,
                  divisions: 10,
                  display: _book.lineHeight.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(
                      () =>
                          _reader.updateBook(_book.copyWith(lineHeight: value)),
                    );
                    setSheetState(() {});
                  },
                  onChangeEnd: (value) {
                    unawaited(_saveBook(_book.copyWith(lineHeight: value)));
                  },
                ),
                _readerThemePicker(setSheetState),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(context.t('总结小说并生成角色')),
                  subtitle: Text(
                    context.t(_book.summary.isEmpty ? '首次生成' : '重新生成'),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_summarizeNovel());
                  },
                ),
                if (_book.roles.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.people_outline),
                    title: Text(context.t('管理小说角色')),
                    subtitle: Text(context.t('共 ${_book.roles.length} 个角色')),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_manageRoles());
                    },
                  ),
                if (_book.roles.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(context.t('创建小说群聊')),
                    subtitle: Text(context.t('导入全部小说角色并配置群聊')),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_createNovelTheater());
                    },
                  ),
                if (_book.summary.trim().isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.article_outlined),
                    title: Text(context.t('查看小说设定档')),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_showSummaryDialog());
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
                      unawaited(_summarizeNovel());
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
                  setState(() => _reader.updateBook(next));
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
                context.showSnack('目录行数必须和当前章节数一致');
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
      _reader.replaceChapters(
        _applyManualChapterTitles(buildNovelChapters(_content)),
      );
    });
  }

  int get _safeChapterIndex => _reader.safeChapterIndex;

  Future<void> _setChapter(int index) async {
    if (_chapters.isEmpty) {
      return;
    }
    await _saveBook(_reader.bookForChapter(index));
    if (_readScrollController.hasClients) {
      _readScrollController.jumpTo(0);
    }
    setState(_reader.resetReadProgress);
  }

  Future<void> _chooseChapter() async {
    if (_chapters.isEmpty) {
      context.showSnack('小说正文为空');
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

  bool get _isCurrentChapterBookmarked => _reader.isCurrentChapterBookmarked;

  Future<void> _toggleBookmark() async {
    if (_chapters.isEmpty) return;
    await _saveBook(_reader.bookWithToggledCurrentBookmark());
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
    if (!mounted) return;
    if (query == null) return;
    late NovelReaderSearchResult result;
    setState(() => result = _reader.search(query));
    switch (result.target) {
      case NovelReaderSearchTarget.cleared:
        return;
      case NovelReaderSearchTarget.chapter:
        await _setChapter(result.index);
        return;
      case NovelReaderSearchTarget.chunk:
        if (_readScrollController.hasClients) {
          final max = _readScrollController.position.maxScrollExtent;
          unawaited(
            _readScrollController.animateTo(
              (result.index * 260.0).clamp(0, max).toDouble(),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            ),
          );
        }
        return;
      case NovelReaderSearchTarget.notFound:
        context.showSnack('没有找到匹配内容');
    }
  }

  void _updateReadProgress() {
    if (!_readScrollController.hasClients) return;
    final position = _readScrollController.position;
    final changed = _reader.updateReadProgress(
      pixels: position.pixels,
      maxExtent: position.maxScrollExtent,
    );
    if (changed && mounted) {
      setState(() {});
    }
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
}
