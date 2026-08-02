import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/qq_contact_binding.dart';
import '../../models/qq_integration_settings.dart';
import '../../services/local_storage_service.dart';
import '../../services/qq/android/qq_native_bridge.dart';
import '../../utils/app_i18n.dart';
import 'qq_contact_binding_edit_screen.dart';

class QqContactBindingsScreen extends StatefulWidget {
  const QqContactBindingsScreen({
    required this.storage,
    required this.mode,
    this.nativeBridge,
    this.onBindingsChanged,
    this.isAndroid = true,
    super.key,
  });

  final LocalStorageService storage;
  final QqIntegrationMode mode;
  final QqNativeBridge? nativeBridge;
  final Future<void> Function(List<QqContactBinding> bindings)?
  onBindingsChanged;
  final bool isAndroid;

  @override
  State<QqContactBindingsScreen> createState() =>
      _QqContactBindingsScreenState();
}

class _QqContactBindingsScreenState extends State<QqContactBindingsScreen> {
  List<QqContactBinding> _bindings = const [];
  var _capturing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool notifyChanged = false}) async {
    final values = await widget.storage.loadQqContactBindings();
    if (!mounted) return;
    setState(() {
      _bindings = values.where((item) => item.mode == widget.mode).toList();
    });
    if (notifyChanged) await widget.onBindingsChanged?.call(values);
  }

  Future<void> _add() async {
    final changed = await Navigator.of(context).push(
      MaterialPageRoute<QqContactBinding>(
        builder: (_) => QqContactBindingEditScreen(
          storage: widget.storage,
          mode: widget.mode,
        ),
      ),
    );
    await _load(notifyChanged: changed != null);
  }

  Future<void> _capture() async {
    final bridge = widget.nativeBridge;
    if (!widget.isAndroid || bridge == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      await bridge.beginNotificationCapture();
      final captured = await bridge.capturedNotifications.first.timeout(
        const Duration(seconds: 65),
      );
      if (!mounted) return;
      final changed = await Navigator.of(context).push(
        MaterialPageRoute<QqContactBinding>(
          builder: (_) => QqContactBindingEditScreen(
            storage: widget.storage,
            mode: QqIntegrationMode.notification,
            capturedExternalUserId: captured['contactKey'] as String? ?? '',
            capturedDisplayName: captured['title'] as String? ?? '',
          ),
        ),
      );
      await _load(notifyChanged: changed != null);
    } on TimeoutException {
      if (mounted) _snack(context.t('60 秒内没有捕获到有效 QQ 私聊通知。'));
    } finally {
      await bridge.cancelNotificationCapture();
      if (mounted) setState(() => _capturing = false);
    }
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
            child: Text(context.t('仅删除绑定')),
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

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.mode == QqIntegrationMode.notification;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('联系人绑定'))),
      floatingActionButton: notification
          ? null
          : FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: ListView(
        children: [
          if (notification)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(context.t('捕获下一条 QQ 私聊通知')),
              subtitle: Text(context.t('有效 60 秒；捕获到的通知不会触发回复')),
              trailing: _capturing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: widget.isAndroid ? _capture : null,
            ),
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
}
