import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import '../../models/character_voice_profile.dart';
import 'speech_backend.dart';

class FlutterTtsBackend implements SpeechBackend {
  FlutterTtsBackend({FlutterTts? tts}) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;
  Future<dynamic>? _utterance;
  Future<void>? _preparation;
  bool _ready = false;
  int _generation = 0;
  @override
  String get platformKey => Platform.isAndroid
      ? 'android'
      : Platform.isWindows
      ? 'windows'
      : 'unsupported';
  @override
  Future<SpeechAvailability> initialize() async {
    if (platformKey == 'unsupported') {
      return const SpeechAvailability(
        available: false,
        reason: 'unsupported_platform',
      );
    }
    try {
      if (!_ready) {
        await _tts.awaitSpeakCompletion(true);
        if (Platform.isAndroid) await _tts.setQueueMode(0);
        _ready = true;
      }
      final voices = await listVoices();
      if (voices.isEmpty) {
        return const SpeechAvailability(available: false, reason: 'no_voices');
      }
      final limit = Platform.isAndroid
          ? await _tts.getMaxSpeechInputLength
          : 1000;
      return SpeechAvailability(
        available: true,
        maxCodeUnits: limit is int && limit > 0 ? limit.clamp(1, 1000) : 1000,
      );
    } catch (_) {
      return const SpeechAvailability(
        available: false,
        reason: 'engine_unavailable',
      );
    }
  }

  @override
  Future<List<String>> listEngines() async => Platform.isAndroid
      ? ((await _tts.getEngines) as List).map((e) => e.toString()).toList()
      : [];
  @override
  Future<List<AvailableVoice>> listVoices({String? engineId}) async {
    if (Platform.isAndroid && engineId != null && engineId.isNotEmpty) {
      final result = await _tts.setEngine(engineId);
      if (result != 1) throw StateError('engine_unavailable');
    }
    final raw = await _tts.getVoices;
    if (raw is! List) return [];
    return [
      for (final v in raw.whereType<Map<Object?, Object?>>())
        if (v['name'] is String && v['locale'] is String)
          AvailableVoice(
            name: v['name'] as String,
            locale: v['locale'] as String,
            identifier: v['identifier']?.toString(),
            networkRequired:
                v['network_required'] == true || v['network_required'] == 'true'
                ? true
                : v['network_required'] == false ||
                      v['network_required'] == 'false'
                ? false
                : null,
          ),
    ];
  }

  @override
  Future<void> speak(SpeechRequest request) async {
    final generation = ++_generation;
    final preparation = _configureVoice(request.profile);
    _preparation = preparation;
    try {
      await preparation;
    } finally {
      if (identical(_preparation, preparation)) _preparation = null;
    }
    if (generation != _generation) return;
    final pending = _tts.speak(request.text, focus: Platform.isAndroid);
    _utterance = pending;
    try {
      final result = await pending;
      if (result != 1) throw StateError('speech_failed');
    } finally {
      if (identical(_utterance, pending)) _utterance = null;
    }
  }

  Future<void> _configureVoice(CharacterVoiceProfile p) async {
    if (Platform.isAndroid && p.engineId != null && p.engineId!.isNotEmpty) {
      await _tts.setEngine(p.engineId!);
    }
    await _tts.setLanguage(p.locale);
    // Windows 4.2.5 selects by name + locale, NOT Apple identifier.
    final selected = await _tts.setVoice({
      'name': p.voiceName,
      'locale': p.locale,
    });
    if (selected != 1) throw StateError('voice_unavailable');
    await _tts.setSpeechRate(p.rate);
    await _tts.setVolume(p.volume);
    await _tts.setPitch(p.pitch);
  }

  @override
  Future<void> stop() async {
    ++_generation;
    final pending = _utterance;
    final preparation = _preparation;
    await _tts.stop().timeout(const Duration(seconds: 5));
    if (preparation != null) {
      await preparation.timeout(const Duration(seconds: 5));
    }
    // Drain the method-specific completion before permitting another speak.
    // Bare global callbacks are deliberately not used for playback ownership.
    if (pending != null) await pending.timeout(const Duration(seconds: 5));
  }

  @override
  Future<void> dispose() => stop();
}
