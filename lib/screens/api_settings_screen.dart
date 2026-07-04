import 'package:flutter/material.dart';

import '../models/ai_provider.dart';
import '../models/api_config.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';

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
  final _apiKeyControllers = <AiProvider, TextEditingController>{};
  final _baseUrlControllers = <AiProvider, TextEditingController>{};
  final _modelControllers = <AiProvider, TextEditingController>{};

  var _config = ApiConfig.defaults();
  var _isLoading = true;
  AiProvider? _testingProvider;

  @override
  void initState() {
    super.initState();
    for (final provider in AiProvider.values) {
      _apiKeyControllers[provider] = TextEditingController();
      _baseUrlControllers[provider] = TextEditingController();
      _modelControllers[provider] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      ..._apiKeyControllers.values,
      ..._baseUrlControllers.values,
      ..._modelControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await widget.storage.loadApiConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _isLoading = false;
      });
      _syncControllers();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(error.toString());
    }
  }

  void _syncControllers() {
    for (final provider in AiProvider.values) {
      final config = _config.get(provider);
      _apiKeyControllers[provider]!.text = config.apiKey;
      _baseUrlControllers[provider]!.text = config.baseUrl;
      _modelControllers[provider]!.text = config.model;
    }
  }

  ApiProviderConfig _configFromControllers(AiProvider provider) {
    return ApiProviderConfig(
      apiKey: _apiKeyControllers[provider]!.text.trim(),
      baseUrl: _baseUrlControllers[provider]!.text.trim(),
      model: _modelControllers[provider]!.text.trim(),
    );
  }

  Future<void> _save(AiProvider provider, {bool silent = false}) async {
    final providerConfig = _configFromControllers(provider);
    final nextConfig = _config.copyWithProvider(provider, providerConfig);
    await widget.storage.saveApiConfig(nextConfig);
    if (!mounted) return;
    setState(() => _config = nextConfig);
    if (!silent) {
      _showSnack('${provider.label} 配置已保存');
    }
  }

  Future<void> _clear(AiProvider provider) async {
    _apiKeyControllers[provider]!.clear();
    _baseUrlControllers[provider]!.clear();
    _modelControllers[provider]!.clear();
    await _save(provider);
  }

  Future<void> _test(AiProvider provider) async {
    setState(() => _testingProvider = provider);
    try {
      await _save(provider, silent: true);
      final providerConfig = _configFromControllers(provider);
      final reply = await widget.aiService.sendMessage(
        provider: provider.id,
        apiKey: providerConfig.apiKey,
        baseUrl: providerConfig.baseUrl,
        model: providerConfig.model,
        messages: const [
          {'role': 'system', 'content': '你是 API 连接测试助手。'},
          {'role': 'user', 'content': '请只回复 OK。'},
        ],
      );
      if (!mounted) return;
      _showSnack('${provider.label} 连接成功：$reply');
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _testingProvider = null);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(context.t(message))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('API 设置'))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                for (final provider in AiProvider.values)
                  _ProviderConfigPanel(
                    provider: provider,
                    apiKeyController: _apiKeyControllers[provider]!,
                    baseUrlController: _baseUrlControllers[provider]!,
                    modelController: _modelControllers[provider]!,
                    isTesting: _testingProvider == provider,
                    onSave: () => _save(provider),
                    onClear: () => _clear(provider),
                    onTest: () => _test(provider),
                  ),
              ],
            ),
    );
  }
}

class _ProviderConfigPanel extends StatefulWidget {
  const _ProviderConfigPanel({
    required this.provider,
    required this.apiKeyController,
    required this.baseUrlController,
    required this.modelController,
    required this.isTesting,
    required this.onSave,
    required this.onClear,
    required this.onTest,
  });

  final AiProvider provider;
  final TextEditingController apiKeyController;
  final TextEditingController baseUrlController;
  final TextEditingController modelController;
  final bool isTesting;
  final VoidCallback onSave;
  final VoidCallback onClear;
  final VoidCallback onTest;

  @override
  State<_ProviderConfigPanel> createState() => _ProviderConfigPanelState();
}

class _ProviderConfigPanelState extends State<_ProviderConfigPanel> {
  var _obscureApiKey = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.provider.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                suffixIcon: IconButton(
                  tooltip: context.t(
                    _obscureApiKey ? '显示 API Key' : '隐藏 API Key',
                  ),
                  onPressed: () {
                    setState(() => _obscureApiKey = !_obscureApiKey);
                  },
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.example.com/v1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.modelController,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'deepseek-chat / gpt-4o-mini',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: widget.onSave,
                  icon: const Icon(Icons.save),
                  label: Text(context.t('保存')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.clear),
                  label: Text(context.t('清空')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.isTesting ? null : widget.onTest,
                  icon: widget.isTesting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(context.t('测试连接')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
