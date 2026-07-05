import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';
import '../utils/page_layout.dart';
import '../utils/password_lock.dart';
import '../widgets/app_background.dart';
import 'character_edit_screen.dart';
import 'chat_screen.dart';
import 'novel_screen.dart';
import 'settings_screen.dart';

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

  var _isLoading = true;
  var _tabIndex = 0;
  var _novelGridView = false;
  String? _error;
  List<AppCharacter> _characters = const [];

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
      await widget.storage.ensureReady();
      final characters = await widget.storage.loadCharacters();
      if (!mounted) return;
      setState(() {
        _characters = characters;
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

  Future<void> _openChat(AppCharacter character) async {
    if (!await _verifyCharacterOperation(character, '进入聊天')) {
      return;
    }
    await widget.storage.markCharacterUsed(character.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
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
    _showSnack(next.isPinned ? '已置顶角色' : '已取消置顶');
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
    _showSnack(next.isHidden ? '已隐藏设定' : '已显示设定');
    await _load();
  }

  Future<void> _toggleLock(AppCharacter character) async {
    if (!character.isLocked && !widget.settings.hasPrivacyPassword) {
      _showSnack('请先到设置里设置隐私密码');
      return;
    }
    if (character.isLocked && !await _verifyPassword('解除上锁')) {
      return;
    }

    final next = character.copyWith(
      isLocked: !character.isLocked,
      updatedAt: DateTime.now(),
    );
    await widget.storage.saveCharacter(next);
    if (!mounted) return;
    _showSnack(next.isLocked ? '已上锁' : '已解除上锁');
    await _load();
  }

  Future<bool> _verifyCharacterOperation(
    AppCharacter character,
    String title,
  ) async {
    if (!character.isLocked) {
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
            onPressed: () {
              final ok = PasswordLock.verify(
                controller.text,
                widget.settings.privacyPasswordSalt,
                widget.settings.privacyPasswordHash,
              );
              if (!ok) {
                _showSnack('密码不正确');
                return;
              }
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

  Future<void> _deleteCharacter(AppCharacter character) async {
    if (!await _verifyCharacterOperation(character, '删除角色')) {
      return;
    }
    if (!mounted) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('删除角色')),
        content: Text(
          context.isEnglish
              ? 'Delete "${character.name}"? Chat history and summaries will also be deleted.'
              : '确定删除“${character.name}”吗？聊天记录和总结也会一起删除。',
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

    try {
      await widget.storage.deleteCharacter(character.id);
      if (!mounted) return;
      _showSnack('已删除角色');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(message))));
  }

  void _selectTab(int index) {
    setState(() => _tabIndex = index);
    if (index == 0) {
      _load();
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
            systemOverlayStyle: _overlayStyle(context),
            title: switch (_tabIndex) {
              0 => Text(context.t('Whisnya')),
              1 => Text(context.t('小说')),
              _ => Text(context.t('设置')),
            },
            actions: [
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
          floatingActionButton: _tabIndex == 0
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: FloatingActionButton.extended(
                    onPressed: () => _editCharacter(),
                    icon: const Icon(Icons.add),
                    label: Text(context.t('新建角色')),
                  ),
                )
              : null,
          bottomNavigationBar: useRail ? null : _navigationBar(navOpacity),
        );
      },
    );
  }

  Widget _currentBody() {
    return switch (_tabIndex) {
      0 => AppBackground(settings: widget.settings, child: _buildBody()),
      1 => AppBackground(
        settings: widget.settings,
        child: NovelScreen(
          key: _novelKey,
          storage: widget.storage,
          aiService: widget.aiService,
          settings: widget.settings,
          useGridView: _novelGridView,
        ),
      ),
      _ => SettingsScreen(
        storage: widget.storage,
        aiService: widget.aiService,
        settings: widget.settings,
        onSettingsChanged: widget.onSettingsChanged,
      ),
    };
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

    return AdaptivePage(
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(0, homeListTop(context), 0, 148),
        itemCount: _characters.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final character = _characters[index];
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
                      _editCharacter(character);
                      break;
                    case _CharacterAction.pin:
                      _togglePin(character);
                      break;
                    case _CharacterAction.hide:
                      _toggleHidden(character);
                      break;
                    case _CharacterAction.lock:
                      _toggleLock(character);
                      break;
                    case _CharacterAction.delete:
                      _deleteCharacter(character);
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
                        context.t(character.isPinned ? '取消置顶' : '置顶角色'),
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
                        context.t(character.isHidden ? '显示设定' : '隐藏设定'),
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
                        context.t(character.isLocked ? '解除上锁' : '上锁'),
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
    );
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
