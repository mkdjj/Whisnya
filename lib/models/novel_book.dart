class NovelRoleCandidate {
  const NovelRoleCandidate({
    required this.name,
    required this.description,
    required this.personality,
    required this.speakingStyle,
    required this.background,
  });

  final String name;
  final String description;
  final String personality;
  final String speakingStyle;
  final String background;

  factory NovelRoleCandidate.fromJson(Map<String, dynamic> json) {
    return NovelRoleCandidate(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      speakingStyle: json['speakingStyle'] as String? ?? '',
      background: json['background'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'personality': personality,
      'speakingStyle': speakingStyle,
      'background': background,
    };
  }
}

class NovelBook {
  const NovelBook({
    required this.id,
    required this.title,
    required this.textPath,
    required this.createdAt,
    required this.updatedAt,
    this.summary = '',
    this.roles = const [],
    this.selectedRoleIndex = -1,
    this.userRoleIndex = -1,
    this.isHidden = false,
    this.isLocked = false,
    this.isChatMode = false,
    this.readingMode = 0,
    this.chapterIndex = 0,
    this.fontSize = 18,
    this.lineHeight = 1.65,
    this.manualChapterTitles = const [],
    this.readerTheme = 0,
    this.bookmarkedChapterIndexes = const [],
    this.chatBackgroundImage = '',
    this.chatBackgroundOpacity = 1,
    this.chatBackgroundBlur = 0,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String textPath;
  final String summary;
  final List<NovelRoleCandidate> roles;
  final int selectedRoleIndex;
  final int userRoleIndex;
  final bool isHidden;
  final bool isLocked;
  final bool isChatMode;
  final int readingMode;
  final int chapterIndex;
  final double fontSize;
  final double lineHeight;
  final List<String> manualChapterTitles;
  final int readerTheme;
  final List<int> bookmarkedChapterIndexes;
  final String chatBackgroundImage;
  final double chatBackgroundOpacity;
  final double chatBackgroundBlur;
  final DateTime? lastOpenedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get lastOpenedSortTime => lastOpenedAt ?? updatedAt;

  NovelRoleCandidate? get selectedRole {
    if (selectedRoleIndex < 0 || selectedRoleIndex >= roles.length) {
      return null;
    }
    return roles[selectedRoleIndex];
  }

  NovelRoleCandidate? get selectedUserRole {
    if (userRoleIndex < 0 || userRoleIndex >= roles.length) {
      return null;
    }
    return roles[userRoleIndex];
  }

  NovelBook copyWith({
    String? id,
    String? title,
    String? textPath,
    String? summary,
    List<NovelRoleCandidate>? roles,
    int? selectedRoleIndex,
    int? userRoleIndex,
    bool? isHidden,
    bool? isLocked,
    bool? isChatMode,
    int? readingMode,
    int? chapterIndex,
    double? fontSize,
    double? lineHeight,
    List<String>? manualChapterTitles,
    int? readerTheme,
    List<int>? bookmarkedChapterIndexes,
    String? chatBackgroundImage,
    double? chatBackgroundOpacity,
    double? chatBackgroundBlur,
    DateTime? lastOpenedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NovelBook(
      id: id ?? this.id,
      title: title ?? this.title,
      textPath: textPath ?? this.textPath,
      summary: summary ?? this.summary,
      roles: roles ?? this.roles,
      selectedRoleIndex: selectedRoleIndex ?? this.selectedRoleIndex,
      userRoleIndex: userRoleIndex ?? this.userRoleIndex,
      isHidden: isHidden ?? this.isHidden,
      isLocked: isLocked ?? this.isLocked,
      isChatMode: isChatMode ?? this.isChatMode,
      readingMode: readingMode ?? this.readingMode,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      manualChapterTitles: manualChapterTitles ?? this.manualChapterTitles,
      readerTheme: readerTheme ?? this.readerTheme,
      bookmarkedChapterIndexes:
          bookmarkedChapterIndexes ?? this.bookmarkedChapterIndexes,
      chatBackgroundImage: chatBackgroundImage ?? this.chatBackgroundImage,
      chatBackgroundOpacity:
          chatBackgroundOpacity ?? this.chatBackgroundOpacity,
      chatBackgroundBlur: chatBackgroundBlur ?? this.chatBackgroundBlur,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory NovelBook.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawRoles = json['roles'];
    return NovelBook(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      textPath: json['textPath'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      roles: rawRoles is List
          ? rawRoles
                .whereType<Map<String, dynamic>>()
                .map(NovelRoleCandidate.fromJson)
                .where((role) => role.name.trim().isNotEmpty)
                .toList()
          : const [],
      selectedRoleIndex: json['selectedRoleIndex'] as int? ?? -1,
      userRoleIndex: json['userRoleIndex'] as int? ?? -1,
      isHidden: json['isHidden'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      isChatMode: json['isChatMode'] as bool? ?? false,
      readingMode: json['readingMode'] as int? ?? 0,
      chapterIndex: json['chapterIndex'] as int? ?? 0,
      fontSize: _readDouble(json['fontSize'], fallback: 18),
      lineHeight: _readDouble(json['lineHeight'], fallback: 1.65),
      manualChapterTitles: _readStringList(json['manualChapterTitles']),
      readerTheme: json['readerTheme'] as int? ?? 0,
      bookmarkedChapterIndexes: _readIntList(json['bookmarkedChapterIndexes']),
      chatBackgroundImage: json['chatBackgroundImage'] as String? ?? '',
      chatBackgroundOpacity: _readDouble(
        json['chatBackgroundOpacity'],
        fallback: 1,
      ),
      chatBackgroundBlur: _readDouble(json['chatBackgroundBlur'], fallback: 0),
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'textPath': textPath,
      'summary': summary,
      'roles': roles.map((role) => role.toJson()).toList(),
      'selectedRoleIndex': selectedRoleIndex,
      'userRoleIndex': userRoleIndex,
      'isHidden': isHidden,
      'isLocked': isLocked,
      'isChatMode': isChatMode,
      'readingMode': readingMode,
      'chapterIndex': chapterIndex,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'manualChapterTitles': manualChapterTitles,
      'readerTheme': readerTheme,
      'bookmarkedChapterIndexes': bookmarkedChapterIndexes,
      'chatBackgroundImage': chatBackgroundImage,
      'chatBackgroundOpacity': chatBackgroundOpacity,
      'chatBackgroundBlur': chatBackgroundBlur,
      if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt!.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static double _readDouble(dynamic value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }

  static List<int> _readIntList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<int>().toList();
  }
}
