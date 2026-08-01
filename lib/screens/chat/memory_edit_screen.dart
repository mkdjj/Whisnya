import 'package:flutter/material.dart';

import '../../models/app_character.dart';
import '../../models/character_memory_entry.dart';
import '../../models/chat_session.dart';
import '../../utils/app_i18n.dart';

class MemoryEditScreen extends StatefulWidget {
  const MemoryEditScreen({
    required this.character,
    required this.session,
    this.entry,
    this.initialContent,
    this.initialScope,
    this.allowScopeChange = true,
    super.key,
  });

  final AppCharacter character;
  final ChatSession session;
  final CharacterMemoryEntry? entry;
  final String? initialContent;
  final MemoryScope? initialScope;
  final bool allowScopeChange;

  @override
  State<MemoryEditScreen> createState() => _MemoryEditScreenState();
}

class _MemoryEditScreenState extends State<MemoryEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late MemoryScope _scope;
  late int _priority;
  late bool _enabled;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _title = TextEditingController(
      text: entry?.title ?? _defaultTitle(widget.initialContent ?? ''),
    );
    _content = TextEditingController(
      text: entry?.content ?? widget.initialContent ?? '',
    );
    _scope = widget.initialScope ?? entry?.scope ?? MemoryScope.character;
    _priority = entry?.priority ?? 50;
    _enabled = entry?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  String _defaultTitle(String content) {
    final compact = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return '来自聊天的记忆';
    return compact.runes.length <= 20
        ? compact
        : '${String.fromCharCodes(compact.runes.take(20))}...';
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('请填写标题和内容'))));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    try {
      final entry = CharacterMemoryEntry(
        id: widget.entry?.id ?? 'memory_${now.microsecondsSinceEpoch}',
        characterId: widget.character.id,
        scope: _scope,
        sessionId: _scope == MemoryScope.session ? widget.session.id : null,
        title: title,
        content: content,
        keywords: const [],
        priority: _priority,
        enabled: _enabled,
        createdAt: widget.entry?.createdAt ?? now,
        updatedAt: now,
      );
      if (mounted) Navigator.of(context).pop(entry);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t(widget.entry == null ? '新建记忆' : '编辑记忆')),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          if (widget.allowScopeChange) ...[
            DropdownButtonFormField<MemoryScope>(
              initialValue: _scope,
              decoration: InputDecoration(labelText: context.t('范围')),
              items: [
                DropdownMenuItem(
                  value: MemoryScope.character,
                  child: Text(context.t('长期记忆')),
                ),
                DropdownMenuItem(
                  value: MemoryScope.session,
                  child: Text(context.t('当前对话记忆')),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _scope = value ?? _scope),
            ),
          ],
          const SizedBox(height: 8),
          Text('${context.t('优先级')}：$_priority'),
          Slider(
            value: _priority.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$_priority',
            onChanged: _saving
                ? null
                : (value) => setState(() => _priority = value.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('启用记忆')),
            value: _enabled,
            onChanged: _saving
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(context.t('保存')),
          ),
        ],
      ),
    ),
  );
}
