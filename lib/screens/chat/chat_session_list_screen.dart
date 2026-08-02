import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_character.dart';
import '../../models/chat_session.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/snack.dart';

class ChatSessionListScreen extends StatefulWidget {
  const ChatSessionListScreen({
    required this.storage,
    required this.character,
    this.selectedSessionId,
    this.deletionDisabled = false,
    super.key,
  });

  final LocalStorageService storage;
  final AppCharacter character;
  final String? selectedSessionId;
  final bool deletionDisabled;

  @override
  State<ChatSessionListScreen> createState() => _ChatSessionListScreenState();
}

class _ChatSessionListScreenState extends State<ChatSessionListScreen> {
  var _sessions = <ChatSession>[];
  var _counts = <String, int>{};
  var _loading = true;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await widget.storage.loadChatSessions(
        widget.character.id,
      );
      final counts = <String, int>{};
      for (final session in sessions) {
        counts[session.id] = (await widget.storage.loadChatBySession(
          session,
        )).length;
      }
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _counts = counts;
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

  Future<void> _create() async {
    final title = await _editTitle(title: '新建对话', initial: '');
    if (title == null) return;
    setState(() => _busy = true);
    try {
      final session = await widget.storage.createChatSession(
        widget.character.id,
        title: title,
      );
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _editTitle({
    required String title,
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t(title)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(labelText: context.t('对话标题')),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(context.t('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _rename(ChatSession session) async {
    final title = await _editTitle(title: '重命名对话', initial: session.title);
    if (title == null) return;
    setState(() => _busy = true);
    try {
      await widget.storage.saveChatSession(
        session.copyWith(title: title, updatedAt: DateTime.now()),
      );
      await _load();
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duplicate(ChatSession session) async {
    setState(() => _busy = true);
    try {
      final copy = await widget.storage.duplicateChatSession(session);
      if (!mounted) return;
      Navigator.of(context).pop(copy);
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(ChatSession session) async {
    setState(() => _busy = true);
    try {
      if (session.isArchived) {
        await widget.storage.unarchiveChatSession(session);
      } else {
        await widget.storage.archiveChatSession(session);
      }
      await _load();
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ChatSession session) async {
    if (widget.deletionDisabled) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除对话',
      content: context.t('确定删除这个对话及其聊天记录吗？'),
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.storage.deleteChatSession(session);
      if (!mounted) return;
      if (session.id == widget.selectedSessionId) {
        final recent = await widget.storage.getOrCreateRecentChatSession(
          widget.character.id,
        );
        if (!mounted) return;
        Navigator.of(context).pop(recent);
        return;
      }
      await _load();
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(ChatSession session) async {
    final used = session.copyWith(
      lastUsedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await widget.storage.saveChatSession(used);
    if (mounted) Navigator.of(context).pop(used);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t('对话管理')),
      actions: [
        IconButton(
          tooltip: context.t('新建对话'),
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add_comment_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      tooltip: context.t('新建对话'),
      onPressed: _busy ? null : _create,
      child: const Icon(Icons.add),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(context.t('重新加载')),
            ),
          )
        : _sessionList(),
  );

  Widget _sessionList() {
    final active = _sessions.where((item) => !item.isArchived).toList();
    final archived = _sessions.where((item) => item.isArchived).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        _section('进行中的对话', active),
        if (archived.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section('已归档', archived),
        ],
      ],
    );
  }

  Widget _section(String title, List<ChatSession> sessions) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final session in sessions)
        Card(
          child: ListTile(
            selected: session.id == widget.selectedSessionId,
            leading: Icon(
              session.isArchived
                  ? Icons.inventory_2_outlined
                  : Icons.chat_bubble_outline,
            ),
            title: Text(session.title),
            subtitle: Text(
              '${context.t('消息数')}：${_counts[session.id] ?? 0}  ·  '
              '${_formatDate(session.lastUsedAt)}',
            ),
            onTap: _busy ? null : () => _open(session),
            trailing: PopupMenuButton<_SessionAction>(
              enabled: !_busy,
              onSelected: (action) {
                switch (action) {
                  case _SessionAction.rename:
                    unawaited(_rename(session));
                  case _SessionAction.duplicate:
                    unawaited(_duplicate(session));
                  case _SessionAction.archive:
                    unawaited(_archive(session));
                  case _SessionAction.delete:
                    unawaited(_delete(session));
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _SessionAction.rename,
                  child: Text(context.t('重命名')),
                ),
                PopupMenuItem(
                  value: _SessionAction.duplicate,
                  child: Text(context.t('复制对话')),
                ),
                PopupMenuItem(
                  value: _SessionAction.archive,
                  child: Text(context.t(session.isArchived ? '取消归档' : '归档对话')),
                ),
                PopupMenuItem(
                  value: _SessionAction.delete,
                  enabled: !widget.deletionDisabled,
                  child: Text(context.t('删除')),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  String _formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

enum _SessionAction { rename, duplicate, archive, delete }
