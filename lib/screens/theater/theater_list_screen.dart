part of 'theater_screens.dart';

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
    unawaited(_load());
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
          initialUserProfile: widget.settings.userProfile,
        ),
      ),
    );
    if (session == null || !mounted) return;
    await _open(session);
  }

  Future<void> _open(TheaterSession session) async {
    if (!await _verifySessionOperation(session, '进入聊天')) return;
    if (!mounted) return;
    final opened = session.copyWith(lastOpenedAt: DateTime.now());
    await widget.storage.saveTheaterSession(opened);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TheaterChatScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          settings: widget.settings,
          session: opened,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _rename(TheaterSession session) async {
    if (!await _verifySessionOperation(session, '重命名')) return;
    if (!mounted) return;
    final title = await showTextInputDialog(
      context: context,
      title: '重命名群聊',
      initialText: session.title,
      label: '群聊名称',
      confirmLabel: '保存',
    );
    if (title == null || title.isEmpty) return;
    await widget.storage.saveTheaterSession(
      session.copyWith(title: title, updatedAt: DateTime.now()),
    );
    await _load();
  }

  Future<void> _edit(TheaterSession session) async {
    if (!await _verifySessionOperation(session, '编辑群聊')) return;
    if (!mounted) return;
    final updated = await Navigator.of(context).push<TheaterSession>(
      MaterialPageRoute(
        builder: (_) => TheaterEditScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          session: session,
        ),
      ),
    );
    if (updated != null && mounted) await _load();
  }

  Future<void> _delete(TheaterSession session) async {
    if (!await _verifySessionOperation(session, '删除群聊')) return;
    if (!mounted) return;
    final ok = await showConfirmDialog(
      context: context,
      title: '删除群聊',
      content: context.isEnglish
          ? 'Delete "${session.title}"? Messages will also be deleted.'
          : '确定删除“${session.title}”吗？消息也会一起删除。',
      confirmLabel: '删除',
    );
    if (!ok) return;
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
    context.showSnack(session.isHidden ? '已显示设定' : '已隐藏设定');
    await _load();
  }

  Future<void> _toggleLock(TheaterSession session) async {
    if (!session.isLocked && !widget.settings.hasPrivacyPassword) {
      context.showSnack('请先到设置里设置隐私密码');
      return;
    }
    if (session.isLocked && !await _verifySessionOperation(session, '解除上锁')) {
      return;
    }
    await widget.storage.saveTheaterSession(
      session.copyWith(isLocked: !session.isLocked, updatedAt: DateTime.now()),
    );
    if (!mounted) return;
    context.showSnack(session.isLocked ? '已解除上锁' : '已上锁');
    await _load();
  }

  Future<bool> _verifySessionOperation(
    TheaterSession session,
    String title,
  ) async {
    if (!session.isLocked) return true;
    return verifyPrivacyPassword(
      context: context,
      settings: widget.settings,
      storage: widget.storage,
      title: title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardOpacity = widget.settings.characterListCardOpacity
        .clamp(0, 1)
        .toDouble();
    final cardColor = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: cardOpacity);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return PageStatusView.error(message: _error!, onRetry: _load);
    }

    final content = _sessions.isEmpty
        ? PageStatusView.empty(
            icon: Icons.forum_outlined,
            message: context.t('还没有群聊'),
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
                key: ValueKey('theater-card-${session.id}'),
                margin: EdgeInsets.zero,
                color: cardColor,
                surfaceTintColor: Colors.transparent,
                elevation: cardOpacity == 0 ? 0 : cardOpacity,
                shadowColor: Colors.black.withValues(alpha: 0.22 * cardOpacity),
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
                      if (value == 'edit') unawaited(_edit(session));
                      if (value == 'rename') unawaited(_rename(session));
                      if (value == 'hide') unawaited(_toggleHidden(session));
                      if (value == 'lock') unawaited(_toggleLock(session));
                      if (value == 'delete') unawaited(_delete(session));
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: const Icon(Icons.tune),
                          title: Text(context.t('编辑群聊')),
                        ),
                      ),
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
