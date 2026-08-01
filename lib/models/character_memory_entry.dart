enum MemoryScope { character, session }

class CharacterMemoryEntry {
  CharacterMemoryEntry({
    required String id,
    required String characterId,
    required this.scope,
    String? sessionId,
    required String title,
    required String content,
    List<String> keywords = const [],
    int priority = 50,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  }) : id = _required(id, 'id'),
       characterId = _required(characterId, 'characterId'),
       sessionId = scope == MemoryScope.character
           ? null
           : _required(sessionId ?? '', 'sessionId'),
       title = _required(title, 'title'),
       content = _required(content, 'content'),
       keywords = List.unmodifiable(_cleanKeywords(keywords)),
       priority = priority.clamp(0, 100);

  final String id;
  final String characterId;
  final MemoryScope scope;
  final String? sessionId;
  final String title;
  final String content;
  final List<String> keywords;
  final int priority;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  CharacterMemoryEntry copyWith({
    String? id,
    String? characterId,
    MemoryScope? scope,
    String? sessionId,
    String? title,
    String? content,
    List<String>? keywords,
    int? priority,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CharacterMemoryEntry(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    scope: scope ?? this.scope,
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    content: content ?? this.content,
    keywords: keywords ?? this.keywords,
    priority: priority ?? this.priority,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory CharacterMemoryEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawKeywords = json['keywords'];
    return CharacterMemoryEntry(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      scope: _scopeFromJson(json['scope']),
      sessionId: json['sessionId'] as String?,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      keywords: rawKeywords is List
          ? rawKeywords.whereType<String>().toList()
          : const [],
      priority: (json['priority'] as num?)?.toInt() ?? 50,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'characterId': characterId,
    'scope': scope.name,
    if (sessionId != null) 'sessionId': sessionId,
    'title': title,
    'content': content,
    'keywords': keywords,
    'priority': priority,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

String _required(String value, String name) {
  final result = value.trim();
  if (result.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return result;
}

List<String> _cleanKeywords(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(value.trim().toLowerCase()))
        value.trim(),
  ];
}

MemoryScope _scopeFromJson(Object? value) => value == MemoryScope.session.name
    ? MemoryScope.session
    : MemoryScope.character;
