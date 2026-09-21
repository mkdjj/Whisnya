import 'message_anchor.dart';

const characterStateLimits = {
  'emotion': 60,
  'relationship': 120,
  'location': 100,
  'action': 160,
};

class StateEdit {
  const StateEdit({
    required this.expectedRevision,
    this.values = const {},
    this.locks = const {},
  });
  final int expectedRevision;
  final Map<String, String?> values;
  final Map<String, bool> locks;
}

class CharacterStateView {
  CharacterStateView({
    required this.sessionId,
    required this.characterId,
    required this.revision,
    required Map<String, String?> values,
    required Map<String, bool> locks,
    required Map<String, String> sources,
    required Map<String, String> modifiedAt,
    this.anchor,
    this.reason = 'branchInitial',
    this.createdAt = '',
  }) : values = Map.unmodifiable(values),
       locks = Map.unmodifiable(locks),
       sources = Map.unmodifiable(sources),
       modifiedAt = Map.unmodifiable(modifiedAt);
  factory CharacterStateView.unknown(String sessionId, String characterId) =>
      CharacterStateView(
        sessionId: sessionId,
        characterId: characterId,
        revision: 0,
        values: {for (final k in characterStateLimits.keys) k: null},
        locks: {for (final k in characterStateLimits.keys) k: false},
        sources: {for (final k in characterStateLimits.keys) k: 'unknown'},
        modifiedAt: {},
      );
  final String sessionId, characterId, reason, createdAt;
  final int revision;
  final MessageAnchor? anchor;
  final Map<String, String?> values;
  final Map<String, bool> locks;
  final Map<String, String> sources, modifiedAt;

  CharacterStateView apply(
    StateEdit edit,
    MessageAnchor? anchor,
    String reason, {
    int? revision,
  }) {
    if (edit.expectedRevision != this.revision) {
      throw StateError('stateModified');
    }
    final values = Map<String, String?>.of(this.values),
        sources = Map<String, String>.of(this.sources),
        times = Map<String, String>.of(modifiedAt);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final e in edit.values.entries) {
      final limit = characterStateLimits[e.key];
      if (limit == null || (e.value?.runes.length ?? 0) > limit) {
        throw const FormatException('invalidStateField');
      }
      if (reason == 'aiRefresh' &&
          (locks[e.key] == true ||
              e.value == null ||
              e.value!.trim().isEmpty)) {
        continue;
      }
      values[e.key] = e.value?.trim().isEmpty == true ? null : e.value?.trim();
      sources[e.key] = reason == 'aiRefresh'
          ? 'ai'
          : reason == 'reset'
          ? 'unknown'
          : 'manual';
      times[e.key] = now;
    }
    for (final k in edit.locks.keys) {
      if (!characterStateLimits.containsKey(k)) {
        throw const FormatException('invalidStateField');
      }
      times[k] = now;
    }
    return CharacterStateView(
      sessionId: sessionId,
      characterId: characterId,
      revision: revision ?? this.revision + 1,
      values: values,
      locks: {...locks, ...edit.locks},
      sources: sources,
      modifiedAt: times,
      anchor: anchor,
      reason: reason,
      createdAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'characterId': characterId,
    'stateRevision': revision,
    'values': values,
    'locks': locks,
    'fieldSources': sources,
    'modifiedAt': modifiedAt,
    'anchor': anchor?.toJson(),
    'reason': reason,
    'createdAt': createdAt,
  };
  factory CharacterStateView.fromJson(Map<String, dynamic> json) {
    final values = <String, String?>{},
        locks = <String, bool>{},
        sources = <String, String>{};
    for (final k in characterStateLimits.keys) {
      final value = (json['values'] as Map?)?[k];
      if (value != null &&
          (value is! String || value.runes.length > characterStateLimits[k]!)) {
        throw const FormatException('invalidStateField');
      }
      values[k] = value as String?;
      final lock = (json['locks'] as Map?)?[k];
      if (lock != null && lock is! bool) {
        throw const FormatException('invalidStateLock');
      }
      locks[k] = lock == true;
      final source = (json['fieldSources'] as Map?)?[k];
      sources[k] = ['unknown', 'manual', 'ai'].contains(source)
          ? source as String
          : 'unknown';
    }
    return CharacterStateView(
      sessionId: json['sessionId'] as String,
      characterId: json['characterId'] as String,
      revision: json['stateRevision'] as int,
      values: values,
      locks: locks,
      sources: sources,
      modifiedAt: Map<String, String>.from(json['modifiedAt'] as Map? ?? {}),
      anchor: json['anchor'] == null
          ? null
          : MessageAnchor.fromJson(
              Map<String, dynamic>.from(json['anchor'] as Map),
            ),
      reason: json['reason'] as String? ?? 'branchInitial',
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}
