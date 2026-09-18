import 'qq_integration_settings.dart';

class QqContactBinding {
  QqContactBinding({
    required String id,
    required this.mode,
    required String externalUserId,
    required String displayName,
    required String characterId,
    required String sessionId,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  }) : id = _required(id, 'id'),
       externalUserId = _required(externalUserId, 'externalUserId'),
       displayName = _required(displayName, 'displayName'),
       characterId = _required(characterId, 'characterId'),
       sessionId = _required(sessionId, 'sessionId') {
    if (mode == QqIntegrationMode.disabled) {
      throw ArgumentError.value(mode, 'mode', 'must be an active transport');
    }
  }

  final String id;
  final QqIntegrationMode mode;
  final String externalUserId;
  final String displayName;
  final String characterId;
  final String sessionId;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  QqContactBinding copyWith({
    String? id,
    QqIntegrationMode? mode,
    String? externalUserId,
    String? displayName,
    String? characterId,
    String? sessionId,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => QqContactBinding(
    id: id ?? this.id,
    mode: mode ?? this.mode,
    externalUserId: externalUserId ?? this.externalUserId,
    displayName: displayName ?? this.displayName,
    characterId: characterId ?? this.characterId,
    sessionId: sessionId ?? this.sessionId,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory QqContactBinding.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return QqContactBinding(
      id: json['id'] as String? ?? '',
      mode: qqIntegrationModeFromJson(json['mode']),
      externalUserId: json['externalUserId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mode': mode.name,
    'externalUserId': externalUserId,
    'displayName': displayName,
    'characterId': characterId,
    'sessionId': sessionId,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

String _required(String value, String name) {
  final result = value.trim();
  if (result.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return result;
}
