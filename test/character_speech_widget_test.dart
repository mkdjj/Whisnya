import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_voice_profile.dart';
import 'package:whisnya/screens/character_voice_settings_screen.dart';
import 'package:whisnya/services/speech/role_speech_controller.dart';
import 'role_speech_controller_test.dart' show FakeSpeechBackend;

void main() {
  testWidgets(
    'disabled route disposal stops idempotently without native work',
    (tester) async {
      final backend = FakeSpeechBackend();
      final controller = RoleSpeechController(backend: backend);
      controller.configure(enabled: false, allowNetworkVoices: false);
      await tester.pumpWidget(MaterialApp(home: _StopOnDispose(controller)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(backend.stops, 0);
      expect(tester.binding.transientCallbackCount, 0);
      controller.dispose();
    },
  );
  testWidgets('voice draft preview does not mutate saved profiles', (
    tester,
  ) async {
    final backend = FakeSpeechBackend();
    final controller = RoleSpeechController(backend: backend);
    final profiles = {
      'android': const CharacterVoiceProfile(
        voiceName: 'local',
        locale: 'zh-CN',
      ),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: CharacterVoiceSettingsScreen(
          profiles: profiles,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-preview')));
    await tester.pump();
    await tester.pump();
    expect(backend.requests.single.text, '你好，今天想和我聊些什么？');
    expect(profiles['android']!.rate, .5);
    await tester.tap(find.byKey(const ValueKey('speech-stop')));
    await tester.pump();
    backend.pending.single.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

class _StopOnDispose extends StatefulWidget {
  const _StopOnDispose(this.controller);
  final RoleSpeechController controller;
  @override
  State<_StopOnDispose> createState() => _StopOnDisposeState();
}

class _StopOnDisposeState extends State<_StopOnDispose> {
  @override
  void dispose() {
    unawaited(widget.controller.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
