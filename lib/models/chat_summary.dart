class ChatSummary {
  const ChatSummary({
    required this.characterId,
    required this.summary,
    required this.updatedAt,
    this.summarizedMessageCount = 0,
  });

  final String characterId;
  final String summary;
  final DateTime updatedAt;
  final int summarizedMessageCount;

  factory ChatSummary.empty(String characterId) {
    return ChatSummary(
      characterId: characterId,
      summary: '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      summarizedMessageCount: 0,
    );
  }

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      characterId: json['characterId'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      summarizedMessageCount: json['summarizedMessageCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characterId': characterId,
      'summary': summary,
      'updatedAt': updatedAt.toIso8601String(),
      'summarizedMessageCount': summarizedMessageCount,
    };
  }
}
