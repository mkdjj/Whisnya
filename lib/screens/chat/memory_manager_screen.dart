import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_character.dart';
import '../../models/character_memory_entry.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/world_book.dart';
import '../../services/ai/ai_gateway.dart';
import '../../services/chat/memory_extraction_service.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/snack.dart';
import 'memory_edit_screen.dart';
import 'world_book_screens.dart';

class MemoryManagerScreen extends StatefulWidget {
  const MemoryManagerScreen({
    required this.storage,
    required this.aiService,
    required this.character,
    required this.session,
    required this.selectedEndpointId,
    super.key,
  });

  final LocalStorageService storage;
  final AiGateway aiService;
  final AppCharacter character;
  final ChatSession session;
  final String selectedEndpointId;

  @override
  State<MemoryManagerScreen> createState() => _MemoryManagerScreenState();
}

class _MemoryManagerScreenState extends State<MemoryManagerScreen>
    with SingleTickerProviderStateMixin {
  late AppCharacter _character;
  late final TabController _tabController;
  var _entries = <CharacterMemoryEntry>[];
  var _messages = <ChatMessage>[];
  var _worldBooks = <WorldBook>[];
  var _entryCounts = <String, ({int enabled, int total})>{};
  var _tabIndex = 0;
  var _loading = true;
  var _extracting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _character = widget.character;
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_handleTabChanged);
    unawaited(_load());
  }

  void _handleTabChanged() {
    final index = _tabController.index;
    if (!mounted || index == _tabIndex) return;
    setState(() => _tabIndex = index);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.storage.loadCharacterMemories(_character.id);
      final refreshedCharacter = (await widget.storage.loadCharacters())
          .where((character) => character.id == _character.id)
          .firstOrNull;
      if (refreshedCharacter != null) {
        _character = refreshedCharacter;
      }
      final messages = await widget.storage.loadChatBySession(widget.session);
      final allBooks = await widget.storage.loadWorldBooks();
      final referenced = allBooks
          .where((book) => _character.worldBookIds.contains(book.id))
          .toList();
      final counts = <String, ({int enabled, int total})>{};
      for (final book in referenced) {
        final bookEntries = await widget.storage.loadWorldBookEntries(book.id);
        counts[book.id] = (
          enabled: bookEntries.where((entry) => entry.enabled).length,
          total: bookEntries.length,
        );
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _messages = messages;
        _worldBooks = referenced;
        _entryCounts = counts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editMemory({
    CharacterMemoryEntry? entry,
    String? content,
    MemoryScope? fixedScope,
  }) async {
    final result = await Navigator.of(context).push<CharacterMemoryEntry>(
      MaterialPageRoute(
        builder: (_) => MemoryEditScreen(
          character: _character,
          session: widget.session,
          entry: entry,
          initialContent: content,
          fixedScope: fixedScope,
        ),
      ),
    );
    if (result == null) return;
    try {
      await widget.storage.saveCharacterMemory(result);
      await _load();
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    }
  }

  Future<void> _deleteMemory(CharacterMemoryEntry entry) async {
    if (!await showConfirmDialog(
      context: context,
      title: context.t('删除记忆'),
      content: context.t('确定删除这条记忆吗？'),
      confirmLabel: context.t('删除'),
    )) {
      return;
    }
    await widget.storage.deleteCharacterMemory(_character.id, entry.id);
    await _load();
  }

  Future<void> _toggleMemory(CharacterMemoryEntry entry) async {
    await widget.storage.saveCharacterMemory(
      entry.copyWith(enabled: !entry.enabled, updatedAt: DateTime.now()),
    );
    await _load();
  }

  Future<void> _extract() async {
    if (_extracting) return;
    setState(() => _extracting = true);
    try {
      final config = await widget.storage.loadApiConfig();
      final endpoint = config.effectiveEndpoint(widget.selectedEndpointId);
      if (endpoint == null) throw StateError('请先添加完整 API 配置。');
      final candidates = await MemoryExtractionService(widget.aiService)
          .extract(
            characterId: _character.id,
            sessionId: widget.session.id,
            messages: _messages,
            endpoint: endpoint,
            onUsage: (usage, request) => widget.storage.recordAiUsage(
              requestType: 'characterMemoryExtraction',
              model: endpoint.model,
              usage: usage,
              messages: request,
              summaryUpdated: false,
            ),
          );
      if (!mounted) return;
      final selected = await Navigator.of(context)
          .push<List<CharacterMemoryEntry>>(
            MaterialPageRoute(
              builder: (_) => _MemoryReviewScreen(
                character: _character,
                session: widget.session,
                entries: candidates,
              ),
            ),
          );
      if (selected == null || selected.isEmpty) return;
      for (final entry in selected) {
        await widget.storage.saveCharacterMemory(entry);
      }
      if (mounted) context.showSnack('已保存 ${selected.length} 条记忆');
      await _load();
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _addWorldBook() async {
    final action = await showModalBottomSheet<_WorldBookAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: Text(context.t('引用已有世界书')),
              onTap: () => Navigator.pop(context, _WorldBookAction.reference),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: Text(context.t('新建世界书')),
              onTap: () => Navigator.pop(context, _WorldBookAction.create),
            ),
          ],
        ),
      ),
    );
    if (action == _WorldBookAction.reference) {
      final books = await widget.storage.loadWorldBooks();
      if (!mounted) return;
      final ids = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => WorldBookPickerScreen(
            books: books,
            selectedIds: _character.worldBookIds,
          ),
        ),
      );
      if (ids != null) await _saveWorldBookReferences(ids);
    } else if (action == _WorldBookAction.create) {
      if (!mounted) return;
      final book = await Navigator.of(context).push<WorldBook>(
        MaterialPageRoute(builder: (_) => const WorldBookEditScreen()),
      );
      if (book == null) return;
      await widget.storage.saveWorldBook(book);
      await _saveWorldBookReferences([..._character.worldBookIds, book.id]);
      if (mounted) await _openWorldBook(book);
    }
  }

  Future<void> _saveWorldBookReferences(List<String> ids) async {
    final cleaned = ids.toSet().toList();
    await widget.storage.updateCharacterWorldBookReferences(
      _character.id,
      cleaned,
    );
    if (!mounted) return;
    setState(() => _character = _character.copyWith(worldBookIds: cleaned));
    await _load();
  }

  Future<void> _openWorldBook(WorldBook book) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            WorldBookEntriesScreen(storage: widget.storage, book: book),
      ),
    );
    await _load();
  }

  Future<void> _editWorldBook(WorldBook book) async {
    final updated = await Navigator.of(context).push<WorldBook>(
      MaterialPageRoute(builder: (_) => WorldBookEditScreen(book: book)),
    );
    if (updated == null) return;
    await widget.storage.saveWorldBook(updated);
    await _load();
  }

  Future<void> _deleteWorldBook(WorldBook book) async {
    final characters = await widget.storage.loadCharacters();
    if (!mounted) return;
    final count = characters
        .where((character) => character.worldBookIds.contains(book.id))
        .length;
    final confirmed = await showConfirmDialog(
      context: context,
      title: context.t('删除世界书'),
      content: '${context.t('确定删除这本世界书吗？')}\n${context.t('角色引用数量')}：$count',
      confirmLabel: context.t('删除'),
    );
    if (!mounted || !confirmed) return;
    await widget.storage.deleteWorldBook(book.id);
    await _load();
  }

  Future<void> _removeReference(WorldBook book) async {
    await _saveWorldBookReferences(
      _character.worldBookIds.where((id) => id != book.id).toList(),
    );
  }

  List<CharacterMemoryEntry> _memoryItems(MemoryScope scope) =>
      _entries
          .where(
            (entry) =>
                entry.scope == scope &&
                (scope != MemoryScope.session ||
                    entry.sessionId == widget.session.id) &&
                entry.keywords.isEmpty,
          )
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Widget _memoryTab(MemoryScope scope) {
    final items = _memoryItems(scope);
    final emptyText = scope == MemoryScope.character
        ? '当前角色还没有长期记忆'
        : '当前对话还没有记忆';
    final addText = scope == MemoryScope.character ? '添加长期记忆' : '添加当前对话记忆';
    return Column(
      children: [
        if (scope == MemoryScope.session)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${context.t('当前对话')}：${widget.session.title}'),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? _emptyAction(
                  emptyText,
                  addText,
                  () => _editMemory(fixedScope: scope),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _memoryTile(items[index]),
                ),
        ),
      ],
    );
  }

  Widget _memoryTile(CharacterMemoryEntry entry) => Card(
    child: ListTile(
      title: Text(entry.title),
      subtitle: Text(
        '${context.t('优先级')} ${entry.priority}\n${entry.content}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      leading: Icon(
        entry.enabled ? Icons.check_circle_outline : Icons.pause_circle_outline,
      ),
      onTap: () => _editMemory(entry: entry, fixedScope: entry.scope),
      trailing: PopupMenuButton<_MemoryAction>(
        onSelected: (action) {
          switch (action) {
            case _MemoryAction.toggle:
              unawaited(_toggleMemory(entry));
            case _MemoryAction.delete:
              unawaited(_deleteMemory(entry));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _MemoryAction.toggle,
            child: Text(context.t(entry.enabled ? '禁用记忆' : '启用记忆')),
          ),
          PopupMenuItem(
            value: _MemoryAction.delete,
            child: Text(context.t('删除')),
          ),
        ],
      ),
    ),
  );

  Widget _worldBookTab() {
    if (_worldBooks.isEmpty) {
      return _emptyAction('当前角色还没有引用世界书', '添加世界书', _addWorldBook);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (final book in _worldBooks)
          Card(
            child: ListTile(
              leading: Icon(
                book.enabled ? Icons.menu_book : Icons.menu_book_outlined,
              ),
              title: Text(book.name),
              subtitle: Text(
                '${book.description}\n${_entryCounts[book.id]?.enabled ?? 0}/${_entryCounts[book.id]?.total ?? 0} ${context.t('有效词条')}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              onTap: () => _openWorldBook(book),
              trailing: PopupMenuButton<_WorldBookMenuAction>(
                onSelected: (action) {
                  switch (action) {
                    case _WorldBookMenuAction.remove:
                      unawaited(_removeReference(book));
                    case _WorldBookMenuAction.edit:
                      unawaited(_editWorldBook(book));
                    case _WorldBookMenuAction.toggle:
                      unawaited(
                        widget.storage
                            .saveWorldBook(
                              book.copyWith(
                                enabled: !book.enabled,
                                updatedAt: DateTime.now(),
                              ),
                            )
                            .then((_) => _load()),
                      );
                    case _WorldBookMenuAction.delete:
                      unawaited(_deleteWorldBook(book));
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _WorldBookMenuAction.remove,
                    child: Text(context.t('取消引用')),
                  ),
                  PopupMenuItem(
                    value: _WorldBookMenuAction.edit,
                    child: Text(context.t('编辑世界书')),
                  ),
                  PopupMenuItem(
                    value: _WorldBookMenuAction.toggle,
                    child: Text(context.t(book.enabled ? '禁用世界书' : '启用世界书')),
                  ),
                  PopupMenuItem(
                    value: _WorldBookMenuAction.delete,
                    child: Text(context.t('删除')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyAction(
    String emptyText,
    String actionText,
    VoidCallback onPressed,
  ) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emptyText),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add),
          label: Text(context.t(actionText)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(context.t('重新加载')),
            ),
          )
        : TabBarView(
            controller: _tabController,
            children: [
              _memoryTab(MemoryScope.character),
              _memoryTab(MemoryScope.session),
              _worldBookTab(),
            ],
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('记忆与世界书')),
        actions: [
          IconButton(
            tooltip: context.t('AI 提取记忆'),
            onPressed: _extracting ? null : _extract,
            icon: _extracting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: context.t('长期记忆')),
            Tab(text: context.t('当前对话记忆')),
            Tab(text: context.t('关键词世界书')),
          ],
        ),
      ),
      floatingActionButton: !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: _tabIndex == 2
                  ? _addWorldBook
                  : () => _editMemory(
                      fixedScope: _tabIndex == 0
                          ? MemoryScope.character
                          : MemoryScope.session,
                    ),
              icon: const Icon(Icons.add),
              label: Text(
                context.t(
                  _tabIndex == 2
                      ? '添加世界书'
                      : _tabIndex == 0
                      ? '添加长期记忆'
                      : '添加当前对话记忆',
                ),
              ),
            )
          : null,
      body: body,
    );
  }
}

enum _MemoryAction { toggle, delete }

enum _WorldBookAction { reference, create }

enum _WorldBookMenuAction { remove, edit, toggle, delete }

class _MemoryReviewScreen extends StatefulWidget {
  const _MemoryReviewScreen({
    required this.character,
    required this.session,
    required this.entries,
  });

  final AppCharacter character;
  final ChatSession session;
  final List<CharacterMemoryEntry> entries;

  @override
  State<_MemoryReviewScreen> createState() => _MemoryReviewScreenState();
}

class _MemoryReviewScreenState extends State<_MemoryReviewScreen> {
  late final List<bool> _selected = List<bool>.filled(
    widget.entries.length,
    true,
  );
  late final List<CharacterMemoryEntry> _entries = List.of(widget.entries);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('审核提取记忆'))),
    body: ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return CheckboxListTile(
          value: _selected[index],
          onChanged: (value) =>
              setState(() => _selected[index] = value ?? false),
          title: Text(entry.title),
          subtitle: Text(
            '${entry.content}\n${entry.scope.name} · ${entry.priority}',
          ),
          isThreeLine: true,
          secondary: IconButton(
            tooltip: context.t('编辑记忆'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final edited = await Navigator.of(context)
                  .push<CharacterMemoryEntry>(
                    MaterialPageRoute(
                      builder: (_) => MemoryEditScreen(
                        character: widget.character,
                        session: widget.session,
                        entry: entry,
                        fixedScope: entry.scope,
                      ),
                    ),
                  );
              if (edited != null && mounted) {
                setState(() => _entries[index] = edited);
              }
            },
          ),
        );
      },
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(12),
      child: FilledButton(
        onPressed: () => Navigator.of(context).pop([
          for (var index = 0; index < _entries.length; index++)
            if (_selected[index]) _entries[index],
        ]),
        child: Text(context.t('保存选中项')),
      ),
    ),
  );
}
