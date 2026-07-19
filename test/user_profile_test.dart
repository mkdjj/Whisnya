import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/user_profile.dart';

void main() {
  test('defaults missing user profile fields', () {
    const profile = UserProfile();

    expect(profile.name, '用户');
    expect(profile.avatar, isEmpty);
    expect(profile.description, isEmpty);
    expect(profile.personality, isEmpty);
    expect(profile.speakingStyle, isEmpty);
    expect(profile.extraPrompt, isEmpty);
    expect(UserProfile.fromJson(const {}).toJson(), profile.toJson());
  });

  test('round trips user profile and preserves avatar path', () {
    const profile = UserProfile(
      name: '小明',
      avatar: r'E:\data\avatar.png',
      description: '旅行者',
      personality: '开朗',
      speakingStyle: '简洁',
      extraPrompt: '喜欢猫',
    );

    expect(UserProfile.fromJson(profile.toJson()).toJson(), profile.toJson());
  });
}
