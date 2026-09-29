import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/character_voice_profile.dart';
import 'package:whisnya/screens/character_voice_settings_screen.dart';
import 'package:whisnya/services/speech/role_speech_controller.dart';
import 'package:whisnya/services/speech/speech_backend.dart';

void main() {
  testWidgets('long Android engine names fit narrow large-text layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = RoleSpeechController(backend: _LongEngineBackend());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: CharacterVoiceSettingsScreen(
          controller: controller,
          profiles: const {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final engine = find.byType(DropdownButtonFormField<String>);
    await tester.scrollUntilVisible(engine, 200);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(engine), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(engine);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(_LongEngineBackend.name).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
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

class _LongEngineBackend implements SpeechBackend {
  static const name =
      'com.example.extremely.long.android.speech.engine.package';
  @override
  String get platformKey => 'android';
  @override
  Future<SpeechAvailability> initialize() async =>
      const SpeechAvailability(available: true);
  @override
  Future<List<String>> listEngines() async => [name];
  @override
  Future<List<AvailableVoice>> listVoices({String? engineId}) async => const [
    AvailableVoice(name: 'local', locale: 'zh-CN'),
  ];
  @override
  Future<void> speak(SpeechRequest request) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
