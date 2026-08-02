class UnifiedQqReply {
  const UnifiedQqReply({
    required this.externalUserId,
    required this.bindingId,
    required this.sessionId,
    required this.text,
    required this.createdAt,
  });

  final String externalUserId;
  final String bindingId;
  final String sessionId;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'externalUserId': externalUserId,
    'bindingId': bindingId,
    'sessionId': sessionId,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };
}
