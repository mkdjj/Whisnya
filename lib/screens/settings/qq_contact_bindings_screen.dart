import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/qq_contact_binding.dart';
import '../../models/qq_integration_settings.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import 'qq_contact_binding_edit_screen.dart';

class QqContactBindingsScreen extends StatefulWidget {
  const QqContactBindingsScreen({
    required this.storage,
    required this.mode,
    this.onBindingsChanged,
    super.key,
  });

  final LocalStorageService storage;
  final QqIntegrationMode mode;
  final Future<void> Function(List<QqContactBinding> bindings)?
  onBindingsChanged;

  @override
  State<QqContactBindingsScreen> createState() =>
      _QqContactBindingsScreenState();
}

class _QqContactBindingsScreenState extends State<QqContactBindingsScreen> {
  List<QqContactBinding> _bindings = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool notifyChanged = false}) async {
    final values = await widget.storage.loadQqContactBindings();
    if (!mounted) return;
    setState(
      () =>
          _bindings = values.where((item) => item.mode == widget.mode).toList(),
    );
    if (notifyChanged) await widget.onBindingsChanged?.call(values);
  }

  Future<void> _add() async {
    final changed = await Navigator.of(context).push(
      MaterialPageRoute<QqContactBinding>(
        builder: (_) => QqContactBindingEditScreen(
          storage: widget.storage,
          mode: QqIntegrationMode.oneBot,
        ),
      ),
    );
    await _load(notifyChanged: changed != null);
  }

  Future<void> _edit(QqContactBinding binding) async {
    final changed = await Navigator.of(context).push(
      MaterialPageRoute<QqContactBinding>(
        builder: (_) => QqContactBindingEditScreen(
          storage: widget.storage,
          mode: binding.mode,
          binding: binding,
        ),
      ),
    );
    await _load(notifyChanged: changed != null);
  }

  Future<void> _delete(QqContactBinding binding) async {
    final choice = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('删除联系人绑定')),
        content: Text(context.t('默认只删除绑定；QQ 对话和聊天记录可以保留。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 1),
            child: Text(context.t('只删除绑定')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 2),
            child: Text(context.t('删除绑定和 QQ 会话')),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await widget.storage.deleteQqContactBinding(binding.id);
    if (choice == 2) {
      final sessions = await widget.storage.loadChatSessions(
        binding.characterId,
      );
      for (final session in sessions) {
        if (session.id == binding.sessionId) {
          await widget.storage.deleteChatSession(session);
          break;
        }
      }
    }
    await _load(notifyChanged: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('联系人绑定'))),
    floatingActionButton: FloatingActionButton(
      onPressed: _add,
      child: const Icon(Icons.add),
    ),
    body: ListView(
      children: [
        if (_bindings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.t('还没有联系人绑定。陌生联系人会被静默忽略。')),
          ),
        for (final binding in _bindings)
          ListTile(
            leading: Icon(binding.enabled ? Icons.person : Icons.person_off),
            title: Text(binding.displayName),
            subtitle: Text(
              context.isEnglish
                  ? '${binding.externalUserId}\nRole: ${binding.characterId}'
                  : '${binding.externalUserId}\n角色：${binding.characterId}',
              maxLines: 2,
            ),
            isThreeLine: true,
            onTap: () => _edit(binding),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(binding),
            ),
          ),
      ],
    ),
  );
}
