enum QqIntegrationMode { disabled, oneBot, notification }

QqIntegrationMode qqIntegrationModeFromJson(Object? value) {
  final name = value is String ? value : '';
  return QqIntegrationMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => QqIntegrationMode.disabled,
  );
}

class QqIntegrationSettings {
  const QqIntegrationSettings({
    this.enabled = false,
    this.mode = QqIntegrationMode.disabled,
    this.defaultCharacterId = '',
    this.mergeWindowMilliseconds = 1800,
    this.replyDelayMilliseconds = 500,
    this.maxReplyCharacters = 1200,
    this.replyChunkCharacters = 500,
    this.requestTimeoutSeconds = 90,
    this.quietHoursEnabled = false,
    this.quietHoursStartMinutes = 0,
    this.quietHoursEndMinutes = 0,
    this.oneBotHost = '127.0.0.1',
    this.oneBotPort = 3001,
    this.oneBotPath = '',
    this.oneBotSecure = false,
    this.oneBotAutoReconnect = true,
    this.allowInsecureRemoteOneBot = false,
    this.notificationPackageName = 'com.tencent.mobileqq',
    this.notificationRemoteInputEnabled = true,
    this.accessibilityFallbackEnabled = false,
    this.returnAfterAccessibilitySend = true,
    this.sendFailureNotice = true,
    this.diagnosticLoggingEnabled = true,
  });

  final bool enabled;
  final QqIntegrationMode mode;
  final String defaultCharacterId;
  final int mergeWindowMilliseconds;
  final int replyDelayMilliseconds;
  final int maxReplyCharacters;
  final int replyChunkCharacters;
  final int requestTimeoutSeconds;
  final bool quietHoursEnabled;
  final int quietHoursStartMinutes;
  final int quietHoursEndMinutes;
  final String oneBotHost;
  final int oneBotPort;
  final String oneBotPath;
  final bool oneBotSecure;
  final bool oneBotAutoReconnect;
  final bool allowInsecureRemoteOneBot;
  final String notificationPackageName;
  final bool notificationRemoteInputEnabled;
  final bool accessibilityFallbackEnabled;
  final bool returnAfterAccessibilitySend;
  final bool sendFailureNotice;
  final bool diagnosticLoggingEnabled;

  bool get isOneBotHostLoopback {
    final host = oneBotHost.trim().toLowerCase();
    return host == 'localhost' ||
        host == '::1' ||
        host == '[::1]' ||
        host.startsWith('127.');
  }

  String? get oneBotConfigurationError {
    if (oneBotHost.trim().isEmpty) return 'OneBot Host 不能为空。';
    if (oneBotPort < 1 || oneBotPort > 65535) return 'OneBot 端口无效。';
    if (!oneBotSecure && !isOneBotHostLoopback && !allowInsecureRemoteOneBot) {
      return '远程明文 WebSocket 默认禁止，请使用 WSS 或明确允许风险。';
    }
    return null;
  }

  Uri get oneBotUri {
    final rawPath = oneBotPath.trim();
    final path = rawPath.isEmpty
        ? ''
        : rawPath.startsWith('/')
        ? rawPath
        : '/$rawPath';
    return Uri(
      scheme: oneBotSecure ? 'wss' : 'ws',
      host: oneBotHost.trim(),
      port: oneBotPort,
      path: path,
    );
  }

  bool isQuietAt(DateTime time) {
    if (!quietHoursEnabled) return false;
    final minute = time.hour * 60 + time.minute;
    if (quietHoursStartMinutes == quietHoursEndMinutes) return true;
    if (quietHoursStartMinutes < quietHoursEndMinutes) {
      return minute >= quietHoursStartMinutes && minute < quietHoursEndMinutes;
    }
    return minute >= quietHoursStartMinutes || minute < quietHoursEndMinutes;
  }

  QqIntegrationSettings copyWith({
    bool? enabled,
    QqIntegrationMode? mode,
    String? defaultCharacterId,
    int? mergeWindowMilliseconds,
    int? replyDelayMilliseconds,
    int? maxReplyCharacters,
    int? replyChunkCharacters,
    int? requestTimeoutSeconds,
    bool? quietHoursEnabled,
    int? quietHoursStartMinutes,
    int? quietHoursEndMinutes,
    String? oneBotHost,
    int? oneBotPort,
    String? oneBotPath,
    bool? oneBotSecure,
    bool? oneBotAutoReconnect,
    bool? allowInsecureRemoteOneBot,
    String? notificationPackageName,
    bool? notificationRemoteInputEnabled,
    bool? accessibilityFallbackEnabled,
    bool? returnAfterAccessibilitySend,
    bool? sendFailureNotice,
    bool? diagnosticLoggingEnabled,
  }) => QqIntegrationSettings.fromJson({
    ...toJson(),
    if (enabled != null) 'enabled': enabled,
    if (mode != null) 'mode': mode.name,
    if (defaultCharacterId != null) 'defaultCharacterId': defaultCharacterId,
    if (mergeWindowMilliseconds != null)
      'mergeWindowMilliseconds': mergeWindowMilliseconds,
    if (replyDelayMilliseconds != null)
      'replyDelayMilliseconds': replyDelayMilliseconds,
    if (maxReplyCharacters != null) 'maxReplyCharacters': maxReplyCharacters,
    if (replyChunkCharacters != null)
      'replyChunkCharacters': replyChunkCharacters,
    if (requestTimeoutSeconds != null)
      'requestTimeoutSeconds': requestTimeoutSeconds,
    if (quietHoursEnabled != null) 'quietHoursEnabled': quietHoursEnabled,
    if (quietHoursStartMinutes != null)
      'quietHoursStartMinutes': quietHoursStartMinutes,
    if (quietHoursEndMinutes != null)
      'quietHoursEndMinutes': quietHoursEndMinutes,
    if (oneBotHost != null) 'oneBotHost': oneBotHost,
    if (oneBotPort != null) 'oneBotPort': oneBotPort,
    if (oneBotPath != null) 'oneBotPath': oneBotPath,
    if (oneBotSecure != null) 'oneBotSecure': oneBotSecure,
    if (oneBotAutoReconnect != null) 'oneBotAutoReconnect': oneBotAutoReconnect,
    if (allowInsecureRemoteOneBot != null)
      'allowInsecureRemoteOneBot': allowInsecureRemoteOneBot,
    if (notificationPackageName != null)
      'notificationPackageName': notificationPackageName,
    if (notificationRemoteInputEnabled != null)
      'notificationRemoteInputEnabled': notificationRemoteInputEnabled,
    if (accessibilityFallbackEnabled != null)
      'accessibilityFallbackEnabled': accessibilityFallbackEnabled,
    if (returnAfterAccessibilitySend != null)
      'returnAfterAccessibilitySend': returnAfterAccessibilitySend,
    if (sendFailureNotice != null) 'sendFailureNotice': sendFailureNotice,
    if (diagnosticLoggingEnabled != null)
      'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
  });

  factory QqIntegrationSettings.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    final maxReply = _int(value['maxReplyCharacters'], 1200, 100, 8000);
    return QqIntegrationSettings(
      enabled: value['enabled'] as bool? ?? false,
      mode: qqIntegrationModeFromJson(value['mode']),
      defaultCharacterId: (value['defaultCharacterId'] as String? ?? '').trim(),
      mergeWindowMilliseconds: _int(
        value['mergeWindowMilliseconds'],
        1800,
        0,
        10000,
      ),
      replyDelayMilliseconds: _int(
        value['replyDelayMilliseconds'],
        500,
        0,
        10000,
      ),
      maxReplyCharacters: maxReply,
      replyChunkCharacters: _int(
        value['replyChunkCharacters'],
        500,
        100,
        maxReply,
      ),
      requestTimeoutSeconds: _int(value['requestTimeoutSeconds'], 90, 15, 300),
      quietHoursEnabled: value['quietHoursEnabled'] as bool? ?? false,
      quietHoursStartMinutes: _int(value['quietHoursStartMinutes'], 0, 0, 1439),
      quietHoursEndMinutes: _int(value['quietHoursEndMinutes'], 0, 0, 1439),
      oneBotHost: (value['oneBotHost'] as String? ?? '127.0.0.1').trim(),
      oneBotPort: _int(value['oneBotPort'], 3001, 1, 65535),
      oneBotPath: (value['oneBotPath'] as String? ?? '').trim(),
      oneBotSecure: value['oneBotSecure'] as bool? ?? false,
      oneBotAutoReconnect: value['oneBotAutoReconnect'] as bool? ?? true,
      allowInsecureRemoteOneBot:
          value['allowInsecureRemoteOneBot'] as bool? ?? false,
      notificationPackageName:
          (value['notificationPackageName'] as String? ??
                  'com.tencent.mobileqq')
              .trim(),
      notificationRemoteInputEnabled:
          value['notificationRemoteInputEnabled'] as bool? ?? true,
      accessibilityFallbackEnabled:
          value['accessibilityFallbackEnabled'] as bool? ?? false,
      returnAfterAccessibilitySend:
          value['returnAfterAccessibilitySend'] as bool? ?? true,
      sendFailureNotice: value['sendFailureNotice'] as bool? ?? true,
      diagnosticLoggingEnabled:
          value['diagnosticLoggingEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'defaultCharacterId': defaultCharacterId,
    'mergeWindowMilliseconds': mergeWindowMilliseconds,
    'replyDelayMilliseconds': replyDelayMilliseconds,
    'maxReplyCharacters': maxReplyCharacters,
    'replyChunkCharacters': replyChunkCharacters,
    'requestTimeoutSeconds': requestTimeoutSeconds,
    'quietHoursEnabled': quietHoursEnabled,
    'quietHoursStartMinutes': quietHoursStartMinutes,
    'quietHoursEndMinutes': quietHoursEndMinutes,
    'oneBotHost': oneBotHost,
    'oneBotPort': oneBotPort,
    'oneBotPath': oneBotPath,
    'oneBotSecure': oneBotSecure,
    'oneBotAutoReconnect': oneBotAutoReconnect,
    'allowInsecureRemoteOneBot': allowInsecureRemoteOneBot,
    'notificationPackageName': notificationPackageName,
    'notificationRemoteInputEnabled': notificationRemoteInputEnabled,
    'accessibilityFallbackEnabled': accessibilityFallbackEnabled,
    'returnAfterAccessibilitySend': returnAfterAccessibilitySend,
    'sendFailureNotice': sendFailureNotice,
    'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
  };
}

int _int(Object? value, int fallback, int minimum, int maximum) {
  final number = value is num ? value.toInt() : fallback;
  return number.clamp(minimum, maximum);
}
