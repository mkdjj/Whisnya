// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/api_config.dart';
import '../../models/qq_bridge_status.dart';
import '../../models/qq_contact_binding.dart';
import '../../models/qq_integration_settings.dart';
import '../../models/unified_qq_message.dart';
import '../ai/ai_gateway.dart';
import '../local_storage_service.dart';
import 'android/qq_native_bridge.dart';
import 'background_character_chat_service.dart';
import 'local_bridge_server.dart';
import 'qq_delivery_fence.dart';
import 'qq_exceptions.dart';
import 'qq_message_debouncer.dart';
import 'qq_message_processor.dart';
import 'qq_reply_splitter.dart';

class QqIntegrationRuntime extends ChangeNotifier {
  QqIntegrationRuntime({
    required LocalStorageService storage,
    required AiGateway aiGateway,
    QqNativeBridge? nativeBridge,
    LocalQqBridgeServer? localBridgeServer,
  }) : _storage = storage,
       _aiGateway = aiGateway,
       nativeBridge = nativeBridge ?? QqNativeBridge() {
    _localBridgeServer =
        localBridgeServer ??
        LocalQqBridgeServer(
          onMessage: _handleLocalBridgeMessage,
          loadConfig: _loadLocalBridgeConfig,
          onStatusChanged: _onLocalBridgeStatusChanged,
        );
  }

  final LocalStorageService _storage;
  final AiGateway _aiGateway;
  final QqNativeBridge nativeBridge;
  late final LocalQqBridgeServer _localBridgeServer;
  QqMessageProcessor? _processor;
  StreamSubscription<Map<String, dynamic>>? _nativeEvents;
  QqIntegrationSettings _settings = const QqIntegrationSettings();
  var _mergeWindowMilliseconds = -1;
  var _running = false;
  var _paused = false;
  var _runGeneration = 0;
  var _accountId = '';
  var _nickname = '';
  var _napcatConnected = false;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastMessageAt;
  DateTime? _lastReplyAt;
  var _lastError = '';

  bool get running => _running;
  bool get paused => _paused;
  bool get bridgeServerRunning => _localBridgeServer.isRunning;
  bool get bridgeOnline => _localBridgeServer.bridgeOnline;
  int get bridgePort => _localBridgeServer.port;
  bool get napcatConnected => _napcatConnected;
  DateTime? get lastHeartbeatAt => _lastHeartbeatAt;
  String get accountId => _accountId;
  String get nickname => _nickname;
  DateTime? get lastMessageAt => _lastMessageAt;
  DateTime? get lastReplyAt => _lastReplyAt;
  String get lastError => _lastError;
  int get queuedMessages => _processor?.queuedCount ?? 0;

  QqConnectionState get connectionState {
    if (!_running || _paused) return QqConnectionState.stopped;
    if (!_localBridgeServer.isRunning) return QqConnectionState.error;
    if (!_localBridgeServer.bridgeOnline) return QqConnectionState.connecting;
    if (_napcatConnected) return QqConnectionState.connected;
    return _lastError.isEmpty
        ? QqConnectionState.reconnecting
        : QqConnectionState.error;
  }

  Future<void> initialize() async {
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
    _running = true;
    _runGeneration++;
    _lastError = '';
    final token = await _storage.loadOrCreateLocalBridgeToken();
    await _localBridgeServer.start(
      port: localQqBridgeDefaultPort,
      token: token,
    );
    await _syncNativeSettings(settings, bindings: bindings);
    notifyListeners();
    try {
      await nativeBridge.startForegroundBridge();
    } on Object {
      _running = false;
      _runGeneration++;
      await _localBridgeServer.stop();
      await _syncNativeSettings(settings, bindings: bindings);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> pause() async {
    if (!_running || _paused) return;
    _paused = true;
    _runGeneration++;
    _processor?.setPaused(true);
    await _syncNativeSettings(_settings);
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_running) {
      await start();
      return;
    }
    if (!_paused) return;
    _paused = false;
    _runGeneration++;
    _processor?.setPaused(false);
    await _syncNativeSettings(_settings);
    notifyListeners();
  }

  Future<void> stop({bool stopForeground = true}) async {
    _running = false;
    _paused = false;
    _runGeneration++;
    _processor?.setPaused(true);
    await _localBridgeServer.stop();
    await _syncNativeSettings(_settings);
    _processor?.dispose();
    _processor = null;
    _mergeWindowMilliseconds = -1;
    _accountId = '';
    _nickname = '';
    _napcatConnected = false;
    _lastHeartbeatAt = null;
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
    if (_running) {
      _runGeneration++;
      _ensureProcessor(settings);
    }
    await _syncNativeSettings(settings, bindings: bindings);
    notifyListeners();
  }

  Future<Map<String, dynamic>> _onRuntimeControl(
    Map<String, dynamic> arguments,
  ) async {
    switch (arguments['action']) {
      case 'start':
        if (!_running) await start();
      case 'pause':
        await pause();
      case 'continue':
        await resume();
      case 'stop':
        await stop(stopForeground: false);
    }
    return const {'status': 'ignored'};
  }

  Future<List<QqContactBinding>> _validateStart(
    QqIntegrationSettings settings,
  ) async {
    if (!settings.enabled || settings.mode != QqIntegrationMode.oneBot) {
      throw const QqConfigurationException(
        '请先开启 QQ 自动回复并选择 NapCat / OneBot 模式。',
      );
    }
    final bindings = (await _storage.loadQqContactBindings())
        .where(
          (binding) =>
              binding.mode == QqIntegrationMode.oneBot && binding.enabled,
        )
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
      final error = endpointValidationError(
        api.effectiveEndpoint(character.defaultEndpointId),
      );
      if (error != null) throw QqConfigurationException(error);
    }
    if (nativeBridge.isAndroid) {
      final native = await nativeBridge.getNativeStatus();
      if (native['notificationPermission'] != true) {
        throw const QqConfigurationException('请先允许 Whisnya 显示前台通知。');
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

  Future<LocalQqBridgeConfig> _loadLocalBridgeConfig() async {
    final settings = await _storage.loadQqIntegrationSettings();
    final bindings = await _storage.loadQqContactBindings();
    return LocalQqBridgeConfig(
      enabled:
          _running &&
          !_paused &&
          settings.enabled &&
          settings.mode == QqIntegrationMode.oneBot,
      allowUsers: [
        for (final binding in bindings)
          if (binding.mode == QqIntegrationMode.oneBot && binding.enabled)
            binding.externalUserId,
      ],
    );
  }

  Future<LocalQqBridgeMessageResult> _handleLocalBridgeMessage(
    LocalQqBridgeMessage message,
  ) async {
    final settings = await _storage.loadQqIntegrationSettings();
    if (!_running || _paused || settings.mode != QqIntegrationMode.oneBot) {
      return const LocalQqBridgeMessageResult.noContent();
    }
    final generation = _runGeneration;
    _lastMessageAt = DateTime.fromMillisecondsSinceEpoch(
      message.timestamp * 1000,
      isUtc: true,
    );
    notifyListeners();
    _ensureProcessor(settings);
    final result = await _processor!.handle(
      UnifiedQqMessage(
        source: QqIntegrationMode.oneBot,
        messageId: message.messageId,
        externalUserId: message.userId,
        senderDisplayName: message.nickname,
        text: message.text,
        timestamp: _lastMessageAt ?? DateTime.now(),
        rawConversationTitle: message.nickname,
      ),
      settings: settings,
    );
    if (!_canDeliver(generation)) {
      return const LocalQqBridgeMessageResult.noContent();
    }
    if (result.status == QqProcessStatus.ignored) {
      return const LocalQqBridgeMessageResult.noContent();
    }
    if (result.status == QqProcessStatus.error) {
      return LocalQqBridgeMessageResult.failure(result.message);
    }
    if (settings.replyDelayMilliseconds > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: settings.replyDelayMilliseconds),
      );
    }
    _lastReplyAt = DateTime.now();
    _lastError = '';
    notifyListeners();
    return LocalQqBridgeMessageResult.reply(
      reply: QqReplySplitter.truncate(
        result.text,
        maxReplyCharacters: settings.maxReplyCharacters,
      ),
      replies: QqReplySplitter.splitOneBot(
        result.text,
        maxReplyCharacters: settings.maxReplyCharacters,
        replyChunkCharacters: settings.replyChunkCharacters,
      ),
      sessionId: result.reply?.sessionId ?? '',
      bindingId: result.reply?.bindingId ?? '',
    );
  }

  void _onLocalBridgeStatusChanged(LocalQqBridgeStatus? status) {
    final previousError = _lastError;
    if (status == null) {
      _accountId = '';
      _nickname = '';
      _napcatConnected = false;
      _lastHeartbeatAt = null;
    } else {
      _accountId = status.selfId;
      _nickname = status.nickname;
      _napcatConnected = status.connected;
      _lastHeartbeatAt = _localBridgeServer.lastHeartbeatAt;
      _lastError = status.lastError ?? '';
    }
    notifyListeners();
    if (_lastError != previousError) {
      unawaited(_syncNativeSettings(_settings));
    }
  }

  bool _canDeliver(int generation) => qqDeliveryPermitted(
    running: _running,
    paused: _paused,
    currentGeneration: _runGeneration,
    resultGeneration: generation,
    settings: _settings,
    mode: QqIntegrationMode.oneBot,
  );

  void _handleNativeEvent(Map<String, dynamic> event) {
    if (event['type'] == 'nativeError') {
      final details = event['details'];
      _lastError = details is Map
          ? details['code']?.toString() ?? 'native_error'
          : 'native_error';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_nativeEvents?.cancel());
    unawaited(_localBridgeServer.stop());
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
          .where(
            (binding) =>
                binding.mode == QqIntegrationMode.oneBot && binding.enabled,
          )
          .length,
      'connectionState': connectionState.name,
      'bridgeServerRunning': bridgeServerRunning,
      'bridgePort': bridgePort,
      'bridgeOnline': bridgeOnline,
      'napcatConnected': _napcatConnected,
      'accountId': _accountId,
      'nickname': _nickname,
      'queuedMessages': queuedMessages,
      'lastMessageAt': _lastMessageAt?.toIso8601String() ?? '',
      'lastReplyAt': _lastReplyAt?.toIso8601String() ?? '',
      'lastHeartbeatAt': _lastHeartbeatAt?.toIso8601String() ?? '',
      'lastError': _lastError,
      'runtimeActive': _running && !_paused,
    });
  }
}
