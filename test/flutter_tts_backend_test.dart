import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_voice_profile.dart';
import 'package:whisnya/services/speech/flutter_tts_backend.dart';
import 'package:whisnya/services/speech/speech_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  test(
    'stop drains pending voice configuration and cancels before native speak',
    () async {
      final configure = Completer<Object?>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'setLanguage') return configure.future;
            return 1;
          });
      final backend = FlutterTtsBackend();
      final speaking = backend.speak(
        const SpeechRequest(
          playbackId: 'a',
          text: 'hello',
          profile: CharacterVoiceProfile(voiceName: 'local', locale: 'en-US'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      var stopped = false;
      final stopping = backend.stop().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, false);
      configure.complete(1);
      await speaking;
      await stopping;
      expect(calls, isNot(contains('speak')));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'adapter waits for utterance and drains stopped completion before returning',
    () async {
      final utterance = Completer<Object?>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getVoices') {
              return [
                {
                  'name': 'local',
                  'locale': 'zh-CN',
                  'identifier': 'windows-id',
                },
              ];
            }
            if (call.method == 'speak') return utterance.future;
            return 1;
          });
      final backend = FlutterTtsBackend();
      expect((await backend.initialize()).available, true);
      var finished = false;
      final speaking = backend
          .speak(
            const SpeechRequest(
              playbackId: 'a',
              text: '你好',
              profile: CharacterVoiceProfile(
                voiceName: 'local',
                locale: 'zh-CN',
                identifier: 'windows-id',
              ),
            ),
          )
          .then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      expect(calls.firstWhere((c) => c.method == 'setVoice').arguments, {
        'name': 'local',
        'locale': 'zh-CN',
      });
      var stopped = false;
      final stop = backend.stop().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, false);
      utterance.complete(1);
      await speaking;
      await stop;
      expect(stopped, true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
