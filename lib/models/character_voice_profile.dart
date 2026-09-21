class CharacterVoiceProfile {
  const CharacterVoiceProfile({
    this.enabled = true,
    this.engineId,
    this.voiceName = '',
    this.locale = '',
    this.identifier,
    this.rate = .5,
    this.pitch = 1,
    this.volume = 1,
  });
  final bool enabled;
  final String? engineId;
  final String voiceName;
  final String locale;
  final String? identifier;
  final double rate, pitch, volume;

  factory CharacterVoiceProfile.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    return CharacterVoiceProfile(
      enabled: json['enabled'] != false,
      engineId: json['engineId'] is String ? json['engineId'] as String : null,
      voiceName: json['voiceName'] is String ? json['voiceName'] as String : '',
      locale: json['locale'] is String ? json['locale'] as String : '',
      identifier: json['identifier'] is String
          ? json['identifier'] as String
          : null,
      rate: number('rate', .5, 0, 1),
      pitch: number('pitch', 1, .5, 2),
      volume: number('volume', 1, 0, 1),
    );
  }
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'engineId': engineId,
    'voiceName': voiceName,
    'locale': locale,
    'identifier': identifier,
    'rate': rate,
    'pitch': pitch,
    'volume': volume,
  };
  CharacterVoiceProfile copyWith({
    bool? enabled,
    String? engineId,
    String? voiceName,
    String? locale,
    String? identifier,
    double? rate,
    double? pitch,
    double? volume,
  }) => CharacterVoiceProfile.fromJson({
    ...toJson(),
    'enabled': ?enabled,
    'engineId': ?engineId,
    'voiceName': ?voiceName,
    'locale': ?locale,
    'identifier': ?identifier,
    'rate': ?rate,
    'pitch': ?pitch,
    'volume': ?volume,
  });
}
