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
import 'qq_notification_help_screen.dart';
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
  final _packageName = TextEditingController();
  final _sendButtonViewId = TextEditingController();
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
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshNativeStatus());
    }
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
      _packageName.text = settings.notificationPackageName;
      _sendButtonViewId.text = settings.accessibilitySendButtonViewId;
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
    for (final controller in [
      _bridgeToken,
      _maxReply,
      _chunk,
      _timeout,
      _packageName,
      _sendButtonViewId,
    ]) {
      controller.dispose();
    }
    widget.runtime?.removeListener(_runtimeChanged);
    super.dispose();
  }

  Future<void> _save(QqIntegrationSettings value) async {
    await widget.storage.saveQqIntegrationSettings(value);
    if (!mounted) return;
    setState(() => _settings = value);
    await widget.runtime?.applySettings(value, bindings: _bindings);
  }

  Future<void> _setMode(QqIntegrationMode mode) async {
    if (widget.runtime?.running == true && mode != _settings.mode) {
      await widget.runtime!.stop();
    }
    await _save(_settings.copyWith(mode: mode, enabled: true));
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

  Future<void> _saveNotificationSettings() async {
    if (_packageName.text.trim().isEmpty) {
      throw StateError(context.t('QQ 包名不能为空。'));
    }
    await _save(
      _settings.copyWith(
        notificationPackageName: _packageName.text,
        accessibilitySendButtonViewId: _sendButtonViewId.text,
      ),
    );
    if (!mounted) return;
    _snack(context.t('通知配置已保存'));
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
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime? value) => value == null
      ? context.t('无')
      : value.toLocal().toString().split('.').first;

  Future<void> _copyBridgeToken() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('复制 Bridge Token')),
        content: Text(context.t('Token 只能粘贴到本机 Termux，不要发送给别人。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('复制')),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await Clipboard.setData(ClipboardData(text: _bridgeToken.text));
    if (mounted) _snack(context.t('Bridge Token 已复制'));
  }

  Future<void> _openBindings() async {
    final mode = _settings.mode == QqIntegrationMode.disabled
        ? QqIntegrationMode.oneBot
        : _settings.mode;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QqContactBindingsScreen(
          storage: widget.storage,
          mode: mode,
          nativeBridge: widget.runtime?.nativeBridge,
          isAndroid: widget.isAndroid,
          onBindingsChanged: (bindings) async {
            if (mounted) setState(() => _bindings = bindings);
            await widget.runtime?.applySettings(_settings, bindings: bindings);
          },
        ),
      ),
    );
    await _load();
  }

  Future<void> _permissionDisclosure({required bool accessibility}) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t(accessibility ? '无障碍权限披露' : '通知权限披露')),
        content: Text(
          context.t(
            accessibility
                ? '仅在 QQ 通知没有快捷回复时使用。Whisnya 会打开触发通知的 QQ 会话、核对标题、填写回复并点击一次发送。无法确认目标时不会发送。'
                : 'Whisnya 将读取 QQ 发出的消息通知，只处理你明确绑定的联系人。通知内容会保存到本地聊天记录，并发送给你配置的 AI API。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('我已了解')),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    if (accessibility) {
      await widget.runtime?.nativeBridge.openAccessibilitySettings();
    } else {
      await widget.runtime?.nativeBridge.openNotificationListenerSettings();
    }
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
    final isOneBot = _settings.mode == QqIntegrationMode.oneBot;
    final isNotification = _settings.mode == QqIntegrationMode.notification;
    final runtime = widget.runtime;
    final statusText = context.isEnglish
        ? 'Connection: ${runtime?.connectionState.name ?? 'stopped'}\n'
              'Bridge server: ${runtime?.bridgeServerRunning == true ? 'Running on 127.0.0.1:${runtime!.bridgePort}' : 'Stopped'}\n'
              'Bridge: ${runtime?.bridgeOnline == true ? 'Online' : 'Offline'} · '
              'NapCat: ${runtime?.napcatConnected == true ? 'Connected' : 'Disconnected'}\n'
              'QQ account: ${runtime?.accountId.isNotEmpty == true ? '${runtime!.accountId} ${runtime.nickname}' : 'None'}\n'
              'Last heartbeat: ${_formatDateTime(runtime?.lastHeartbeatAt)}\n'
              'Last message: ${_formatDateTime(runtime?.lastMessageAt)}\n'
              'Last reply: ${_formatDateTime(runtime?.lastReplyAt)}\n'
              'Queue: ${runtime?.queuedMessages ?? 0}\n'
              'Last error: ${runtime?.lastError.isNotEmpty == true ? runtime!.lastError : 'None'}\n'
              'Contacts: ${_bindings.where((item) => item.mode == _settings.mode && item.enabled).length} · '
              'Notification access: ${_nativeStatus['notificationAccess'] == true ? 'On' : 'Off'} · '
              'Listener: ${_nativeStatus['notificationListenerConnected'] == true ? 'Connected' : 'Disconnected'} · '
              'Foreground notification: ${_nativeStatus['notificationPermission'] == true ? 'On' : 'Off'} · '
              'Accessibility: ${_nativeStatus['accessibilityAccess'] == true ? 'On' : 'Off'}'
        : '连接：${runtime?.connectionState.name ?? 'stopped'}\n'
              'Bridge 服务：${runtime?.bridgeServerRunning == true ? '运行于 127.0.0.1:${runtime!.bridgePort}' : '已停止'}\n'
              'Bridge：${runtime?.bridgeOnline == true ? '在线' : '离线'} · '
              'NapCat：${runtime?.napcatConnected == true ? '已连接' : '未连接'}\n'
              'QQ 账号：${runtime?.accountId.isNotEmpty == true ? '${runtime!.accountId} ${runtime.nickname}' : '无'}\n'
              '最后心跳：${_formatDateTime(runtime?.lastHeartbeatAt)}\n'
              '最后消息：${_formatDateTime(runtime?.lastMessageAt)}\n'
              '最后回复：${_formatDateTime(runtime?.lastReplyAt)}\n'
              '队列：${runtime?.queuedMessages ?? 0}\n'
              '最后错误：${runtime?.lastError.isNotEmpty == true ? runtime!.lastError : '无'}\n'
              '联系人：${_bindings.where((item) => item.mode == _settings.mode && item.enabled).length} · '
              '通知读取：${_nativeStatus['notificationAccess'] == true ? '已开' : '未开'} · '
              '监听服务：${_nativeStatus['notificationListenerConnected'] == true ? '已连接' : '未连接'} · '
              '前台通知：${_nativeStatus['notificationPermission'] == true ? '已开' : '未开'} · '
              '无障碍：${_nativeStatus['accessibilityAccess'] == true ? '已开' : '未开'}';
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
              subtitle: Text(
                context.t(
                  'NapCat 可能掉线、失效或触发账号风险；通知和无障碍依赖 QQ 当前格式。只使用不重要的 QQ 小号。',
                ),
              ),
            ),
          ),
          if (!widget.isAndroid)
            ListTile(title: Text(context.t('当前仅 Android 支持手机后台 QQ 接入'))),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<QqIntegrationMode>(
              segments: [
                ButtonSegment(
                  value: QqIntegrationMode.oneBot,
                  label: Text(context.t('NapCat / Termux')),
                  icon: const Icon(Icons.cable),
                ),
                ButtonSegment(
                  value: QqIntegrationMode.notification,
                  label: Text(context.t('通知监听')),
                  icon: const Icon(Icons.notifications_outlined),
                ),
              ],
              selected: _settings.mode == QqIntegrationMode.disabled
                  ? const {}
                  : {_settings.mode},
              emptySelectionAllowed: true,
              onSelectionChanged: (values) {
                if (values.isNotEmpty) {
                  unawaited(_setMode(values.single));
                }
              },
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
            subtitle: Text(context.t('强制白名单；每位联系人绑定一个角色和独立会话')),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openBindings,
          ),
          if (isOneBot) _oneBotSection(),
          if (isNotification) _notificationSection(),
          _replySection(),
          _section(context.t('权限和隐私'), [
            ListTile(
              title: Text(context.t('电池优化设置')),
              subtitle: Text(context.t('Termux 与 Whisnya 都建议关闭电池优化')),
              onTap: widget.isAndroid
                  ? widget.runtime?.nativeBridge.openBatteryOptimizationSettings
                  : null,
            ),
            SwitchListTile(
              title: Text(context.t('诊断日志')),
              subtitle: Text(
                context.t('最多 200 条，不记录消息原文、回复原文、API Key 或 token'),
              ),
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

  Widget _notificationSection() => _section(context.t('通知监听配置'), [
    ListTile(
      title: Text(context.t('通知读取权限')),
      subtitle: Text(
        context.t(_nativeStatus['notificationAccess'] == true ? '已开启' : '未开启'),
      ),
      trailing: const Icon(Icons.open_in_new),
      onTap: widget.isAndroid
          ? () => _permissionDisclosure(accessibility: false)
          : null,
    ),
    ListTile(
      title: Text(context.t('应用通知权限')),
      subtitle: Text(
        context.t(
          _nativeStatus['notificationPermission'] == true ? '已开启' : '未开启',
        ),
      ),
      trailing: const Icon(Icons.open_in_new),
      onTap: widget.isAndroid
          ? widget.runtime?.nativeBridge.openAppNotificationSettings
          : null,
    ),
    ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(context.t('捕获下一条 QQ 私聊通知')),
      subtitle: Text(context.t('进入联系人绑定后开始 60 秒捕获')),
      onTap: _openBindings,
    ),
    SwitchListTile(
      title: Text(context.t('快捷回复')),
      subtitle: Text(context.t('优先使用通知 RemoteInput，不打开 QQ')),
      value: _settings.notificationRemoteInputEnabled,
      onChanged: (value) =>
          _save(_settings.copyWith(notificationRemoteInputEnabled: value)),
    ),
    SwitchListTile(
      title: Text(context.t('无障碍兜底')),
      subtitle: Text(context.t('只在快捷回复不存在或失败时使用')),
      value: _settings.accessibilityFallbackEnabled,
      onChanged: (value) =>
          _save(_settings.copyWith(accessibilityFallbackEnabled: value)),
    ),
    SwitchListTile(
      title: Text(context.t('发送后返回 Whisnya')),
      subtitle: Text(context.t('仅无障碍兜底发送成功后生效')),
      value: _settings.returnAfterAccessibilitySend,
      onChanged: (value) => unawaited(
        _save(_settings.copyWith(returnAfterAccessibilitySend: value)),
      ),
    ),
    SwitchListTile(
      title: Text(context.t('发送失败时显示提示')),
      value: _settings.sendFailureNotice,
      onChanged: (value) =>
          unawaited(_save(_settings.copyWith(sendFailureNotice: value))),
    ),
    ListTile(
      title: Text(context.t('无障碍服务')),
      subtitle: Text(
        context.t(_nativeStatus['accessibilityAccess'] == true ? '已开启' : '未开启'),
      ),
      onTap: widget.isAndroid
          ? () => _permissionDisclosure(accessibility: true)
          : null,
    ),
    Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _packageName,
            decoration: InputDecoration(labelText: context.t('QQ 包名')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sendButtonViewId,
            decoration: InputDecoration(
              labelText: context.t('发送按钮 ViewId（可选）'),
              helperText: context.t('仅在标题严格匹配后用于无障碍兜底'),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => _run(_saveNotificationSettings),
              child: Text(context.t('保存通知配置')),
            ),
          ),
        ],
      ),
    ),
    ListTile(
      title: Text(context.t('使用说明')),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const QqNotificationHelpScreen(),
        ),
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
      onChanged: (value) => setState(() {
        _settings = _settings.copyWith(mergeWindowMilliseconds: value.round());
      }),
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
      onChanged: (value) => setState(() {
        _settings = _settings.copyWith(replyDelayMilliseconds: value.round());
      }),
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
            decoration: InputDecoration(
              labelText: context.t('最大回复字符（100–8000）'),
            ),
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
            decoration: InputDecoration(
              labelText: context.t('AI 超时秒数（15–300）'),
            ),
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
        subtitle: Text(context.t('开始与结束相同表示全天静默')),
        trailing: Text(_formatTime(_settings.quietHoursEndMinutes)),
        onTap: () => _pickQuietTime(start: false),
      ),
  ]);
}
