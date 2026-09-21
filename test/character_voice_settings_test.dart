import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/character_voice_profile.dart';

void main() {
  test(
    'legacy characters have no configured voice and retain both platforms',
    () {
      final character = AppCharacter.fromJson({'id': 'c'});
      expect(character.voiceProfiles, isEmpty);
      final changed = character.copyWith(
        voiceProfiles: {
          'android': CharacterVoiceProfile.fromJson({
            'voiceName': 'local',
            'locale': 'zh-CN',
            'rate': 99,
            'volume': -1,
          }),
          'windows': const CharacterVoiceProfile(
            voiceName: 'Windows',
            locale: 'en-US',
          ),
        },
      );
      final restored = AppCharacter.fromJson(changed.toJson());
      expect(restored.voiceProfiles['android']!.rate, 1);
      expect(restored.voiceProfiles['android']!.volume, 0);
      expect(restored.voiceProfiles['windows']!.voiceName, 'Windows');
    },
  );
}
