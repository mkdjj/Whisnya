enum MemoryScope { character, session }

class CharacterMemoryEntry {
  CharacterMemoryEntry({
    required String id,
    required String characterId,
    required this.scope,
    String? sessionId,
    required String title,
    required String content,
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
       priority = priority.clamp(0, 100);

  final String id;
  final String characterId;
  final MemoryScope scope;
  final String? sessionId;
  final String title;
  final String content;
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
    priority: priority ?? this.priority,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory CharacterMemoryEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return CharacterMemoryEntry(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      scope: _scopeFromJson(json['scope']),
      sessionId: json['sessionId'] as String?,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
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

MemoryScope _scopeFromJson(Object? value) => value == MemoryScope.session.name
    ? MemoryScope.session
    : MemoryScope.character;
