import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/character_voice_profile.dart';
import 'package:whisnya/services/speech/role_speech_controller.dart';
import 'package:whisnya/services/speech/speech_backend.dart';

class FakeSpeechBackend implements SpeechBackend {
  final requests = <SpeechRequest>[];
  final pending = <Completer<void>>[];
  int stops = 0;
  bool? networkRequired = false;
  @override
  String get platformKey => 'android';
  @override
  Future<SpeechAvailability> initialize() async =>
      const SpeechAvailability(available: true);
  @override
  Future<List<AvailableVoice>> listVoices({String? engineId}) async => [
    AvailableVoice(
      name: 'local',
      locale: 'zh-CN',
      networkRequired: networkRequired,
    ),
  ];
  @override
  Future<List<String>> listEngines() async => [];
  @override
  Future<void> speak(SpeechRequest request) {
    requests.add(request);
    final done = Completer<void>();
    pending.add(done);
    return done.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('idle stop is idempotent without touching native engine', () async {
    final backend = FakeSpeechBackend();
    final controller = RoleSpeechController(backend: backend);
    await controller.stop();
    await controller.stop();
    expect(backend.stops, 0);
    expect(controller.state, SpeechState.idle);
    controller.dispose();
  });
  test('disabled idle configuration never touches system engine', () async {
    final backend = FakeSpeechBackend();
    final controller = RoleSpeechController(backend: backend);
    controller.configure(enabled: false, allowNetworkVoices: false);
    await Future<void>.delayed(Duration.zero);
    expect(backend.stops, 0);
    controller.dispose();
  });
  const profile = CharacterVoiceProfile(voiceName: 'local', locale: 'zh-CN');
  ChatMessage message(String text) => ChatMessage(
    role: 'assistant',
    content: text,
    time: DateTime.now(),
    reasoningContent: 'PRIVATE_R',
    innerVoice: 'PRIVATE_I',
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  test(
    'body only; stop A before B; late A completion does not finish B',
    () async {
      final backend = FakeSpeechBackend();
      final controller = RoleSpeechController(backend: backend);
      controller.configure(enabled: true, allowNetworkVoices: false);
      final a = controller.playMessage(
        message: message('**你好**'),
        sessionId: 's',
        messageId: 'a',
        variantId: 'v',
        datasetEpoch: 1,
        profile: profile,
      );
      await tick();
      expect(backend.requests.single.text, '你好');
      final b = controller.playMessage(
        message: message('B'),
        sessionId: 's',
        messageId: 'b',
        variantId: 'v',
        datasetEpoch: 1,
        profile: profile,
      );
      await tick();
      expect(backend.stops, greaterThanOrEqualTo(2));
      expect(backend.requests.length, 2);
      backend.pending[0].complete();
      await a;
      expect(controller.messageId, 'b');
      expect(controller.state, SpeechState.speaking);
      await controller.stop();
      backend.pending[1].complete();
      await b;
      expect(controller.state, SpeechState.idle);
      controller.dispose();
    },
  );
  test('disabled and cross-platform missing profile never speak', () async {
    final backend = FakeSpeechBackend();
    final controller = RoleSpeechController(backend: backend);
    await controller.playMessage(
      message: message('hello'),
      sessionId: 's',
      messageId: 'a',
      variantId: 'v',
      datasetEpoch: 1,
      profile: profile,
    );
    expect(backend.requests, isEmpty);
    controller.configure(enabled: true, allowNetworkVoices: false);
    await controller.playMessage(
      message: message('hello'),
      sessionId: 's',
      messageId: 'a',
      variantId: 'v',
      datasetEpoch: 1,
      profile: null,
    );
    expect(backend.requests, isEmpty);
    expect(controller.error, isNotNull);
    controller.dispose();
  });
  test('unknown network voices require explicit permission', () async {
    final backend = FakeSpeechBackend()..networkRequired = null;
    final controller = RoleSpeechController(backend: backend);
    controller.configure(enabled: true, allowNetworkVoices: false);
    await controller.playMessage(
      message: message('hello'),
      sessionId: 's',
      messageId: 'a',
      variantId: 'v',
      datasetEpoch: 1,
      profile: profile,
    );
    expect(backend.requests, isEmpty);
    expect(controller.error, 'network_unknown');
    controller.dispose();
  });
  test(
    'saved completion is consumed once and busy auto replies do not queue',
    () async {
      final backend = FakeSpeechBackend();
      final controller = RoleSpeechController(backend: backend);
      controller.configure(enabled: true, allowNetworkVoices: false);
      Future<void> auto(String id, {bool persisted = true}) =>
          controller.autoReadSavedReply(
            message: message(id),
            sessionId: 's',
            messageId: id,
            variantId: 'v',
            datasetEpoch: 1,
            profile: profile,
            persisted: persisted,
            selected: true,
            enabled: true,
          );
      await auto('unsaved', persisted: false);
      expect(backend.requests, isEmpty);
      final a = auto('a');
      await tick();
      await auto('b');
      expect(backend.requests.length, 1);
      await controller.stop();
      backend.pending.single.complete();
      await a;
      await auto('a');
      await auto('b');
      expect(backend.requests.length, 1);
      controller.dispose();
    },
  );
  test(
    'voice without identifier remains selectable after draft serialization',
    () {
      expect(
        const AvailableVoice(
          name: 'local',
          locale: 'zh-CN',
          networkRequired: false,
        ).matches(profile.copyWith(identifier: '')),
        true,
      );
    },
  );
}
