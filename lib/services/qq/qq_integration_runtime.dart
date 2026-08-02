// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/api_config.dart';
import '../../models/qq_bridge_status.dart';
import '../../models/qq_contact_binding.dart';
import '../../models/qq_diagnostic_event.dart';
import '../../models/qq_integration_settings.dart';
import '../../models/unified_qq_message.dart';
import '../ai/ai_gateway.dart';
import '../local_storage_service.dart';
import 'android/qq_native_bridge.dart';
import 'background_character_chat_service.dart';
import 'onebot/onebot_client.dart';
import 'qq_exceptions.dart';
import 'qq_diagnostic_service.dart';
import 'qq_message_debouncer.dart';
import 'qq_message_processor.dart';
import 'qq_reply_splitter.dart';

class QqIntegrationRuntime extends ChangeNotifier {
  QqIntegrationRuntime({
    required LocalStorageService storage,
    required AiGateway aiGateway,
    QqNativeBridge? nativeBridge,
  }) : _storage = storage,
       _aiGateway = aiGateway,
       nativeBridge = nativeBridge ?? QqNativeBridge();

  final LocalStorageService _storage;
  final AiGateway _aiGateway;
  final QqNativeBridge nativeBridge;
  QqMessageProcessor? _processor;
  OneBotClient? _oneBot;
  StreamSubscription<UnifiedQqMessage>? _oneBotMessages;
  StreamSubscription<QqConnectionState>? _oneBotStates;
  StreamSubscription<Map<String, dynamic>>? _nativeEvents;
  QqIntegrationSettings _settings = const QqIntegrationSettings();
  var _mergeWindowMilliseconds = -1;
  var _running = false;
  var _paused = false;
  var _accountId = '';
  var _nickname = '';
  DateTime? _lastMessageAt;
  DateTime? _lastReplyAt;
  var _lastError = '';

  bool get running => _running;
  bool get paused => _paused;
  String get accountId => _accountId;
  String get nickname => _nickname;
  DateTime? get lastMessageAt => _lastMessageAt;
  DateTime? get lastReplyAt => _lastReplyAt;
  String get lastError => _lastError;
  int get queuedMessages => _processor?.queuedCount ?? 0;
  QqConnectionState get connectionState =>
      _oneBot?.state ?? QqConnectionState.stopped;

  Future<void> initialize() async {
    nativeBridge.onIncomingNotification = _onIncomingNotification;
    nativeBridge.onRuntimeControl = _onRuntimeControl;
    nativeBridge.initialize();
    _nativeEvents = nativeBridge.statusEvents.listen(_handleNativeEvent);
    _settings = await _storage.loadQqIntegrationSettings();
    await _syncNativeSettings(_settings);
  }

  Future<void> start() async {
    final settings = await _storage.loadQqIntegrationSettings();
    final bindings = await _validateStart(settings);
    await stop(stopForeground: false);
    _settings = settings;
    _ensureProcessor(settings);
    _paused = false;
    _processor!.setPaused(false);
    await _syncNativeSettings(settings, bindings: bindings);
    _running = true;
    _lastError = '';
    notifyListeners();
    try {
      await nativeBridge.startForegroundBridge();
    } on Object {
      _running = false;
      notifyListeners();
      rethrow;
    }
    if (settings.mode == QqIntegrationMode.oneBot) {
      await _startOneBot(settings);
    }
  }

  Future<void> pause() async {
    _paused = true;
    _processor?.setPaused(true);
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_running) {
      await start();
      return;
    }
    _paused = false;
    _processor?.setPaused(false);
    notifyListeners();
  }

  Future<void> stop({bool stopForeground = true}) async {
    _running = false;
    _paused = false;
    await _oneBotMessages?.cancel();
    await _oneBotStates?.cancel();
    _oneBotMessages = null;
    _oneBotStates = null;
    await _oneBot?.dispose();
    _oneBot = null;
    _processor?.dispose();
    _processor = null;
    _mergeWindowMilliseconds = -1;
    _accountId = '';
    _nickname = '';
    await nativeBridge.cancelPendingAccessibilityReply();
    if (stopForeground) await nativeBridge.stopForegroundBridge();
    notifyListeners();
  }

  Future<void> applySettings(
    QqIntegrationSettings settings, {
    List<QqContactBinding>? bindings,
  }) async {
    final mustStop =
        _running && (!settings.enabled || settings.mode != _settings.mode);
    if (mustStop) await stop();
    _settings = settings;
    if (_running) _ensureProcessor(settings);
    await _syncNativeSettings(settings, bindings: bindings);
    notifyListeners();
  }

  Future<OneBotLoginInfo> testOneBotConnection(
    QqIntegrationSettings settings,
  ) async {
    final error = settings.oneBotConfigurationError;
    if (error != null) throw QqConfigurationException(error);
    final token = await _storage.loadOneBotAccessToken();
    final current = _oneBot;
    if (current != null && current.isConnected) {
      final data = await current.callAction('get_login_info');
      final info = OneBotLoginInfo(
        accountId: data['user_id']?.toString() ?? '',
        nickname: data['nickname']?.toString() ?? '',
      );
      _rememberLogin(info);
      return info;
    }
    final temporary = OneBotClient();
    try {
      final info = await temporary.connect(
        settings.oneBotUri,
        accessToken: token,
      );
      _rememberLogin(info);
      return info;
    } finally {
      await temporary.dispose();
    }
  }

  Future<Map<String, dynamic>> _onIncomingNotification(
    Map<String, dynamic> arguments,
  ) async {
    try {
      final settings = await _storage.loadQqIntegrationSettings();
      if (!_running || settings.mode != QqIntegrationMode.notification) {
        return const {'status': 'ignored'};
      }
      _lastMessageAt = DateTime.now();
      notifyListeners();
      _ensureProcessor(settings);
      final message = UnifiedQqMessage.fromJson({
        ...arguments,
        'source': QqIntegrationMode.notification.name,
      });
      final result = await _processor!.handle(message, settings: settings);
      final json = result.toNativeJson();
      if (result.status == QqProcessStatus.reply) {
        json['text'] = QqReplySplitter.forNotification(
          result.text,
          maxReplyCharacters: settings.maxReplyCharacters,
        );
      }
      notifyListeners();
      return json;
    } on Object catch (error) {
      _rememberError(error);
      return const {'status': 'error', 'message': 'QQ 通知处理失败，请查看诊断日志。'};
    }
  }

  Future<Map<String, dynamic>> _onRuntimeControl(
    Map<String, dynamic> arguments,
  ) async {
    switch (arguments['action']) {
      case 'start':
        if (!_running) await start();
        break;
      case 'pause':
        await pause();
        break;
      case 'continue':
        await resume();
        break;
      case 'stop':
        await stop(stopForeground: false);
        break;
    }
    return const {'status': 'ignored'};
  }

  Future<List<QqContactBinding>> _validateStart(
    QqIntegrationSettings settings,
  ) async {
    if (!settings.enabled || settings.mode == QqIntegrationMode.disabled) {
      throw const QqConfigurationException('请先开启 QQ 自动回复并选择模式。');
    }
    final bindings = (await _storage.loadQqContactBindings())
        .where((binding) => binding.mode == settings.mode && binding.enabled)
        .toList();
    if (bindings.isEmpty) {
      throw const QqConfigurationException('至少需要一个启用的联系人绑定。');
    }
    final characters = await _storage.loadCharacters();
    final characterIds = characters.map((character) => character.id).toSet();
    if (bindings.any(
      (binding) => !characterIds.contains(binding.characterId),
    )) {
      throw const QqConfigurationException('联系人绑定的角色不存在。');
    }
    final api = await _storage.loadApiConfig();
    for (final binding in bindings) {
      final character = characters.firstWhere(
        (item) => item.id == binding.characterId,
      );
      final endpoint = api.effectiveEndpoint(character.defaultEndpointId);
      final error = endpointValidationError(endpoint);
      if (error != null) throw QqConfigurationException(error);
    }
    if (settings.mode == QqIntegrationMode.oneBot) {
      final error = settings.oneBotConfigurationError;
      if (error != null) throw QqConfigurationException(error);
    }
    if (nativeBridge.isAndroid) {
      final native = await nativeBridge.getNativeStatus();
      if (native['qqInstalled'] != true) {
        throw const QqConfigurationException('没有检测到配置包名对应的 QQ 应用。');
      }
      if (native['notificationPermission'] != true) {
        throw const QqConfigurationException('请先允许 Whisnya 显示前台通知。');
      }
      if (settings.mode == QqIntegrationMode.notification &&
          native['notificationAccess'] != true) {
        throw const QqConfigurationException('请先开启 QQ 通知读取权限。');
      }
    }
    return bindings;
  }

  void _ensureProcessor(QqIntegrationSettings settings) {
    if (_processor != null &&
        _mergeWindowMilliseconds == settings.mergeWindowMilliseconds) {
      return;
    }
    _processor?.dispose();
    _mergeWindowMilliseconds = settings.mergeWindowMilliseconds;
    _processor = QqMessageProcessor(
      storage: _storage,
      chatService: BackgroundCharacterChatService(
        storage: _storage,
        aiGateway: _aiGateway,
      ),
      debouncer: QqMessageDebouncer(
        mergeWindow: Duration(milliseconds: settings.mergeWindowMilliseconds),
      ),
    )..setPaused(_paused);
  }

  Future<void> _startOneBot(QqIntegrationSettings settings) async {
    final client = OneBotClient();
    _oneBot = client;
    _oneBotMessages = client.messages.listen((message) {
      unawaited(_handleOneBotMessage(message));
    });
    _oneBotStates = client.states.listen((state) {
      if (state == QqConnectionState.authenticationFailed) {
        _lastError = 'OneBot token authentication failed';
      } else if (state == QqConnectionState.error) {
        _lastError = 'OneBot connection error';
      } else if (state == QqConnectionState.connected) {
        _lastError = '';
      }
      notifyListeners();
      unawaited(_syncNativeSettings(settings));
      unawaited(
        QqDiagnosticService(_storage).record(
          settings: settings,
          mode: QqIntegrationMode.oneBot,
          eventType: QqDiagnosticEventType.connectionChanged,
          success:
              state != QqConnectionState.error &&
              state != QqConnectionState.authenticationFailed,
          transport: state.name,
          errorCode:
              state == QqConnectionState.error ||
                  state == QqConnectionState.authenticationFailed
              ? state.name
              : '',
        ),
      );
    });
    final token = await _storage.loadOneBotAccessToken();
    unawaited(
      client.start(
        uri: settings.oneBotUri,
        accessToken: token,
        autoReconnect: settings.oneBotAutoReconnect,
        onConnected: _rememberLogin,
      ),
    );
  }

  Future<void> _handleOneBotMessage(UnifiedQqMessage message) async {
    final processor = _processor;
    final client = _oneBot;
    if (!_running || processor == null || client == null) return;
    _lastMessageAt = DateTime.now();
    notifyListeners();
    try {
      final result = await processor.handle(message, settings: _settings);
      if (result.status != QqProcessStatus.reply) return;
      if (_settings.replyDelayMilliseconds > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: _settings.replyDelayMilliseconds),
        );
      }
      final chunks = QqReplySplitter.splitOneBot(
        result.text,
        maxReplyCharacters: _settings.maxReplyCharacters,
        replyChunkCharacters: _settings.replyChunkCharacters,
      );
      for (var index = 0; index < chunks.length; index++) {
        await client.sendPrivateMessage(message.externalUserId, chunks[index]);
        if (index + 1 < chunks.length) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      _lastReplyAt = DateTime.now();
      _lastError = '';
      await QqDiagnosticService(_storage).record(
        settings: _settings,
        mode: QqIntegrationMode.oneBot,
        eventType: QqDiagnosticEventType.replySent,
        success: true,
        messageId: message.messageId,
        transport: 'oneBot',
        replyLength: result.text.runes.length,
      );
    } on Object catch (error) {
      _rememberError(error);
      await QqDiagnosticService(_storage).record(
        settings: _settings,
        mode: QqIntegrationMode.oneBot,
        eventType: QqDiagnosticEventType.replyFailed,
        success: false,
        messageId: message.messageId,
        transport: 'oneBot',
        errorCode: error.runtimeType.toString(),
        errorSummary: 'OneBot reply delivery failed',
      );
    } finally {
      notifyListeners();
    }
  }

  void _rememberLogin(OneBotLoginInfo info) {
    _accountId = info.accountId;
    _nickname = info.nickname;
    _lastError = '';
    notifyListeners();
  }

  void _rememberError(Object error) {
    _lastError = error.toString();
    notifyListeners();
    unawaited(_syncNativeSettings(_settings));
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    final rawDetails = event['details'];
    final details = rawDetails is Map<Object?, Object?>
        ? {
            for (final item in rawDetails.entries)
              item.key.toString(): item.value,
          }
        : const <String, dynamic>{};
    QqDiagnosticEventType? eventType;
    var success = details['success'] as bool? ?? true;
    var transport = details['transport']?.toString() ?? '';
    switch (type) {
      case 'remoteInputSend':
        eventType = success
            ? QqDiagnosticEventType.replySent
            : QqDiagnosticEventType.replyFailed;
        transport = transport.isEmpty ? 'notificationRemoteInput' : transport;
        break;
      case 'accessibilitySend':
        eventType = success
            ? QqDiagnosticEventType.replySent
            : QqDiagnosticEventType.accessibilityAborted;
        transport = transport.isEmpty ? 'accessibility' : transport;
        break;
      case 'permissionChanged':
        eventType = QqDiagnosticEventType.permissionChanged;
        break;
      case 'notificationCapture':
        if (details['captured'] == true) {
          eventType = QqDiagnosticEventType.captureCompleted;
        } else if (details['active'] == true) {
          eventType = QqDiagnosticEventType.captureStarted;
        }
        break;
      case 'nativeError':
        eventType = QqDiagnosticEventType.replyFailed;
        success = false;
        break;
    }
    if (success && (type == 'remoteInputSend' || type == 'accessibilitySend')) {
      _lastReplyAt = DateTime.now();
      _lastError = '';
    } else if (!success) {
      _lastError = details['errorCode']?.toString() ?? 'native_error';
    }
    notifyListeners();
    if (eventType != null) {
      unawaited(
        QqDiagnosticService(_storage).record(
          settings: _settings,
          mode: QqIntegrationMode.notification,
          eventType: eventType,
          success: success,
          transport: transport,
          errorCode: details['errorCode']?.toString() ?? '',
          errorSummary: success ? '' : 'Native QQ reply operation failed',
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_nativeEvents?.cancel());
    super.dispose();
  }

  Future<void> _syncNativeSettings(
    QqIntegrationSettings settings, {
    List<QqContactBinding>? bindings,
  }) async {
    final activeBindings = bindings ?? await _storage.loadQqContactBindings();
    await nativeBridge.updateNativeQqSettings({
      ...settings.toJson(),
      'enabledContacts': activeBindings
          .where((binding) => binding.mode == settings.mode && binding.enabled)
          .length,
      'connectionState': connectionState.name,
      'accountId': _accountId,
      'nickname': _nickname,
      'queuedMessages': queuedMessages,
      'lastMessageAt': _lastMessageAt?.toIso8601String() ?? '',
      'lastReplyAt': _lastReplyAt?.toIso8601String() ?? '',
      'lastError': _lastError,
    });
  }
}
