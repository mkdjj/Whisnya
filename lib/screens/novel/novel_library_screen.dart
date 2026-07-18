part of 'novel_screens.dart';

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
    unawaited(_load());
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
      context.showSnack(error.toString());
    }
  }

  Future<String> _decodePickedNovel(List<int> bytes) async {
    try {
      return const NovelImportService().decode(bytes).text;
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
      return const NovelImportService().decode(bytes, encoding: encoding).text;
    }
  }

  Future<void> _openBook(NovelBook book) async {
    if (!await _verifyBookOperation(book, '打开小说')) {
      return;
    }
    if (!mounted) return;
    final opened = book.copyWith(lastOpenedAt: DateTime.now());
    await widget.storage.saveNovel(opened);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NovelReaderScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          settings: widget.settings,
          book: opened,
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
    context.showSnack(book.isHidden ? '已显示设定' : '已隐藏设定');
    await _load();
  }

  Future<void> _toggleBookLock(NovelBook book) async {
    if (!book.isLocked && !widget.settings.hasPrivacyPassword) {
      context.showSnack('请先到设置里设置隐私密码');
      return;
    }
    if (book.isLocked && !await _verifyBookOperation(book, '解除上锁')) {
      return;
    }
    await widget.storage.saveNovel(
      book.copyWith(isLocked: !book.isLocked, updatedAt: DateTime.now()),
    );
    if (!mounted) return;
    context.showSnack(book.isLocked ? '已解除上锁' : '已上锁');
    await _load();
  }

  Future<bool> _verifyBookOperation(NovelBook book, String title) async {
    if (!book.isLocked) {
      return true;
    }
    return _verifyPassword(title);
  }

  Future<bool> _verifyPassword(String title) async {
    return verifyPrivacyPassword(
      context: context,
      settings: widget.settings,
      storage: widget.storage,
      title: title,
    );
  }

  Future<void> _deleteBook(NovelBook book) async {
    if (!await _verifyBookOperation(book, '删除小说')) {
      return;
    }
    if (!mounted) return;

    final shouldDelete = await showConfirmDialog(
      context: context,
      title: '删除小说',
      content: context.isEnglish
          ? 'Delete "${book.title}"? Novel chats will also be deleted.'
          : '确定删除《${book.title}》吗？小说内聊天也会一起删除。',
      confirmLabel: '删除',
    );
    if (!shouldDelete) return;

    await widget.storage.deleteNovel(book);
    if (!mounted) return;
    context.showSnack('已删除小说');
    await _load();
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
            unawaited(_toggleBookHidden(book));
            break;
          case _NovelAction.lock:
            unawaited(_toggleBookLock(book));
            break;
          case _NovelAction.delete:
            unawaited(_deleteBook(book));
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
