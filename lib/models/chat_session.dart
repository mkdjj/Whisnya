class ChatSession {
  const ChatSession({
    required this.id,
    required this.characterId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.lastUsedAt,
    this.isArchived = false,
    this.openingMessageInitialized = false,
    this.messageCount,
  });

  final String id;
  final String characterId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastUsedAt;
  final bool isArchived;
  final bool openingMessageInitialized;
  final int? messageCount;

  ChatSession copyWith({
    String? id,
    String? characterId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    bool? isArchived,
    bool? openingMessageInitialized,
    int? messageCount,
  }) {
    return ChatSession(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isArchived: isArchived ?? this.isArchived,
      openingMessageInitialized:
          openingMessageInitialized ?? this.openingMessageInitialized,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final createdAt = _parseDate(json['createdAt']) ?? now;
    final updatedAt = _parseDate(json['updatedAt']) ?? createdAt;
    return ChatSession(
      id: _string(json['id']),
      characterId: _string(json['characterId']),
      title: normalizedTitle(
        json['title'] is String ? json['title'] as String : null,
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastUsedAt: _parseDate(json['lastUsedAt']) ?? updatedAt,
      isArchived: json['isArchived'] is bool
          ? json['isArchived'] as bool
          : false,
      openingMessageInitialized: json['openingMessageInitialized'] is bool
          ? json['openingMessageInitialized'] as bool
          : false,
      messageCount: readMessageCount(json['messageCount']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'characterId': characterId,
    'title': normalizedTitle(title),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastUsedAt': lastUsedAt.toIso8601String(),
    'isArchived': isArchived,
    'openingMessageInitialized': openingMessageInitialized,
    'messageCount': messageCount,
  };

  static String normalizedTitle(String? title) {
    final value = title?.trim() ?? '';
    return value.isEmpty ? '未命名对话' : value;
  }

  static int compare(ChatSession a, ChatSession b) {
    if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
    return b.lastUsedAt.compareTo(a.lastUsedAt);
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

int? readMessageCount(Object? raw) => raw is int && raw >= 0 ? raw : null;
