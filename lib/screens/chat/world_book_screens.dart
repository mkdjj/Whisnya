import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/world_book.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/snack.dart';

class WorldBookManagerScreen extends StatefulWidget {
  const WorldBookManagerScreen({required this.storage, super.key});

  final LocalStorageService storage;

  @override
  State<WorldBookManagerScreen> createState() => _WorldBookManagerScreenState();
}

class _WorldBookManagerScreenState extends State<WorldBookManagerScreen> {
  var _books = <WorldBook>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final books = await widget.storage.loadWorldBooks();
      if (!mounted) return;
      setState(() {
        _books = books;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showSnack(error.toString());
    }
  }

  Future<void> _edit([WorldBook? book]) async {
    final result = await Navigator.of(context).push<WorldBook>(
      MaterialPageRoute(builder: (_) => WorldBookEditScreen(book: book)),
    );
    if (result == null) return;
    await widget.storage.saveWorldBook(result);
    await _load();
  }

  Future<void> _openEntries(WorldBook book) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            WorldBookEntriesScreen(storage: widget.storage, book: book),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('关键词世界书'))),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: Text(context.t('添加世界书')),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _books.isEmpty
        ? Center(child: Text(context.t('还没有世界书')))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _books.length,
            itemBuilder: (context, index) {
              final book = _books[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    book.enabled ? Icons.menu_book : Icons.menu_book_outlined,
                  ),
                  title: Text(book.name),
                  subtitle: Text(book.description),
                  onTap: () => _openEntries(book),
                  trailing: PopupMenuButton<_WorldBookManagerAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _WorldBookManagerAction.edit:
                          unawaited(_edit(book));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _WorldBookManagerAction.edit,
                        child: Text(context.t('编辑世界书')),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

enum _WorldBookManagerAction { edit }

class WorldBookEditScreen extends StatefulWidget {
  const WorldBookEditScreen({this.book, super.key});

  final WorldBook? book;

  @override
  State<WorldBookEditScreen> createState() => _WorldBookEditScreenState();
}

class _WorldBookEditScreenState extends State<WorldBookEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.book?.name ?? '');
    _description = TextEditingController(text: widget.book?.description ?? '');
    _enabled = widget.book?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      context.showSnack('请填写世界书名称');
      return;
    }
    final now = DateTime.now();
    Navigator.of(context).pop(
      WorldBook(
        id: widget.book?.id ?? 'worldbook_${now.microsecondsSinceEpoch}',
        name: name,
        description: _description.text.trim(),
        enabled: _enabled,
        createdAt: widget.book?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t(widget.book == null ? '新建世界书' : '编辑世界书')),
      actions: [
        IconButton(
          tooltip: context.t('保存'),
          onPressed: _save,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          maxLength: 80,
          decoration: InputDecoration(labelText: context.t('世界书名称')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 4,
          decoration: InputDecoration(labelText: context.t('简介')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('启用世界书')),
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(context.t('保存')),
        ),
      ],
    ),
  );
}

class WorldBookEntryEditScreen extends StatefulWidget {
  const WorldBookEntryEditScreen({required this.book, this.entry, super.key});

  final WorldBook book;
  final WorldBookEntry? entry;

  @override
  State<WorldBookEntryEditScreen> createState() =>
      _WorldBookEntryEditScreenState();
}

class _WorldBookEntryEditScreenState extends State<WorldBookEntryEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _keywords;
  late int _priority;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.entry?.title ?? '');
    _content = TextEditingController(text: widget.entry?.content ?? '');
    _keywords = TextEditingController(
      text: widget.entry?.keywords.join(', ') ?? '',
    );
    _priority = widget.entry?.priority ?? 50;
    _enabled = widget.entry?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _keywords.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final content = _content.text.trim();
    final keywords = cleanWorldBookKeywords([_keywords.text]);
    if (title.isEmpty || content.isEmpty) {
      context.showSnack(context.t('请填写标题和内容'));
      return;
    }
    if (keywords.isEmpty) {
      context.showSnack(context.t('至少填写一个关键词'));
      return;
    }
    final now = DateTime.now();
    Navigator.of(context).pop(
      WorldBookEntry(
        id: widget.entry?.id ?? 'worldbook_entry_${now.microsecondsSinceEpoch}',
        worldBookId: widget.book.id,
        title: title,
        content: content,
        keywords: keywords,
        priority: _priority,
        enabled: _enabled,
        createdAt: widget.entry?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t(widget.entry == null ? '添加词条' : '编辑词条')),
      actions: [
        IconButton(
          tooltip: context.t('保存'),
          onPressed: _save,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.book.name, style: Theme.of(context).textTheme.titleMedium),
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: InputDecoration(labelText: context.t('标题')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _content,
          minLines: 6,
          maxLines: 12,
          decoration: InputDecoration(labelText: context.t('内容')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keywords,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.t('关键词'),
            hintText: context.t('使用逗号或换行分隔关键词'),
          ),
        ),
        const SizedBox(height: 8),
        Text('${context.t('优先级')}：$_priority'),
        Slider(
          value: _priority.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          label: '$_priority',
          onChanged: (value) => setState(() => _priority = value.round()),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('启用世界书词条')),
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(context.t('保存')),
        ),
      ],
    ),
  );
}

class WorldBookEntriesScreen extends StatefulWidget {
  const WorldBookEntriesScreen({
    required this.storage,
    required this.book,
    super.key,
  });

  final LocalStorageService storage;
  final WorldBook book;

  @override
  State<WorldBookEntriesScreen> createState() => _WorldBookEntriesScreenState();
}

class _WorldBookEntriesScreenState extends State<WorldBookEntriesScreen> {
  var _entries = <WorldBookEntry>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final entries = await widget.storage.loadWorldBookEntries(widget.book.id);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        context.showSnack(error.toString());
      }
    }
  }

  Future<void> _edit([WorldBookEntry? entry]) async {
    final result = await Navigator.of(context).push<WorldBookEntry>(
      MaterialPageRoute(
        builder: (_) =>
            WorldBookEntryEditScreen(book: widget.book, entry: entry),
      ),
    );
    if (result == null) return;
    await widget.storage.saveWorldBookEntry(result);
    await _load();
  }

  Future<void> _delete(WorldBookEntry entry) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: context.t('删除词条'),
      content: context.t('确定删除这条词条吗？'),
      confirmLabel: context.t('删除'),
    );
    if (!mounted || !confirmed) return;
    await widget.storage.deleteWorldBookEntry(widget.book.id, entry.id);
    await _load();
  }

  Future<void> _toggle(WorldBookEntry entry) async {
    await widget.storage.saveWorldBookEntry(
      entry.copyWith(enabled: !entry.enabled, updatedAt: DateTime.now()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.book.name)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: Text(context.t('添加词条')),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _entries.isEmpty
        ? Center(child: Text(context.t('这本世界书还没有关键词词条')))
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              return Card(
                child: ListTile(
                  title: Text(entry.title),
                  subtitle: Text(
                    '${entry.keywords.join('、')} · ${context.t('优先级')} ${entry.priority}\n${entry.content}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  leading: Icon(
                    entry.enabled
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                  ),
                  onTap: () => _edit(entry),
                  trailing: PopupMenuButton<_EntryAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _EntryAction.toggle:
                          unawaited(_toggle(entry));
                        case _EntryAction.delete:
                          unawaited(_delete(entry));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _EntryAction.toggle,
                        child: Text(
                          context.t(entry.enabled ? '禁用世界书词条' : '启用世界书词条'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _EntryAction.delete,
                        child: Text(context.t('删除')),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

enum _EntryAction { toggle, delete }

class WorldBookPickerScreen extends StatefulWidget {
  const WorldBookPickerScreen({
    required this.books,
    required this.selectedIds,
    super.key,
  });

  final List<WorldBook> books;
  final List<String> selectedIds;

  @override
  State<WorldBookPickerScreen> createState() => _WorldBookPickerScreenState();
}

class _WorldBookPickerScreenState extends State<WorldBookPickerScreen> {
  late final Set<String> _selected = {...widget.selectedIds};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t('引用已有世界书')),
      actions: [
        IconButton(
          tooltip: context.t('保存引用'),
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: widget.books.isEmpty
        ? Center(child: Text(context.t('还没有世界书')))
        : ListView.builder(
            itemCount: widget.books.length,
            itemBuilder: (context, index) {
              final book = widget.books[index];
              return CheckboxListTile(
                value: _selected.contains(book.id),
                title: Text(book.name),
                subtitle: Text(book.description),
                onChanged: (value) => setState(() {
                  value == true
                      ? _selected.add(book.id)
                      : _selected.remove(book.id);
                }),
              );
            },
          ),
  );
}
