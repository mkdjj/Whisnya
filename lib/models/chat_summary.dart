class ChatSummary {
  const ChatSummary({
    required this.characterId,
    this.sessionId = '',
    required this.summary,
    required this.updatedAt,
    this.summarizedMessageCount = 0,
  });

  final String characterId;
  final String sessionId;
  final String summary;
  final DateTime updatedAt;
  final int summarizedMessageCount;

  factory ChatSummary.empty(String characterId, [String sessionId = '']) {
    return ChatSummary(
      characterId: characterId,
      sessionId: sessionId,
      summary: '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      summarizedMessageCount: 0,
    );
  }

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      characterId: json['characterId'] is String
          ? json['characterId'] as String
          : '',
      sessionId: json['sessionId'] is String ? json['sessionId'] as String : '',
      summary: json['summary'] is String ? json['summary'] as String : '',
      updatedAt:
          DateTime.tryParse(
            json['updatedAt'] is String ? json['updatedAt'] as String : '',
          ) ??
          DateTime.now(),
      summarizedMessageCount: json['summarizedMessageCount'] is num
          ? (json['summarizedMessageCount'] as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characterId': characterId,
      'sessionId': sessionId,
      'summary': summary,
      'updatedAt': updatedAt.toIso8601String(),
      'summarizedMessageCount': summarizedMessageCount,
    };
  }
}
