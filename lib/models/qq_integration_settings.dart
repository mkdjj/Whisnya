enum QqIntegrationMode { disabled, oneBot }

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
    this.mergeWindowMilliseconds = 1800,
    this.replyDelayMilliseconds = 500,
    this.maxReplyCharacters = 1200,
    this.replyChunkCharacters = 500,
    this.requestTimeoutSeconds = 90,
    this.quietHoursEnabled = false,
    this.quietHoursStartMinutes = 0,
    this.quietHoursEndMinutes = 0,
    this.diagnosticLoggingEnabled = true,
  });

  final bool enabled;
  final QqIntegrationMode mode;
  final int mergeWindowMilliseconds;
  final int replyDelayMilliseconds;
  final int maxReplyCharacters;
  final int replyChunkCharacters;
  final int requestTimeoutSeconds;
  final bool quietHoursEnabled;
  final int quietHoursStartMinutes;
  final int quietHoursEndMinutes;
  final bool diagnosticLoggingEnabled;

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
    int? mergeWindowMilliseconds,
    int? replyDelayMilliseconds,
    int? maxReplyCharacters,
    int? replyChunkCharacters,
    int? requestTimeoutSeconds,
    bool? quietHoursEnabled,
    int? quietHoursStartMinutes,
    int? quietHoursEndMinutes,
    bool? diagnosticLoggingEnabled,
  }) => QqIntegrationSettings.fromJson({
    'enabled': enabled ?? this.enabled,
    'mode': (mode ?? this.mode).name,
    'mergeWindowMilliseconds':
        mergeWindowMilliseconds ?? this.mergeWindowMilliseconds,
    'replyDelayMilliseconds':
        replyDelayMilliseconds ?? this.replyDelayMilliseconds,
    'maxReplyCharacters': maxReplyCharacters ?? this.maxReplyCharacters,
    'replyChunkCharacters': replyChunkCharacters ?? this.replyChunkCharacters,
    'requestTimeoutSeconds':
        requestTimeoutSeconds ?? this.requestTimeoutSeconds,
    'quietHoursEnabled': quietHoursEnabled ?? this.quietHoursEnabled,
    'quietHoursStartMinutes':
        quietHoursStartMinutes ?? this.quietHoursStartMinutes,
    'quietHoursEndMinutes': quietHoursEndMinutes ?? this.quietHoursEndMinutes,
    'diagnosticLoggingEnabled':
        diagnosticLoggingEnabled ?? this.diagnosticLoggingEnabled,
  });

  factory QqIntegrationSettings.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    final mode = qqIntegrationModeFromJson(value['mode']);
    final maxReply = _int(value['maxReplyCharacters'], 1200, 100, 8000);
    return QqIntegrationSettings(
      enabled:
          (value['enabled'] as bool? ?? false) &&
          mode != QqIntegrationMode.disabled,
      mode: mode,
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
      diagnosticLoggingEnabled:
          value['diagnosticLoggingEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'mergeWindowMilliseconds': mergeWindowMilliseconds,
    'replyDelayMilliseconds': replyDelayMilliseconds,
    'maxReplyCharacters': maxReplyCharacters,
    'replyChunkCharacters': replyChunkCharacters,
    'requestTimeoutSeconds': requestTimeoutSeconds,
    'quietHoursEnabled': quietHoursEnabled,
    'quietHoursStartMinutes': quietHoursStartMinutes,
    'quietHoursEndMinutes': quietHoursEndMinutes,
    'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
  };
}

int _int(Object? value, int fallback, int minimum, int maximum) {
  final number = value is num ? value.toInt() : fallback;
  return number.clamp(minimum, maximum);
}
