class UserProfile {
  const UserProfile({
    this.name = '用户',
    this.avatar = '',
    this.description = '',
    this.personality = '',
    this.speakingStyle = '',
    this.extraPrompt = '',
  });

  final String name;
  final String avatar;
  final String description;
  final String personality;
  final String speakingStyle;
  final String extraPrompt;

  UserProfile copyWith({
    String? name,
    String? avatar,
    String? description,
    String? personality,
    String? speakingStyle,
    String? extraPrompt,
  }) {
    return UserProfile(
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      speakingStyle: speakingStyle ?? this.speakingStyle,
      extraPrompt: extraPrompt ?? this.extraPrompt,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic>? json) {
    return UserProfile(
      name: json?['name'] as String? ?? '用户',
      avatar: json?['avatar'] as String? ?? '',
      description: json?['description'] as String? ?? '',
      personality: json?['personality'] as String? ?? '',
      speakingStyle: json?['speakingStyle'] as String? ?? '',
      extraPrompt: json?['extraPrompt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'avatar': avatar,
    'description': description,
    'personality': personality,
    'speakingStyle': speakingStyle,
    'extraPrompt': extraPrompt,
  };
}
