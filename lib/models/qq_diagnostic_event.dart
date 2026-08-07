import 'qq_integration_settings.dart';

enum QqDiagnosticEventType {
  received,
  ignoredDuplicate,
  ignoredUnknownContact,
  ignoredQuietHours,
  merged,
  queued,
  aiStarted,
  aiCompleted,
  replySent,
  replyFailed,
  connectionChanged,
  permissionChanged,
  captureStarted,
  captureCompleted,
  notificationRejected,
  accessibilityAborted,
}

class QqDiagnosticEvent {
  const QqDiagnosticEvent({
    required this.time,
    required this.mode,
    this.contactDisplayName = '',
    this.messageIdSuffix = '',
    required this.eventType,
    required this.success,
    this.transport = '',
    this.durationMilliseconds = 0,
    this.replyLength = 0,
    this.errorCode = '',
    this.errorSummary = '',
  });

  final DateTime time;
  final QqIntegrationMode mode;
  final String contactDisplayName;
  final String messageIdSuffix;
  final QqDiagnosticEventType eventType;
  final bool success;
  final String transport;
  final int durationMilliseconds;
  final int replyLength;
  final String errorCode;
  final String errorSummary;

  factory QqDiagnosticEvent.fromJson(
    Map<String, dynamic> json,
  ) => QqDiagnosticEvent(
    time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
    mode: qqIntegrationModeFromJson(json['mode']),
    contactDisplayName: json['contactDisplayName'] as String? ?? '',
    messageIdSuffix: json['messageIdSuffix'] as String? ?? '',
    eventType: QqDiagnosticEventType.values.firstWhere(
      (value) => value.name == json['eventType'],
      orElse: () => QqDiagnosticEventType.replyFailed,
    ),
    success: json['success'] as bool? ?? false,
    transport: json['transport'] as String? ?? '',
    durationMilliseconds: (json['durationMilliseconds'] as num?)?.toInt() ?? 0,
    replyLength: (json['replyLength'] as num?)?.toInt() ?? 0,
    errorCode: json['errorCode'] as String? ?? '',
    errorSummary: sanitizeQqDiagnosticText(
      json['errorSummary'] as String? ?? '',
    ),
  );

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'mode': mode.name,
    'contactDisplayName': contactDisplayName,
    'messageIdSuffix': messageIdSuffix.length <= 8
        ? messageIdSuffix
        : messageIdSuffix.substring(messageIdSuffix.length - 8),
    'eventType': eventType.name,
    'success': success,
    'transport': transport,
    'durationMilliseconds': durationMilliseconds,
    'replyLength': replyLength,
    'errorCode': errorCode,
    'errorSummary': sanitizeQqDiagnosticText(errorSummary),
  };
}

String sanitizeQqDiagnosticText(String value) {
  var result = value.replaceAll(
    RegExp(r'(bearer|token|api[_ -]?key)\s*[:=]?\s*\S+', caseSensitive: false),
    r'$1 [REDACTED]',
  );
  result = result.replaceAll(RegExp(r'[A-Za-z]:\\[^\s]+'), '[PATH]');
  return result.length <= 240 ? result : result.substring(0, 240);
}
