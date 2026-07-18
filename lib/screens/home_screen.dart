import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';
import '../utils/character_import_flow.dart';
import '../utils/confirm_dialog.dart';
import '../utils/page_layout.dart';
import '../utils/privacy_password_prompt.dart';
import '../utils/snack.dart';
import '../widgets/app_background.dart';
import 'character_edit_screen.dart';
import 'chat/chat_screen.dart';
import 'novel/novel_screens.dart';
import 'settings_screen.dart';
import 'theater/theater_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    required this.onSettingsChanged,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final AppSettings settings;
  final Future<void> Function() onSettingsChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _novelKey = GlobalKey<NovelScreenState>();
  final _theaterKey = GlobalKey<TheaterListScreenState>();

  var _isLoading = true;
  var _tabIndex = 0;
  final _visitedTabs = <int>{0};
  var _novelGridView = false;
  String? _error;
  List<AppCharacter> _characters = const [];

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
      await widget.storage.ensureReady();
      final characters = await widget.storage.loadCharacters();
      final recoveryMessages = widget.storage.takeRecoveryMessages();
      if (!mounted) return;
      setState(() {
        _characters = characters;
        _isLoading = false;
      });
      if (recoveryMessages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.showSnack(recoveryMessages.join('\n'));
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _editCharacter([AppCharacter? character]) async {
    if (character != null &&
        !await _verifyCharacterOperation(character, '编辑角色')) {
      return;
    }
    if (!mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CharacterEditScreen(storage: widget.storage, character: character),
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _importCharacters() async {
    final changed = await showCharacterImportFlow(
      context: context,
      storage: widget.storage,
    );
    if (changed) {
      await _load();
    }
  }

  Future<void> _openChat(AppCharacter character) async {
    if (!await _verifyCharacterOperation(character, '进入聊天')) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          character: character,
          settings: widget.settings,
        ),
      ),
    );
    await _load();
  }

  Future<void> _togglePin(AppCharacter character) async {
    if (!await _verifyCharacterOperation(
      character,
      character.isPinned ? '取消置顶' : '置顶角色',
    )) {
      return;
    }

    final next = character.copyWith(
      isPinned: !character.isPinned,
      updatedAt: DateTime.now(),
    );
    await widget.storage.saveCharacter(next);
    if (!mounted) return;
    context.showSnack(next.isPinned ? '已置顶角色' : '已取消置顶');
    await _load();
  }

  Future<void> _toggleHidden(AppCharacter character) async {
    if (!await _verifyCharacterOperation(
      character,
      character.isHidden ? '显示设定' : '隐藏设定',
    )) {
      return;
    }

    final next = character.copyWith(
      isHidden: !character.isHidden,
      updatedAt: DateTime.now(),
    );
    await widget.storage.saveCharacter(next);
    if (!mounted) return;
    context.showSnack(next.isHidden ? '已隐藏设定' : '已显示设定');
    await _load();
  }

  Future<void> _toggleLock(AppCharacter character) async {
    if (!character.isLocked && !widget.settings.hasPrivacyPassword) {
      context.showSnack('请先到设置里设置隐私密码');
      return;
    }
    if (!await _verifyCharacterOperation(character, '解除上锁')) {
      return;
    }

    final next = character.copyWith(
      isLocked: !character.isLocked,
      updatedAt: DateTime.now(),
    );
    await widget.storage.saveCharacter(next);
    if (!mounted) return;
    context.showSnack(next.isLocked ? '已上锁' : '已解除上锁');
    await _load();
  }

  Future<bool> _verifyCharacterOperation(
    AppCharacter character,
    String title,
  ) async {
    if (!character.isLocked) return true;
    return verifyPrivacyPassword(
      context: context,
      settings: widget.settings,
      storage: widget.storage,
      onSettingsChanged: widget.onSettingsChanged,
      title: title,
    );
  }

  Future<void> _deleteCharacter(AppCharacter character) async {
    if (!await _verifyCharacterOperation(character, '删除角色')) {
      return;
    }
    if (!mounted) return;

    final shouldDelete = await showConfirmDialog(
      context: context,
      title: '删除角色',
      content: context.isEnglish
          ? 'Delete "${character.name}"? Chat history and summaries will also be deleted.'
          : '确定删除“${character.name}”吗？聊天记录和总结也会一起删除。',
      confirmLabel: '删除',
    );

    if (!shouldDelete) return;

    try {
      await widget.storage.deleteCharacter(character.id);
      if (!mounted) return;
      context.showSnack('已删除角色');
      await _load();
    } catch (error) {
      if (!mounted) return;
      context.showSnack(error.toString());
    }
  }

  void _selectTab(int index) {
    setState(() {
      _tabIndex = index;
      _visitedTabs.add(index);
    });
    if (index == 0) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final navOpacity = widget.settings.navigationBarOpacity
        .clamp(0, 1)
        .toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = !isCompactWidth(constraints.maxWidth);
        final body = _currentBody();
        return Scaffold(
          extendBodyBehindAppBar: true,
          extendBody: !useRail,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: appSystemOverlayStyle(context),
            title: switch (_tabIndex) {
              0 => Text(context.t('Whisnya')),
              1 => Text(context.t('小说')),
              2 => Text(context.t('群聊')),
              _ => Text(context.t('设置')),
            },
            actions: [
              if (_tabIndex == 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _importCharacters,
                          icon: const Icon(Icons.drive_folder_upload_outlined),
                          label: Text(context.t('导入')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _editCharacter(),
                          icon: const Icon(Icons.add),
                          label: Text(context.t('新建角色')),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_tabIndex == 1)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() => _novelGridView = !_novelGridView);
                          },
                          icon: Icon(
                            _novelGridView
                                ? Icons.view_list_outlined
                                : Icons.grid_view_outlined,
                          ),
                          label: Text(context.t(_novelGridView ? '列表' : '网格')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () =>
                              _novelKey.currentState?.importNovel(),
                          icon: const Icon(Icons.upload_file),
                          label: Text(context.t('导入 txt')),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_tabIndex == 2)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: () =>
                          _theaterKey.currentState?.createTheater(),
                      icon: const Icon(Icons.add),
                      label: Text(context.t('新建')),
                    ),
                  ),
                ),
            ],
          ),
          body: useRail
              ? Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                      ),
                      child: _navigationRail(
                        navOpacity,
                        extended: isExpandedWidth(constraints.maxWidth),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          floatingActionButton: null,
          bottomNavigationBar: useRail ? null : _navigationBar(navOpacity),
        );
      },
    );
  }

  Widget _currentBody() {
    return IndexedStack(
      index: _tabIndex,
      children: [
        AppBackground(settings: widget.settings, child: _buildBody()),
        _visitedTabs.contains(1)
            ? AppBackground(
                settings: widget.settings,
                child: NovelScreen(
                  key: _novelKey,
                  storage: widget.storage,
                  aiService: widget.aiService,
                  settings: widget.settings,
                  useGridView: _novelGridView,
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(2)
            ? AppBackground(
                settings: widget.settings,
                child: TheaterListScreen(
                  key: _theaterKey,
                  storage: widget.storage,
                  aiService: widget.aiService,
                  settings: widget.settings,
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(3)
            ? SettingsScreen(
                storage: widget.storage,
                aiService: widget.aiService,
                settings: widget.settings,
                onSettingsChanged: widget.onSettingsChanged,
              )
            : const SizedBox.shrink(),
      ],
    );
  }

  Widget _navigationBar(double navOpacity) {
    return NavigationBar(
      height: 68,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: navOpacity),
      surfaceTintColor: Colors.transparent,
      selectedIndex: _tabIndex,
      onDestinationSelected: _selectTab,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.people_outline),
          selectedIcon: const Icon(Icons.people),
          label: context.t('角色'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.menu_book_outlined),
          selectedIcon: const Icon(Icons.menu_book),
          label: context.t('小说'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.forum_outlined),
          selectedIcon: const Icon(Icons.forum),
          label: context.t('群聊'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: context.t('设置'),
        ),
      ],
    );
  }

  Widget _navigationRail(double navOpacity, {required bool extended}) {
    return NavigationRail(
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: navOpacity),
      extended: extended,
      selectedIndex: _tabIndex,
      onDestinationSelected: _selectTab,
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.people_outline),
          selectedIcon: const Icon(Icons.people),
          label: Text(context.t('角色')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.menu_book_outlined),
          selectedIcon: const Icon(Icons.menu_book),
          label: Text(context.t('小说')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.forum_outlined),
          selectedIcon: const Icon(Icons.forum),
          label: Text(context.t('群聊')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: Text(context.t('设置')),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return AdaptivePage(
        child: Center(
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
        ),
      );
    }

    if (_characters.isEmpty) {
      return AdaptivePage(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_add_alt_1, size: 48),
                const SizedBox(height: 12),
                Text(context.t('还没有角色')),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _editCharacter(),
                  icon: const Icon(Icons.add),
                  label: Text(context.t('创建第一个角色')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final characters = _characters;
    return AdaptivePage(
      child: Column(
        children: [
          SizedBox(height: homeListTop(context)),
          Expanded(
            child: characters.isEmpty
                ? Center(child: Text(context.t('没有匹配的角色')))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 148),
                    itemCount: characters.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final character = characters[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: _CharacterAvatar(character: character),
                          title: Row(
                            children: [
                              Flexible(child: Text(character.name)),
                              if (character.isPinned) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.push_pin,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            character.isHidden
                                ? '******'
                                : character.description.isEmpty
                                ? context.t('未填写简介')
                                : character.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _openChat(character),
                          trailing: PopupMenuButton<_CharacterAction>(
                            onSelected: (action) {
                              switch (action) {
                                case _CharacterAction.edit:
                                  unawaited(_editCharacter(character));
                                  break;
                                case _CharacterAction.pin:
                                  unawaited(_togglePin(character));
                                  break;
                                case _CharacterAction.hide:
                                  unawaited(_toggleHidden(character));
                                  break;
                                case _CharacterAction.lock:
                                  unawaited(_toggleLock(character));
                                  break;
                                case _CharacterAction.delete:
                                  unawaited(_deleteCharacter(character));
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: _CharacterAction.edit,
                                child: ListTile(
                                  leading: const Icon(Icons.edit),
                                  title: Text(context.t('编辑角色')),
                                ),
                              ),
                              PopupMenuItem(
                                value: _CharacterAction.pin,
                                child: ListTile(
                                  leading: Icon(
                                    character.isPinned
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                  ),
                                  title: Text(
                                    context.t(
                                      character.isPinned ? '取消置顶' : '置顶角色',
                                    ),
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _CharacterAction.hide,
                                child: ListTile(
                                  leading: Icon(
                                    character.isHidden
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  title: Text(
                                    context.t(
                                      character.isHidden ? '显示设定' : '隐藏设定',
                                    ),
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _CharacterAction.lock,
                                child: ListTile(
                                  leading: Icon(
                                    character.isLocked
                                        ? Icons.lock_open_outlined
                                        : Icons.lock_outline,
                                  ),
                                  title: Text(
                                    context.t(
                                      character.isLocked ? '解除上锁' : '上锁',
                                    ),
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: _CharacterAction.delete,
                                child: ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: Text(context.t('删除角色')),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _CharacterAction { edit, pin, hide, lock, delete }

class _CharacterAvatar extends StatelessWidget {
  const _CharacterAvatar({required this.character});

  final AppCharacter character;

  @override
  Widget build(BuildContext context) {
    final avatarPath = character.avatar.trim();
    if (avatarPath.isNotEmpty) {
      final file = File(avatarPath);
      if (file.existsSync()) {
        return CircleAvatar(backgroundImage: FileImage(file));
      }
    }

    final name = character.name.trim();
    return CircleAvatar(
      child: Text(name.isEmpty ? '?' : name.characters.first),
    );
  }
}
