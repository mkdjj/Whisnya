import '../../models/character_voice_profile.dart';

class SpeechAvailability {
  const SpeechAvailability({
    required this.available,
    this.reason,
    this.maxCodeUnits = 1000,
  });
  final bool available;
  final String? reason;
  final int maxCodeUnits;
}

class AvailableVoice {
  const AvailableVoice({
    required this.name,
    required this.locale,
    this.identifier,
    this.networkRequired,
  });
  final String name, locale;
  final String? identifier;
  final bool? networkRequired;
  bool matches(CharacterVoiceProfile profile) =>
      name == profile.voiceName &&
      locale == profile.locale &&
      (profile.identifier == null ||
          profile.identifier!.isEmpty ||
          identifier == profile.identifier);
}

class SpeechRequest {
  const SpeechRequest({
    required this.playbackId,
    required this.text,
    required this.profile,
  });
  final String playbackId, text;
  final CharacterVoiceProfile profile;
}

abstract interface class SpeechBackend {
  String get platformKey;
  Future<SpeechAvailability> initialize();
  Future<List<AvailableVoice>> listVoices({String? engineId});
  Future<List<String>> listEngines();

  /// Resolves only when this utterance completes (not when native accepts it).
  Future<void> speak(SpeechRequest request);

  /// Stops native audio and settles its outstanding utterance before returning.
  Future<void> stop();
  Future<void> dispose();
}
