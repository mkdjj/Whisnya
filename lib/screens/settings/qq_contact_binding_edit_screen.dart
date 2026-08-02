import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_character.dart';
import '../../models/qq_contact_binding.dart';
import '../../models/qq_integration_settings.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';

class QqContactBindingEditScreen extends StatefulWidget {
  const QqContactBindingEditScreen({
    required this.storage,
    required this.mode,
    this.binding,
    this.capturedExternalUserId = '',
    this.capturedDisplayName = '',
    super.key,
  });

  final LocalStorageService storage;
  final QqIntegrationMode mode;
  final QqContactBinding? binding;
  final String capturedExternalUserId;
  final String capturedDisplayName;

  @override
  State<QqContactBindingEditScreen> createState() =>
      _QqContactBindingEditScreenState();
}

class _QqContactBindingEditScreenState
    extends State<QqContactBindingEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _externalController;
  late final TextEditingController _nameController;
  late final TextEditingController _aliasesController;
  List<AppCharacter> _characters = const [];
  String _characterId = '';
  var _enabled = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final binding = widget.binding;
    _externalController = TextEditingController(
      text: binding?.externalUserId ?? widget.capturedExternalUserId,
    );
    _nameController = TextEditingController(
      text: binding?.displayName ?? widget.capturedDisplayName,
    );
    _aliasesController = TextEditingController(
      text:
          binding?.notificationTitleAliases.join('\n') ??
          (widget.capturedDisplayName.isEmpty
              ? ''
              : widget.capturedDisplayName),
    );
    _characterId = binding?.characterId ?? '';
    _enabled = binding?.enabled ?? true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final characters = await widget.storage.loadCharacters();
    if (!mounted) return;
    setState(() {
      _characters = characters;
      if (_characterId.isEmpty && characters.isNotEmpty) {
        _characterId = characters.first.id;
      }
    });
  }

  @override
  void dispose() {
    _externalController.dispose();
    _nameController.dispose();
    _aliasesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (_characterId.isEmpty) {
      _show(context.t('请先创建一个角色。'));
      return;
    }
    setState(() => _saving = true);
    try {
      final externalId = _externalController.text.trim();
      final duplicateMessage = context.t('这个联系人已经绑定。');
      final existing = await widget.storage.loadQqContactBindings();
      if (existing.any(
        (item) =>
            item.id != widget.binding?.id &&
            item.mode == widget.mode &&
            item.externalUserId == externalId,
      )) {
        throw StateError(duplicateMessage);
      }
      final now = DateTime.now();
      var sessionId = widget.binding?.sessionId ?? '';
      if (sessionId.isEmpty) {
        var session = await widget.storage.createChatSession(
          _characterId,
          title: 'QQ · ${_nameController.text.trim()}',
        );
        session = await widget.storage.markOpeningMessageInitialized(
          sessionId: session.id,
          characterId: _characterId,
        );
        sessionId = session.id;
      }
      final value = QqContactBinding(
        id: widget.binding?.id ?? 'qq_binding_${now.microsecondsSinceEpoch}',
        mode: widget.mode,
        externalUserId: externalId,
        displayName: _nameController.text,
        characterId: _characterId,
        sessionId: sessionId,
        enabled: _enabled,
        notificationTitleAliases: _aliasesController.text.split('\n'),
        createdAt: widget.binding?.createdAt ?? now,
        updatedAt: now,
      );
      await widget.storage.saveQqContactBinding(value);
      if (mounted) Navigator.of(context).pop(value);
    } on Object catch (error) {
      _show(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isNotification = widget.mode == QqIntegrationMode.notification;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(widget.binding == null ? '添加联系人绑定' : '编辑联系人绑定')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(context.t('保存')),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const ValueKey('qq-external-user-id'),
              controller: _externalController,
              readOnly: isNotification,
              decoration: InputDecoration(
                labelText: context.t(isNotification ? '通知联系人 Key' : 'QQ 号'),
                helperText: context.t(
                  isNotification ? '只能通过捕获 QQ 私聊通知生成' : '始终按字符串保存',
                ),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? context.t('不能为空')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('qq-display-name'),
              controller: _nameController,
              decoration: InputDecoration(labelText: context.t('显示名')),
              validator: (value) => value == null || value.trim().isEmpty
                  ? context.t('不能为空')
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _characters.any((item) => item.id == _characterId)
                  ? _characterId
                  : null,
              decoration: InputDecoration(labelText: context.t('绑定角色')),
              items: [
                for (final character in _characters)
                  DropdownMenuItem(
                    value: character.id,
                    child: Text(character.name),
                  ),
              ],
              onChanged: (value) => setState(() => _characterId = value ?? ''),
            ),
            if (isNotification) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _aliasesController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.t('联系人标题别名'),
                  helperText: context.t('每行一个；无障碍发送时只做精确匹配'),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.t('启用这个联系人')),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ],
        ),
      ),
    );
  }
}
