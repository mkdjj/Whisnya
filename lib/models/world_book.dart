class WorldBook {
  const WorldBook({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorldBook copyWith({
    String? id,
    String? name,
    String? description,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WorldBook(
    id: id ?? this.id,
    name: (name ?? this.name).trim(),
    description: (description ?? this.description).trim(),
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory WorldBook.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return WorldBook(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class WorldBookEntry {
  WorldBookEntry({
    required String id,
    required String worldBookId,
    required String title,
    required String content,
    required Iterable<String> keywords,
    int priority = 50,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  }) : id = _required(id, 'id'),
       worldBookId = _required(worldBookId, 'worldBookId'),
       title = _required(title, 'title'),
       content = _required(content, 'content'),
       keywords = List.unmodifiable(cleanWorldBookKeywords(keywords)),
       priority = priority.clamp(0, 100) {
    if (this.keywords.isEmpty) {
      throw ArgumentError.value(keywords, 'keywords', 'must not be empty');
    }
  }

  final String id;
  final String worldBookId;
  final String title;
  final String content;
  final List<String> keywords;
  final int priority;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorldBookEntry copyWith({
    String? id,
    String? worldBookId,
    String? title,
    String? content,
    Iterable<String>? keywords,
    int? priority,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WorldBookEntry(
    id: id ?? this.id,
    worldBookId: worldBookId ?? this.worldBookId,
    title: title ?? this.title,
    content: content ?? this.content,
    keywords: keywords ?? this.keywords,
    priority: priority ?? this.priority,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory WorldBookEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawKeywords = json['keywords'];
    return WorldBookEntry(
      id: json['id'] as String? ?? '',
      worldBookId: json['worldBookId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      keywords: rawKeywords is List
          ? rawKeywords.whereType<String>()
          : const <String>[],
      priority: (json['priority'] as num?)?.toInt() ?? 50,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'worldBookId': worldBookId,
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

List<String> cleanWorldBookKeywords(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    for (final part in value.split(RegExp(r'[,，\n\r]+'))) {
      final cleaned = part.trim();
      final key = cleaned.toLowerCase();
      if (cleaned.isNotEmpty && seen.add(key)) result.add(cleaned);
    }
  }
  return result;
}
