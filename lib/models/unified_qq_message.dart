import 'qq_integration_settings.dart';

class UnifiedQqMessage {
  const UnifiedQqMessage({
    required this.source,
    required this.messageId,
    required this.externalUserId,
    required this.senderDisplayName,
    required this.text,
    required this.timestamp,
    required this.rawConversationTitle,
    this.nativeNotificationKey,
  });

  final QqIntegrationMode source;
  final String messageId;
  final String externalUserId;
  final String senderDisplayName;
  final String text;
  final DateTime timestamp;
  final String rawConversationTitle;
  final String? nativeNotificationKey;

  UnifiedQqMessage copyWith({
    QqIntegrationMode? source,
    String? messageId,
    String? externalUserId,
    String? senderDisplayName,
    String? text,
    DateTime? timestamp,
    String? rawConversationTitle,
    String? nativeNotificationKey,
  }) => UnifiedQqMessage(
    source: source ?? this.source,
    messageId: messageId ?? this.messageId,
    externalUserId: externalUserId ?? this.externalUserId,
    senderDisplayName: senderDisplayName ?? this.senderDisplayName,
    text: text ?? this.text,
    timestamp: timestamp ?? this.timestamp,
    rawConversationTitle: rawConversationTitle ?? this.rawConversationTitle,
    nativeNotificationKey: nativeNotificationKey ?? this.nativeNotificationKey,
  );

  factory UnifiedQqMessage.fromJson(Map<String, dynamic> json) =>
      UnifiedQqMessage(
        source: qqIntegrationModeFromJson(json['source']),
        messageId: (json['messageId'] as Object?)?.toString() ?? '',
        externalUserId: (json['externalUserId'] as Object?)?.toString() ?? '',
        senderDisplayName: json['senderDisplayName'] as String? ?? '',
        text: json['text'] as String? ?? '',
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        rawConversationTitle: json['rawConversationTitle'] as String? ?? '',
        nativeNotificationKey: json['nativeNotificationKey'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'messageId': messageId,
    'externalUserId': externalUserId,
    'senderDisplayName': senderDisplayName,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'rawConversationTitle': rawConversationTitle,
    if (nativeNotificationKey != null)
      'nativeNotificationKey': nativeNotificationKey,
  };
}
