import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/qq_contact_binding.dart';
import '../../models/qq_integration_settings.dart';
import '../../services/local_storage_service.dart';
import '../../services/qq/local_bridge_server.dart';
import '../../services/qq/qq_integration_runtime.dart';
import '../../utils/app_i18n.dart';
import 'qq_contact_bindings_screen.dart';
import 'qq_diagnostics_screen.dart';
import 'qq_termux_help_screen.dart';

class QqIntegrationScreen extends StatefulWidget {
  QqIntegrationScreen({
    required this.storage,
    this.runtime,
    bool? isAndroid,
    super.key,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  final LocalStorageService storage;
  final QqIntegrationRuntime? runtime;
  final bool isAndroid;

  @override
  State<QqIntegrationScreen> createState() => _QqIntegrationScreenState();
}

class _QqIntegrationScreenState extends State<QqIntegrationScreen>
    with WidgetsBindingObserver {
  QqIntegrationSettings _settings = const QqIntegrationSettings();
  List<QqContactBinding> _bindings = const [];
  Map<String, dynamic> _nativeStatus = const {};
  final _bridgeToken = TextEditingController();
  final _maxReply = TextEditingController();
  final _chunk = TextEditingController();
  final _timeout = TextEditingController();
  var _loading = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.runtime?.addListener(_runtimeChanged);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshNativeStatus());
  }

  void _runtimeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final settings = await widget.storage.loadQqIntegrationSettings();
    final bindings = await widget.storage.loadQqContactBindings();
    final bridgeToken = widget.isAndroid
        ? await widget.storage.loadOrCreateLocalBridgeToken()
        : '';
    var native = <String, dynamic>{};
    if (widget.isAndroid && widget.runtime != null) {
      native = await widget.runtime!.nativeBridge.getNativeStatus();
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _bindings = bindings;
      _nativeStatus = native;
      _bridgeToken.text = bridgeToken;
      _maxReply.text = '${settings.maxReplyCharacters}';
      _chunk.text = '${settings.replyChunkCharacters}';
      _timeout.text = '${settings.requestTimeoutSeconds}';
      _loading = false;
    });
  }

  Future<void> _refreshNativeStatus() async {
    if (!widget.isAndroid || widget.runtime == null) return;
    final native = await widget.runtime!.nativeBridge.getNativeStatus();
    if (mounted) setState(() => _nativeStatus = native);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bridgeToken.dispose();
    _maxReply.dispose();
    _chunk.dispose();
    _timeout.dispose();
    widget.runtime?.removeListener(_runtimeChanged);
    super.dispose();
  }

  Future<void> _save(QqIntegrationSettings value) async {
    await widget.storage.saveQqIntegrationSettings(value);
    if (!mounted) return;
    setState(() => _settings = value);
    await widget.runtime?.applySettings(value, bindings: _bindings);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } on Object catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveReplySettings() async {
    final value = _settings.copyWith(
      maxReplyCharacters: int.tryParse(_maxReply.text) ?? 1200,
      replyChunkCharacters: int.tryParse(_chunk.text) ?? 500,
      requestTimeoutSeconds: int.tryParse(_timeout.text) ?? 90,
    );
    await _save(value);
    _maxReply.text = '${value.maxReplyCharacters}';
    _chunk.text = '${value.replyChunkCharacters}';
    _timeout.text = '${value.requestTimeoutSeconds}';
  }

  Future<void> _pickQuietTime({required bool start}) async {
    final current = start
        ? _settings.quietHoursStartMinutes
        : _settings.quietHoursEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await _save(
      start
          ? _settings.copyWith(quietHoursStartMinutes: minutes)
          : _settings.copyWith(quietHoursEndMinutes: minutes),
    );
  }

  String _formatTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  String _formatDateTime(DateTime? value) => value == null
      ? context.t('无')
      : value.toLocal().toString().split('.').first;

  Future<void> _copyBridgeToken() async {
    await Clipboard.setData(ClipboardData(text: _bridgeToken.text));
    if (mounted) _snack(context.t('Bridge Token 已复制'));
  }

  Future<void> _openBindings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QqContactBindingsScreen(
          storage: widget.storage,
          mode: QqIntegrationMode.oneBot,
          onBindingsChanged: (bindings) async {
            if (mounted) setState(() => _bindings = bindings);
            await widget.runtime?.applySettings(_settings, bindings: bindings);
          },
        ),
      ),
    );
    await _load();
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final runtime = widget.runtime;
    final statusText = context.isEnglish
        ? 'Connection: ${runtime?.connectionState.name ?? 'stopped'}\nBridge: ${runtime?.bridgeOnline == true ? 'Online' : 'Offline'}\nNapCat: ${runtime?.napcatConnected == true ? 'Connected' : 'Disconnected'}\nQQ account: ${runtime?.accountId.isNotEmpty == true ? '${runtime!.accountId} ${runtime.nickname}' : 'None'}\nLast heartbeat: ${_formatDateTime(runtime?.lastHeartbeatAt)}\nLast message: ${_formatDateTime(runtime?.lastMessageAt)}\nLast reply: ${_formatDateTime(runtime?.lastReplyAt)}\nQueue: ${runtime?.queuedMessages ?? 0}\nContacts: ${_bindings.where((item) => item.mode == QqIntegrationMode.oneBot && item.enabled).length}\nForeground notification: ${_nativeStatus['notificationPermission'] == true ? 'On' : 'Off'}'
        : '连接：${runtime?.connectionState.name ?? 'stopped'}\nBridge：${runtime?.bridgeOnline == true ? '在线' : '离线'}\nNapCat：${runtime?.napcatConnected == true ? '已连接' : '未连接'}\nQQ 账号：${runtime?.accountId.isNotEmpty == true ? '${runtime!.accountId} ${runtime.nickname}' : '无'}\n最后心跳：${_formatDateTime(runtime?.lastHeartbeatAt)}\n最后消息：${_formatDateTime(runtime?.lastMessageAt)}\n最后回复：${_formatDateTime(runtime?.lastReplyAt)}\n队列：${runtime?.queuedMessages ?? 0}\n联系人：${_bindings.where((item) => item.mode == QqIntegrationMode.oneBot && item.enabled).length}\n前台通知：${_nativeStatus['notificationPermission'] == true ? '已开启' : '未开启'}';
    return Scaffold(
      appBar: AppBar(title: Text(context.t('QQ 私聊自动回复'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text(context.t('非官方接入风险')),
              subtitle: Text(context.t('NapCat 可能掉线或失效，请只使用不重要的 QQ 小号。')),
            ),
          ),
          SwitchListTile(
            title: Text(context.t('总开关')),
            subtitle: Text(context.t('仍需手动点击“启动”才会运行')),
            value: _settings.enabled,
            onChanged: (value) => _save(
              _settings.copyWith(
                enabled: value,
                mode: value && _settings.mode == QqIntegrationMode.disabled
                    ? QqIntegrationMode.oneBot
                    : _settings.mode,
              ),
            ),
          ),
          _section(context.t('状态'), [
            ListTile(
              title: Text(context.t(runtime?.running == true ? '运行中' : '已停止')),
              subtitle: Text(statusText),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy || widget.runtime == null
                        ? null
                        : () => _run(widget.runtime!.start),
                    child: Text(context.t('启动')),
                  ),
                  OutlinedButton(
                    onPressed: _busy || widget.runtime == null
                        ? null
                        : () => _run(widget.runtime!.pause),
                    child: Text(context.t('暂停')),
                  ),
                  OutlinedButton(
                    onPressed: _busy || widget.runtime == null
                        ? null
                        : () => _run(widget.runtime!.resume),
                    child: Text(context.t('继续')),
                  ),
                  TextButton(
                    onPressed: _busy || widget.runtime == null
                        ? null
                        : () => _run(() => widget.runtime!.stop()),
                    child: Text(context.t('停止')),
                  ),
                ],
              ),
            ),
          ]),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text(context.t('联系人绑定')),
            subtitle: Text(context.t('白名单中的 QQ 号才会触发回复。')),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openBindings,
          ),
          _oneBotSection(),
          _replySection(),
          _section(context.t('权限和隐私'), [
            ListTile(
              title: Text(context.t('电池优化设置')),
              subtitle: Text(context.t('Termux 和 Whisnya 都建议关闭电池优化。')),
              onTap: widget.isAndroid
                  ? widget.runtime?.nativeBridge.openBatteryOptimizationSettings
                  : null,
            ),
            ListTile(
              title: Text(context.t('应用通知权限')),
              subtitle: Text(
                context.t(
                  _nativeStatus['notificationPermission'] == true
                      ? '已开启'
                      : '未开启',
                ),
              ),
              onTap: widget.isAndroid
                  ? widget.runtime?.nativeBridge.openAppNotificationSettings
                  : null,
            ),
            SwitchListTile(
              title: Text(context.t('诊断日志')),
              subtitle: Text(context.t('最多 200 条，不记录消息原文、API Key 或 token。')),
              value: _settings.diagnosticLoggingEnabled,
              onChanged: (value) =>
                  _save(_settings.copyWith(diagnosticLoggingEnabled: value)),
            ),
          ]),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(context.t('诊断日志')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QqDiagnosticsScreen(storage: widget.storage),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _oneBotSection() => _section(context.t('Termux / NapCat Bridge'), [
    ListTile(
      leading: const Icon(Icons.http_outlined),
      title: Text(context.t('本地 Bridge 服务')),
      subtitle: Text(
        context.t(
          '仅监听 127.0.0.1:$localQqBridgeDefaultPort，由 Termux 中的 qq_bridge 连接 NapCat。',
        ),
      ),
    ),
    ListTile(
      leading: const Icon(Icons.key_outlined),
      title: const Text('Bridge Token'),
      subtitle: Text(
        context.t(_bridgeToken.text.isEmpty ? '尚未生成' : '已生成并保存在安全存储中，不会写入备份。'),
      ),
      trailing: IconButton(
        tooltip: context.t('复制 Bridge Token'),
        icon: const Icon(Icons.copy_outlined),
        onPressed: _bridgeToken.text.isEmpty ? null : _copyBridgeToken,
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QqTermuxHelpScreen(),
              ),
            ),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(context.t('Termux 帮助')),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(context.t('刷新状态')),
          ),
        ],
      ),
    ),
  ]);

  Widget _replySection() => _section(context.t('回复设置'), [
    ListTile(
      title: Text(context.t('连续消息合并窗口')),
      subtitle: Text('${_settings.mergeWindowMilliseconds} ms'),
    ),
    Slider(
      value: _settings.mergeWindowMilliseconds.toDouble(),
      min: 0,
      max: 10000,
      divisions: 100,
      onChanged: (value) => setState(
        () => _settings = _settings.copyWith(
          mergeWindowMilliseconds: value.round(),
        ),
      ),
      onChangeEnd: (value) =>
          _save(_settings.copyWith(mergeWindowMilliseconds: value.round())),
    ),
    ListTile(
      title: Text(context.t('回复延迟')),
      subtitle: Text('${_settings.replyDelayMilliseconds} ms'),
    ),
    Slider(
      value: _settings.replyDelayMilliseconds.toDouble(),
      min: 0,
      max: 10000,
      divisions: 100,
      onChanged: (value) => setState(
        () => _settings = _settings.copyWith(
          replyDelayMilliseconds: value.round(),
        ),
      ),
      onChangeEnd: (value) =>
          _save(_settings.copyWith(replyDelayMilliseconds: value.round())),
    ),
    Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _maxReply,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.t('最大回复字符')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _chunk,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.t('OneBot 分片字符')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _timeout,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.t('AI 超时秒数')),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _saveReplySettings,
              child: Text(context.t('保存回复设置')),
            ),
          ),
        ],
      ),
    ),
    SwitchListTile(
      title: Text(context.t('静默时段')),
      subtitle: Text(context.t('支持跨午夜；命令仍可使用')),
      value: _settings.quietHoursEnabled,
      onChanged: (value) => _save(_settings.copyWith(quietHoursEnabled: value)),
    ),
    if (_settings.quietHoursEnabled)
      ListTile(
        title: Text(context.t('静默开始')),
        trailing: Text(_formatTime(_settings.quietHoursStartMinutes)),
        onTap: () => _pickQuietTime(start: true),
      ),
    if (_settings.quietHoursEnabled)
      ListTile(
        title: Text(context.t('静默结束')),
        trailing: Text(_formatTime(_settings.quietHoursEndMinutes)),
        onTap: () => _pickQuietTime(start: false),
      ),
  ]);
}
