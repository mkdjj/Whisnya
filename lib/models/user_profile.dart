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
