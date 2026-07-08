import 'package:flutter/material.dart';

import '../models/api_config.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';
import '../utils/confirm_dialog.dart';
import '../utils/page_layout.dart';
import '../utils/snack.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({
    required this.storage,
    required this.aiService,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  var _config = ApiConfig.defaults();
  var _isLoading = true;
  String? _testingEndpointId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await widget.storage.loadApiConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(error.toString());
    }
  }

  Future<void> _saveConfig(ApiConfig config, [String? message]) async {
    await widget.storage.saveApiConfig(config);
    if (!mounted) return;
    setState(() => _config = config);
    if (message != null) _showSnack(message);
  }

  Future<void> _editEndpoint([AiEndpointConfig? endpoint]) async {
    final saved = await _endpointDialog(endpoint: endpoint);
    if (saved == null) return;
    await _saveConfig(_config.upsertEndpoint(saved), '配置已保存');
  }

  Future<void> _duplicateEndpoint(AiEndpointConfig endpoint) async {
    final saved = await _endpointDialog(endpoint: endpoint, duplicate: true);
    if (saved == null) return;
    await _saveConfig(_config.upsertEndpoint(saved), '配置已复制');
  }

  Future<void> _deleteEndpoint(AiEndpointConfig endpoint) async {
    final ok = await showConfirmDialog(
      context: context,
      title: '删除 API 配置',
      content: context.t('确定删除这个 API 配置吗？'),
      confirmLabel: '删除',
    );
    if (!ok) return;
    await _saveConfig(_config.removeEndpoint(endpoint.id), '配置已删除');
  }

  Future<void> _testEndpoint(AiEndpointConfig endpoint) async {
    final error = _validateEndpoint(endpoint);
    if (error != null) {
      _showSnack(error);
      return;
    }

    setState(() => _testingEndpointId = endpoint.id);
    try {
      final reply = await widget.aiService.sendMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: const [
          {'role': 'system', 'content': '你是 API 连接测试助手。'},
          {'role': 'user', 'content': '请只回复 OK。'},
        ],
      );
      if (!mounted) return;
      _showSnack('${endpoint.name} 连接成功：$reply');
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _testingEndpointId = null);
    }
  }

  Future<AiEndpointConfig?> _endpointDialog({
    AiEndpointConfig? endpoint,
    bool duplicate = false,
  }) async {
    final now = DateTime.now();
    final nameController = TextEditingController(
      text: duplicate
          ? '${endpoint?.name ?? context.t('模型配置')} copy'
          : endpoint?.name ?? '',
    );
    final apiKeyController = TextEditingController(
      text: endpoint?.apiKey ?? '',
    );
    final baseUrlController = TextEditingController(
      text: endpoint?.baseUrl ?? '',
    );
    final modelController = TextEditingController(text: endpoint?.model ?? '');
    var enabled = endpoint?.enabled ?? true;
    var obscureApiKey = true;

    final saved = await showDialog<AiEndpointConfig>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            context.t(endpoint == null || duplicate ? '添加配置' : '编辑配置'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: context.t('名称')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyController,
                  obscureText: obscureApiKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    suffixIcon: IconButton(
                      tooltip: context.t(
                        obscureApiKey ? '显示 API Key' : '隐藏 API Key',
                      ),
                      onPressed: () {
                        setDialogState(() => obscureApiKey = !obscureApiKey);
                      },
                      icon: Icon(
                        obscureApiKey ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.example.com/v1',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText: 'deepseek-chat / gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.t('启用配置')),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('取消')),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                Navigator.of(context).pop(
                  AiEndpointConfig(
                    id: duplicate || endpoint == null
                        ? _newEndpointId()
                        : endpoint.id,
                    name: name.isEmpty ? context.t('模型配置') : name,
                    apiKey: apiKeyController.text.trim(),
                    baseUrl: baseUrlController.text.trim(),
                    model: modelController.text.trim(),
                    enabled: enabled,
                    createdAt: duplicate || endpoint == null
                        ? now
                        : endpoint.createdAt,
                    updatedAt: now,
                  ),
                );
              },
              child: Text(context.t('保存')),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    apiKeyController.dispose();
    baseUrlController.dispose();
    modelController.dispose();
    return saved;
  }

  String? _validateEndpoint(AiEndpointConfig endpoint) {
    if (endpoint.apiKey.trim().isEmpty) return 'API Key 为空，请先配置。';
    if (endpoint.baseUrl.trim().isEmpty) return 'Base URL 为空，请先配置。';
    if (endpoint.model.trim().isEmpty) return 'Model 为空，请先配置。';
    return null;
  }

  String _newEndpointId() {
    return 'endpoint_${DateTime.now().microsecondsSinceEpoch}';
  }

  void _showSnack(String message) {
    context.showSnack(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('API 配置')),
        actions: [
          IconButton(
            tooltip: context.t('添加配置'),
            onPressed: () => _editEndpoint(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AdaptivePage(
              child: _config.endpoints.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
                      itemCount: _config.endpoints.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _endpointTile(_config.endpoints[index]),
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editEndpoint(),
        icon: const Icon(Icons.add),
        label: Text(context.t('添加配置')),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, size: 48),
          const SizedBox(height: 12),
          Text(context.t('还没有 API 配置')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _editEndpoint(),
            icon: const Icon(Icons.add),
            label: Text(context.t('添加配置')),
          ),
        ],
      ),
    );
  }

  Widget _endpointTile(AiEndpointConfig endpoint) {
    final isDefault = endpoint.id == _config.defaultEndpointId;
    final isTesting = endpoint.id == _testingEndpointId;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          endpoint.enabled ? Icons.memory : Icons.memory_outlined,
          color: endpoint.enabled ? null : Theme.of(context).disabledColor,
        ),
        title: Row(
          children: [
            Flexible(child: Text(endpoint.name)),
            if (isDefault) ...[
              const SizedBox(width: 8),
              Chip(label: Text(context.t('默认模型'))),
            ],
          ],
        ),
        subtitle: Text(
          [
            endpoint.model.isEmpty ? context.t('未填写模型') : endpoint.model,
            endpoint.baseUrl.isEmpty
                ? context.t('未填写 Base URL')
                : endpoint.baseUrl,
            endpoint.enabled ? context.t('已启用') : context.t('已禁用'),
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: isTesting
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : PopupMenuButton<_EndpointAction>(
                onSelected: (action) => _handleAction(action, endpoint),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _EndpointAction.edit,
                    child: ListTile(
                      leading: const Icon(Icons.edit),
                      title: Text(context.t('编辑配置')),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EndpointAction.duplicate,
                    child: ListTile(
                      leading: const Icon(Icons.copy),
                      title: Text(context.t('复制配置')),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EndpointAction.test,
                    child: ListTile(
                      leading: const Icon(Icons.wifi_tethering),
                      title: Text(context.t('测试连接')),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EndpointAction.setDefault,
                    enabled: !isDefault && endpoint.enabled,
                    child: ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(context.t('设为默认')),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EndpointAction.toggle,
                    child: ListTile(
                      leading: Icon(
                        endpoint.enabled
                            ? Icons.toggle_off_outlined
                            : Icons.toggle_on_outlined,
                      ),
                      title: Text(
                        context.t(endpoint.enabled ? '禁用配置' : '启用配置'),
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EndpointAction.delete,
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(context.t('删除 API 配置')),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _handleAction(
    _EndpointAction action,
    AiEndpointConfig endpoint,
  ) async {
    switch (action) {
      case _EndpointAction.edit:
        await _editEndpoint(endpoint);
        break;
      case _EndpointAction.duplicate:
        await _duplicateEndpoint(endpoint);
        break;
      case _EndpointAction.test:
        await _testEndpoint(endpoint);
        break;
      case _EndpointAction.setDefault:
        await _saveConfig(
          _config.copyWith(defaultEndpointId: endpoint.id),
          '已设为默认模型',
        );
        break;
      case _EndpointAction.toggle:
        await _saveConfig(
          _config.upsertEndpoint(
            endpoint.copyWith(
              enabled: !endpoint.enabled,
              updatedAt: DateTime.now(),
            ),
          ),
          endpoint.enabled ? '配置已禁用' : '配置已启用',
        );
        break;
      case _EndpointAction.delete:
        await _deleteEndpoint(endpoint);
        break;
    }
  }
}

enum _EndpointAction { edit, duplicate, test, setDefault, toggle, delete }
