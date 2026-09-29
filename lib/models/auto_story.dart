import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

enum StoryStatus { draft, ready, running, paused, completed }

enum StoryPauseReason {
  userPause,
  userStop,
  background,
  leftPage,
  requestError,
  storageError,
  lengthLimit,
  requestLimit,
  tokenLimit,
  stagnation,
  interruptedRestart,
  datasetChanged,
}

enum StoryTurnSource { ai, manual }

enum RequestPurpose { plan, actorA, actorB, review, repair, replan, regenerate }

enum CommitResult { applied, alreadyCommitted, stale, missing }

String newStoryId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(1 << 32).toRadixString(36)}';
String storyTurnsHash(List<StoryTurn> turns) => sha256
    .convert(utf8.encode(turns.map((t) => t.turnId).join('\n')))
    .toString();
dynamic _clone(dynamic value) => value is Map
    ? value.map((k, v) => MapEntry(k.toString(), _clone(v)))
    : value is List
    ? value.map(_clone).toList()
    : value;
dynamic _freeze(dynamic value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((k, v) => MapEntry(k.toString(), _freeze(v))),
      )
    : value is List
    ? List<dynamic>.unmodifiable(value.map(_freeze))
    : value;
Map<String, dynamic> _map(dynamic value) {
  if (value is! Map || value.keys.any((k) => k is! String)) {
    throw const FormatException('Expected object');
  }
  return Map<String, dynamic>.from(value);
}

String _text(
  Map<String, dynamic> j,
  String key, {
  String fallback = '',
  int max = 4000,
  bool required = false,
}) {
  final v = j[key] ?? fallback;
  if (v is! String || v.runes.length > max || (required && v.trim().isEmpty)) {
    throw FormatException('Invalid $key');
  }
  return v;
}

int _int(
  Map<String, dynamic> j,
  String key, {
  int fallback = 0,
  int min = 0,
  int max = 1000000000,
}) {
  final v = j[key] ?? fallback;
  if (v is! int || v < min || v > max) throw FormatException('Invalid $key');
  return v;
}

bool _bool(Map<String, dynamic> j, String key, {bool fallback = false}) {
  final v = j[key] ?? fallback;
  if (v is! bool) throw FormatException('Invalid $key');
  return v;
}

List<dynamic> _list(Map<String, dynamic> j, String key, {int max = 10000}) {
  final v = j[key] ?? <dynamic>[];
  if (v is! List || v.length > max) throw FormatException('Invalid $key');
  return v;
}

List<String> _texts(Map<String, dynamic> j, String key, {int max = 100}) =>
    List.unmodifiable(
      _list(j, key, max: max).map((v) {
        if (v is! String || v.runes.length > 4000) {
          throw FormatException('Invalid $key');
        }
        return v;
      }),
    );
T _enum<T extends Enum>(List<T> values, dynamic value, T fallback) {
  if (value == null) return fallback;
  for (final e in values) {
    if (e.name == value) return e;
  }
  throw FormatException('Invalid enum $value');
}

DateTime _date(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || DateTime.tryParse(v) == null) {
    throw FormatException('Invalid $key');
  }
  return DateTime.parse(v);
}

String _safeId(String id) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
    throw const FormatException('Unsafe identifier');
  }
  return id;
}

bool isSafeStoryMediaPath(String path) =>
    !path.contains('\\') &&
    !path.startsWith('/') &&
    !path.contains(':') &&
    !path.split('/').any((p) => p == '..' || p == '.' || p.isEmpty) &&
    path.startsWith('media/auto_stories/');

abstract class _JsonModel {
  _JsonModel(Map<String, dynamic> json)
    : _json = _freeze(json) as Map<String, dynamic>;
  final Map<String, dynamic> _json;
  Map<String, dynamic> toJson() => _clone(_json) as Map<String, dynamic>;
}

class StoryActorSnapshot extends _JsonModel {
  StoryActorSnapshot({
    required String actorId,
    required String name,
    String? sourceId,
    String? avatarRelativePath,
    String persona = '',
    String publicProfile = '',
    String endpointId = '',
    String model = '',
    bool lockedSource = false,
  }) : this.fromJson({
         'actorId': actorId,
         'name': name,
         'sourceId': sourceId,
         'avatarRelativePath': avatarRelativePath,
         'persona': persona,
         'publicProfile': publicProfile,
         'endpointId': endpointId,
         'model': model,
         'lockedSource': lockedSource,
       });
  StoryActorSnapshot.fromJson(super.j) {
    if (actorId != 'A' && actorId != 'B') {
      throw const FormatException('Actor must be A or B');
    }
    name;
    persona;
    publicProfile;
    endpointId;
    model;
    lockedSource;
    sourceId;
    if (avatarRelativePath != null &&
        !isSafeStoryMediaPath(avatarRelativePath!)) {
      throw const FormatException('Unsafe story media');
    }
  }
  String get actorId => _text(_json, 'actorId', required: true, max: 1);
  String get name => _text(_json, 'name', required: true, max: 200);
  String? get sourceId =>
      _json['sourceId'] == null ? null : _text(_json, 'sourceId', max: 128);
  String? get avatarRelativePath => _json['avatarRelativePath'] == null
      ? null
      : _text(_json, 'avatarRelativePath', max: 500);
  String get persona => _text(_json, 'persona', max: 20000);
  String get publicProfile => _text(_json, 'publicProfile');
  String get endpointId => _text(_json, 'endpointId', max: 200);
  String get model => _text(_json, 'model', max: 200);
  bool get lockedSource => _bool(_json, 'lockedSource');
  StoryActorSnapshot copyWith({
    String? name,
    String? persona,
    String? publicProfile,
    String? endpointId,
    String? model,
    bool? lockedSource,
    String? avatarRelativePath,
  }) => StoryActorSnapshot.fromJson({
    ...toJson(),
    'name': ?name,
    'persona': ?persona,
    'publicProfile': ?publicProfile,
    'endpointId': ?endpointId,
    'model': ?model,
    'lockedSource': ?lockedSource,
    'avatarRelativePath': ?avatarRelativePath,
  });
}

class StoryConfig extends _JsonModel {
  StoryConfig({
    String title = '',
    required String opening,
    required String targetEnding,
    String style = '',
    int plannedRounds = 80,
    String replyLengthPreset = 'standard',
    int interTurnDelayMs = 1000,
    int? maxRequests,
    int? tokenLimit,
    int planVersion = 1,
  }) : this.fromJson({
         'title': title,
         'opening': opening,
         'targetEnding': targetEnding,
         'style': style,
         'plannedRounds': plannedRounds,
         'replyLengthPreset': replyLengthPreset,
         'interTurnDelayMs': interTurnDelayMs,
         'maxRequests':
             maxRequests ??
             2 * plannedRounds + 2 * ((plannedRounds + 4) ~/ 5) + 10,
         'tokenLimit': tokenLimit,
         'planVersion': planVersion,
       });
  StoryConfig.fromJson(super.j) {
    title;
    opening;
    targetEnding;
    style;
    plannedRounds;
    replyLengthPreset;
    interTurnDelayMs;
    maxRequests;
    tokenLimit;
    planVersion;
  }
  String get title => _text(_json, 'title', max: 200);
  String get opening => _text(_json, 'opening', required: true);
  String get targetEnding => _text(_json, 'targetEnding', required: true);
  String get style => _text(_json, 'style', max: 2000);
  int get plannedRounds =>
      _int(_json, 'plannedRounds', fallback: 80, min: 10, max: 300);
  String get replyLengthPreset {
    final v = _text(_json, 'replyLengthPreset', fallback: 'standard');
    if (!['short', 'standard', 'detailed'].contains(v)) {
      throw const FormatException('Invalid reply length');
    }
    return v;
  }

  int get interTurnDelayMs =>
      _int(_json, 'interTurnDelayMs', fallback: 1000, max: 10000);
  int get maxRequests =>
      _int(_json, 'maxRequests', fallback: 202, min: 1, max: 100000);
  int? get tokenLimit =>
      _json['tokenLimit'] == null ? null : _int(_json, 'tokenLimit', min: 1);
  int get planVersion => _int(_json, 'planVersion', fallback: 1, min: 1);
  StoryConfig copyWith({
    String? title,
    String? opening,
    String? targetEnding,
    String? style,
    int? plannedRounds,
    String? replyLengthPreset,
    int? interTurnDelayMs,
    int? maxRequests,
    int? tokenLimit,
    bool clearTokenLimit = false,
    int? planVersion,
  }) => StoryConfig.fromJson({
    ...toJson(),
    'title': ?title,
    'opening': ?opening,
    'targetEnding': ?targetEnding,
    'style': ?style,
    'plannedRounds': ?plannedRounds,
    'replyLengthPreset': ?replyLengthPreset,
    'interTurnDelayMs': ?interTurnDelayMs,
    'maxRequests': ?maxRequests,
    if (tokenLimit != null || clearTokenLimit) 'tokenLimit': tokenLimit,
    'planVersion': ?planVersion,
  });
}

class StoryStage extends _JsonModel {
  StoryStage({
    required String id,
    required String title,
    required String objective,
    required int minRounds,
    required int targetRounds,
    required List<String> acceptanceCriteria,
    List<String> permittedDevelopments = const [],
    List<String> prematureDevelopments = const [],
  }) : this.fromJson({
         'id': id,
         'title': title,
         'objective': objective,
         'minRounds': minRounds,
         'targetRounds': targetRounds,
         'acceptanceCriteria': acceptanceCriteria,
         'permittedDevelopments': permittedDevelopments,
         'prematureDevelopments': prematureDevelopments,
       });
  StoryStage.fromJson(super.j) {
    _safeId(id);
    title;
    objective;
    if (minRounds > targetRounds || acceptanceCriteria.isEmpty) {
      throw const FormatException('Invalid stage budget or criteria');
    }
    permittedDevelopments;
    prematureDevelopments;
  }
  String get id => _text(_json, 'id', required: true, max: 128);
  String get title => _text(_json, 'title', required: true, max: 200);
  String get objective => _text(_json, 'objective', required: true);
  int get minRounds => _int(_json, 'minRounds', min: 1, max: 300);
  int get targetRounds => _int(_json, 'targetRounds', min: 1, max: 300);
  List<String> get acceptanceCriteria =>
      _texts(_json, 'acceptanceCriteria', max: 3);
  List<String> get permittedDevelopments =>
      _texts(_json, 'permittedDevelopments', max: 20);
  List<String> get prematureDevelopments =>
      _texts(_json, 'prematureDevelopments', max: 20);
  StoryStage copyWith({
    String? title,
    String? objective,
    int? minRounds,
    int? targetRounds,
    List<String>? acceptanceCriteria,
  }) => StoryStage.fromJson({
    ...toJson(),
    'title': ?title,
    'objective': ?objective,
    'minRounds': ?minRounds,
    'targetRounds': ?targetRounds,
    'acceptanceCriteria': ?acceptanceCriteria,
  });
}

class StoryTurn extends _JsonModel {
  StoryTurn({
    required String turnId,
    required int ordinal,
    required String speakerId,
    required String content,
    String reasoningContent = '',
    StoryTurnSource source = StoryTurnSource.ai,
    String endpointId = '',
    String model = '',
    String? requestId,
    DateTime? createdAt,
    String? replacesTurnId,
  }) : this.fromJson({
         'turnId': turnId,
         'ordinal': ordinal,
         'roundNumber': ordinal ~/ 2 + 1,
         'speakerId': speakerId,
         'content': content,
         'reasoningContent': reasoningContent,
         'source': source.name,
         'endpointId': endpointId,
         'model': model,
         'requestId': requestId,
         'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
         'replacesTurnId': replacesTurnId,
       });
  StoryTurn.fromJson(super.j) {
    _safeId(turnId);
    ordinal;
    if (speakerId != (ordinal.isEven ? 'A' : 'B') ||
        roundNumber != ordinal ~/ 2 + 1) {
      throw const FormatException('Invalid turn identity');
    }
    content;
    reasoningContent;
    source;
    endpointId;
    model;
    requestId;
    createdAt;
    replacesTurnId;
  }
  String get turnId => _text(_json, 'turnId', required: true, max: 128);
  int get ordinal => _int(_json, 'ordinal', max: 599);
  int get roundNumber =>
      _int(_json, 'roundNumber', fallback: ordinal ~/ 2 + 1, min: 1, max: 300);
  String get speakerId => _text(_json, 'speakerId', required: true, max: 1);
  String get content => _text(_json, 'content', required: true);
  String get reasoningContent => _text(_json, 'reasoningContent', max: 100000);
  StoryTurnSource get source =>
      _enum(StoryTurnSource.values, _json['source'], StoryTurnSource.ai);
  String get endpointId => _text(_json, 'endpointId', max: 200);
  String get model => _text(_json, 'model', max: 200);
  String? get requestId => _json['requestId'] == null
      ? null
      : _text(_json, 'requestId', required: true, max: 128);
  DateTime get createdAt => _date(_json, 'createdAt');
  String? get replacesTurnId => _json['replacesTurnId'] == null
      ? null
      : _text(_json, 'replacesTurnId', required: true, max: 128);
  StoryTurn copyWith({
    String? turnId,
    String? content,
    String? requestId,
    String? replacesTurnId,
  }) => StoryTurn.fromJson({
    ...toJson(),
    'turnId': ?turnId,
    'content': ?content,
    'requestId': ?requestId,
    'replacesTurnId': ?replacesTurnId,
  });
}

class StoryEvidence extends _JsonModel {
  StoryEvidence({required String turnId, required String quote})
    : this.fromJson({'turnId': turnId, 'quote': quote});
  StoryEvidence.fromJson(super.j) {
    turnId;
    quote;
  }
  String get turnId => _text(_json, 'turnId', required: true, max: 128);
  String get quote => _text(_json, 'quote', required: true);
}

class StoryFact extends _JsonModel {
  StoryFact({
    required String text,
    required List<String> evidenceTurnIds,
    List<StoryEvidence> evidence = const [],
  }) : this.fromJson({
         'text': text,
         'evidenceTurnIds': evidenceTurnIds,
         'evidence': evidence.map((e) => e.toJson()).toList(),
       });
  StoryFact.fromJson(super.j) {
    text;
    evidence;
    if (evidenceTurnIds.isEmpty) {
      throw const FormatException('Fact requires evidence');
    }
  }
  String get text => _text(_json, 'text', required: true);
  List<String> get evidenceTurnIds =>
      _texts(_json, 'evidenceTurnIds', max: 600);
  List<StoryEvidence> get evidence => List.unmodifiable(
    _list(
      _json,
      'evidence',
      max: 60,
    ).map((v) => StoryEvidence.fromJson(_map(v))),
  );
}

class DirectorCheckpoint extends _JsonModel {
  DirectorCheckpoint({
    required String checkpointId,
    required int coveredThroughOrdinal,
    required String coveredTurnIdsHash,
    required int planVersion,
    String summary = '',
    List<StoryFact> confirmedFacts = const [],
    int stageIndex = 0,
    List<StoryEvidence> criterionEvidence = const [],
    String nextBeat = '',
    String pacing = 'normal',
    DateTime? createdAt,
    List<StoryEvidence> goalEvidence = const [],
    String checkKey = '',
    bool stageSatisfied = false,
    int stageStartedRound = 0,
  }) : this.fromJson({
         'checkpointId': checkpointId,
         'coveredThroughOrdinal': coveredThroughOrdinal,
         'coveredTurnIdsHash': coveredTurnIdsHash,
         'planVersion': planVersion,
         'summary': summary,
         'confirmedFacts': confirmedFacts.map((f) => f.toJson()).toList(),
         'stageIndex': stageIndex,
         'criterionEvidence': criterionEvidence.map((f) => f.toJson()).toList(),
         'nextBeat': nextBeat,
         'pacing': pacing,
         'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
         'goalEvidence': goalEvidence.map((f) => f.toJson()).toList(),
         'checkKey': checkKey,
         'stageSatisfied': stageSatisfied,
         'stageStartedRound': stageStartedRound,
       });
  DirectorCheckpoint.fromJson(super.j) {
    _safeId(checkpointId);
    coveredThroughOrdinal;
    coveredTurnIdsHash;
    planVersion;
    summary;
    confirmedFacts;
    stageIndex;
    criterionEvidence;
    nextBeat;
    pacing;
    createdAt;
    goalEvidence;
    checkKey;
    stageSatisfied;
    stageStartedRound;
  }
  String get checkpointId =>
      _text(_json, 'checkpointId', required: true, max: 128);
  int get coveredThroughOrdinal =>
      _int(_json, 'coveredThroughOrdinal', min: -1, max: 599);
  String get coveredTurnIdsHash => _text(_json, 'coveredTurnIdsHash', max: 128);
  int get planVersion => _int(_json, 'planVersion', min: 1);
  String get summary => _text(_json, 'summary');
  List<StoryFact> get confirmedFacts => List.unmodifiable(
    _list(
      _json,
      'confirmedFacts',
      max: 20,
    ).map((v) => StoryFact.fromJson(_map(v))),
  );
  int get stageIndex => _int(_json, 'stageIndex', max: 7);
  List<StoryEvidence> get criterionEvidence => List.unmodifiable(
    _list(
      _json,
      'criterionEvidence',
      max: 60,
    ).map((v) => StoryEvidence.fromJson(_map(v))),
  );
  List<StoryEvidence> get goalEvidence => List.unmodifiable(
    _list(
      _json,
      'goalEvidence',
      max: 60,
    ).map((v) => StoryEvidence.fromJson(_map(v))),
  );
  String get nextBeat => _text(_json, 'nextBeat');
  String get pacing => _text(_json, 'pacing', max: 100);
  String get checkKey => _text(_json, 'checkKey', max: 300);
  bool get stageSatisfied => _bool(_json, 'stageSatisfied');
  int get stageStartedRound => _int(_json, 'stageStartedRound', max: 300);
  DateTime get createdAt => _date(_json, 'createdAt');
}

class StoryEvent extends _JsonModel {
  StoryEvent({
    required String eventId,
    required String kind,
    required int effectiveAfterOrdinal,
    required String content,
    String? sourceCheckpointId,
    String status = 'pending',
    String scope = 'checkpoint',
    DateTime? createdAt,
  }) : this.fromJson({
         'eventId': eventId,
         'kind': kind,
         'effectiveAfterOrdinal': effectiveAfterOrdinal,
         'content': content,
         'sourceCheckpointId': sourceCheckpointId,
         'status': status,
         'scope': scope,
         'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
       });
  StoryEvent.fromJson(super.j) {
    _safeId(eventId);
    if (![
          'directorInstruction',
          'sceneTransition',
          'goalChange',
          'systemNotice',
        ].contains(kind) ||
        !['pending', 'applied', 'expired'].contains(status)) {
      throw const FormatException('Invalid event');
    }
    effectiveAfterOrdinal;
    content;
    sourceCheckpointId;
    scope;
    createdAt;
  }
  String get eventId => _text(_json, 'eventId', required: true, max: 128);
  String get kind => _text(_json, 'kind', required: true, max: 100);
  int get effectiveAfterOrdinal =>
      _int(_json, 'effectiveAfterOrdinal', min: -1, max: 599);
  String get content => _text(_json, 'content', required: true, max: 2000);
  String? get sourceCheckpointId => _json['sourceCheckpointId'] == null
      ? null
      : _text(_json, 'sourceCheckpointId', max: 128);
  String get status => _text(_json, 'status', fallback: 'pending', max: 30);
  String get scope => _text(_json, 'scope', fallback: 'checkpoint', max: 100);
  DateTime get createdAt => _date(_json, 'createdAt');
}

class StoryRequestRecord extends _JsonModel {
  StoryRequestRecord({
    required String requestId,
    required RequestPurpose purpose,
    String status = 'pending',
    DateTime? createdAt,
    int? inputTokens,
    int? outputTokens,
    int? totalTokens,
    String? errorCode,
    int runGeneration = 0,
    int expectedNextOrdinal = 0,
    String expectedSpeaker = 'A',
    int planVersion = 1,
    bool replaceLast = false,
  }) : this.fromJson({
         'requestId': requestId,
         'purpose': purpose.name,
         'status': status,
         'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
         'inputTokens': inputTokens,
         'outputTokens': outputTokens,
         'totalTokens': totalTokens,
         'errorCode': errorCode,
         'runGeneration': runGeneration,
         'expectedNextOrdinal': expectedNextOrdinal,
         'expectedSpeaker': expectedSpeaker,
         'planVersion': planVersion,
         'replaceLast': replaceLast,
       });
  StoryRequestRecord.fromJson(super.j) {
    _safeId(requestId);
    purpose;
    if (![
      'pending',
      'committed',
      'failed',
      'cancelled',
      'unknown',
    ].contains(status)) {
      throw const FormatException('Invalid request status');
    }
    createdAt;
    inputTokens;
    outputTokens;
    providerTotalTokens;
    errorCode;
    runGeneration;
    expectedNextOrdinal;
    expectedSpeaker;
    planVersion;
    replaceLast;
  }
  String get requestId => _text(_json, 'requestId', required: true, max: 128);
  RequestPurpose get purpose =>
      _enum(RequestPurpose.values, _json['purpose'], RequestPurpose.review);
  String get status => _text(_json, 'status', fallback: 'pending', max: 30);
  DateTime get createdAt => _date(_json, 'createdAt');
  int? get inputTokens =>
      _json['inputTokens'] == null ? null : _int(_json, 'inputTokens');
  int? get outputTokens =>
      _json['outputTokens'] == null ? null : _int(_json, 'outputTokens');
  int? get providerTotalTokens =>
      _json['totalTokens'] == null ? null : _int(_json, 'totalTokens');
  String? get errorCode =>
      _json['errorCode'] == null ? null : _text(_json, 'errorCode', max: 100);
  int get runGeneration => _int(_json, 'runGeneration');
  int get expectedNextOrdinal => _int(_json, 'expectedNextOrdinal', max: 600);
  String get expectedSpeaker =>
      _text(_json, 'expectedSpeaker', fallback: 'A', max: 1);
  int get planVersion => _int(_json, 'planVersion', fallback: 1, min: 1);
  bool get replaceLast => _bool(_json, 'replaceLast');
  StoryRequestRecord copyWith({
    String? status,
    int? inputTokens,
    int? outputTokens,
    int? totalTokens,
    String? errorCode,
  }) => StoryRequestRecord.fromJson({
    ...toJson(),
    'status': ?status,
    'inputTokens': ?inputTokens,
    'outputTokens': ?outputTokens,
    'totalTokens': ?totalTokens,
    'errorCode': ?errorCode,
  });
}

class StoryUsageTotals {
  StoryUsageTotals(Iterable<StoryRequestRecord> records)
    : attempts = records.length,
      inputTokens = records.fold(0, (n, r) => n + (r.inputTokens ?? 0)),
      outputTokens = records.fold(0, (n, r) => n + (r.outputTokens ?? 0)),
      totalTokens = records.fold(
        0,
        (n, r) =>
            n +
            (r.providerTotalTokens ??
                ((r.inputTokens ?? 0) + (r.outputTokens ?? 0))),
      ),
      hasUnknown = records.any(
        (r) =>
            r.providerTotalTokens == null &&
            (r.inputTokens == null || r.outputTokens == null),
      );
  final int attempts, inputTokens, outputTokens, totalTokens;
  final bool hasUnknown;
  Map<String, dynamic> toJson() => {
    'attempts': attempts,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'totalTokens': totalTokens,
    'hasUnknown': hasUnknown,
  };
}

class AutoStoryDocument extends _JsonModel {
  AutoStoryDocument({
    required String id,
    required List<StoryActorSnapshot> actors,
    required StoryConfig config,
    int revision = 0,
    int runGeneration = 0,
    StoryStatus status = StoryStatus.draft,
    StoryPauseReason? pauseReason,
    bool pauseAfterCurrent = false,
    List<StoryStage> plan = const [],
    List<StoryTurn> turns = const [],
    List<StoryEvent> events = const [],
    List<DirectorCheckpoint> directorCheckpoints = const [],
    List<StoryFact> lockedFacts = const [],
    String? currentCheckpointId,
    String goalStatus = 'pending',
    List<Map<String, dynamic>> worldBookSnapshots = const [],
    List<Map<String, dynamic>> importedMemorySnapshots = const [],
    bool privacyRequired = false,
    List<StoryRequestRecord> requestLedger = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : this.fromJson({
         'schemaVersion': 1,
         'id': id,
         'revision': revision,
         'runGeneration': runGeneration,
         'actors': actors.map((a) => a.toJson()).toList(),
         'config': config.toJson(),
         'status': status.name,
         'pauseReason': pauseReason?.name,
         'pauseAfterCurrent': pauseAfterCurrent,
         'plan': plan.map((s) => s.toJson()).toList(),
         'turns': turns.map((t) => t.toJson()).toList(),
         'events': events.map((e) => e.toJson()).toList(),
         'directorCheckpoints': directorCheckpoints
             .map((c) => c.toJson())
             .toList(),
         'lockedFacts': lockedFacts.map((f) => f.toJson()).toList(),
         'currentCheckpointId': currentCheckpointId,
         'nextActor': turns.length.isEven ? 'A' : 'B',
         'completedRounds': turns.length ~/ 2,
         'goalStatus': goalStatus,
         'worldBookSnapshots': worldBookSnapshots,
         'importedMemorySnapshots': importedMemorySnapshots,
         'privacyRequired':
             privacyRequired || actors.any((a) => a.lockedSource),
         'requestLedger': requestLedger.map((r) => r.toJson()).toList(),
         'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
         'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
       });
  AutoStoryDocument.fromJson(super.j) {
    validate();
  }
  String get id => _safeId(_text(_json, 'id', required: true, max: 128));
  int get schemaVersion => _int(_json, 'schemaVersion', min: 1, max: 1);
  int get revision => _int(_json, 'revision');
  int get runGeneration => _int(_json, 'runGeneration');
  StoryStatus get status =>
      _enum(StoryStatus.values, _json['status'], StoryStatus.draft);
  StoryPauseReason? get pauseReason => _json['pauseReason'] == null
      ? null
      : _enum(
          StoryPauseReason.values,
          _json['pauseReason'],
          StoryPauseReason.userPause,
        );
  bool get pauseAfterCurrent => _bool(_json, 'pauseAfterCurrent');
  late final List<StoryActorSnapshot> actors = List.unmodifiable(
    _list(
      _json,
      'actors',
      max: 2,
    ).map((a) => StoryActorSnapshot.fromJson(_map(a))),
  );
  late final StoryConfig config = StoryConfig.fromJson(_map(_json['config']));
  late final List<StoryStage> plan = List.unmodifiable(
    _list(_json, 'plan', max: 8).map((a) => StoryStage.fromJson(_map(a))),
  );
  late final List<StoryTurn> turns = List.unmodifiable(
    _list(_json, 'turns', max: 600).map((a) => StoryTurn.fromJson(_map(a))),
  );
  late final List<StoryEvent> events = List.unmodifiable(
    _list(_json, 'events', max: 10000).map((a) => StoryEvent.fromJson(_map(a))),
  );
  late final List<DirectorCheckpoint> directorCheckpoints = List.unmodifiable(
    _list(
      _json,
      'directorCheckpoints',
      max: 10000,
    ).map((a) => DirectorCheckpoint.fromJson(_map(a))),
  );
  late final List<StoryRequestRecord> requestLedger = List.unmodifiable(
    _list(
      _json,
      'requestLedger',
      max: 100000,
    ).map((a) => StoryRequestRecord.fromJson(_map(a))),
  );
  String? get currentCheckpointId => _json['currentCheckpointId'] == null
      ? null
      : _text(_json, 'currentCheckpointId', max: 128);
  late final DirectorCheckpoint? currentCheckpoint = directorCheckpoints
      .where((c) => c.checkpointId == currentCheckpointId)
      .firstOrNull;

  int get stageIndex =>
      currentCheckpoint?.stageIndex ?? (plan.isEmpty ? 0 : replanStageIndex);
  int get replanStageIndex =>
      _int(_json, 'replanStageIndex', max: plan.isEmpty ? 7 : plan.length - 1);
  String get nextActor => turns.length.isEven ? 'A' : 'B';
  int get completedRounds => turns.length ~/ 2;
  int get nextOrdinal => turns.length;
  int get currentRound => completedRounds + 1;
  String get replanSummary => replanSummaryOr('');
  String replanSummaryOr(String fallback) =>
      _text(_json, 'replanSummary', fallback: fallback);
  int get replanCoveredThroughOrdinal => _int(
    _json,
    'replanCoveredThroughOrdinal',
    fallback: -1,
    min: -1,
    max: turns.length - 1,
  );
  int get replanStartRound =>
      _int(_json, 'replanStartRound', max: (turns.length + 1) ~/ 2);
  List<StoryFact> get lockedFacts => List.unmodifiable(
    _list(
      _json,
      'lockedFacts',
      max: 20,
    ).map((v) => StoryFact.fromJson(_map(v))),
  );
  String get goalStatus =>
      _text(_json, 'goalStatus', fallback: 'pending', max: 30);
  bool get privacyRequired =>
      _bool(_json, 'privacyRequired') || actors.any((a) => a.lockedSource);
  List<Map<String, dynamic>> get worldBookSnapshots => List.unmodifiable(
    _list(
      _json,
      'worldBookSnapshots',
      max: 500,
    ).map((v) => Map<String, dynamic>.unmodifiable(_map(v))),
  );
  List<Map<String, dynamic>> get importedMemorySnapshots => List.unmodifiable(
    _list(
      _json,
      'importedMemorySnapshots',
      max: 500,
    ).map((v) => Map<String, dynamic>.unmodifiable(_map(v))),
  );
  late final StoryUsageTotals usageTotals = StoryUsageTotals(requestLedger);
  DateTime get createdAt => _date(_json, 'createdAt');
  DateTime get updatedAt => _date(_json, 'updatedAt');
  void validate() {
    schemaVersion;
    id;
    revision;
    runGeneration;
    status;
    pauseReason;
    pauseAfterCurrent;
    config;
    privacyRequired;
    createdAt;
    updatedAt;
    goalStatus;
    worldBookSnapshots;
    importedMemorySnapshots;
    replanSummary;
    replanCoveredThroughOrdinal;
    replanStartRound;
    replanStageIndex;
    for (final snapshot in [
      ...worldBookSnapshots,
      ...importedMemorySnapshots,
    ]) {
      if (jsonEncode(snapshot).runes.length > 100000) {
        throw const FormatException('Snapshot exceeds bounded context');
      }
    }
    if (actors.length != 2 ||
        actors[0].actorId != 'A' ||
        actors[1].actorId != 'B') {
      throw const FormatException('Exactly two ordered fixed actors required');
    }
    if (actors.any(
      (a) =>
          a.avatarRelativePath != null &&
          !a.avatarRelativePath!.startsWith('media/auto_stories/$id/'),
    )) {
      throw const FormatException('Story media must belong to this story');
    }
    if (turns.length > config.plannedRounds * 2 ||
        _text(_json, 'nextActor', fallback: nextActor) != nextActor ||
        _int(_json, 'completedRounds', fallback: completedRounds) !=
            completedRounds) {
      throw const FormatException('Inconsistent story cursor');
    }
    final ids = <String>{};
    final requestIds = <String>{};
    for (var i = 0; i < turns.length; i++) {
      final t = turns[i];
      if (t.ordinal != i ||
          !ids.add(t.turnId) ||
          (t.requestId != null && !requestIds.add(t.requestId!))) {
        throw const FormatException('Noncontinuous or duplicate turns');
      }
    }
    if (plan.isNotEmpty &&
        (plan.length < 3 ||
            plan.map((s) => s.id).toSet().length != plan.length ||
            plan.fold<int>(0, (n, s) => n + s.targetRounds) !=
                config.plannedRounds)) {
      throw const FormatException('Invalid stage allocation');
    }
    final cpIds = <String>{};
    final lockedKeys = <String>{};
    for (final fact in lockedFacts) {
      if (!lockedKeys.add(jsonEncode(fact.toJson())) ||
          fact.evidence.isEmpty ||
          !fact.evidence
              .map((e) => e.turnId)
              .toSet()
              .containsAll(fact.evidenceTurnIds)) {
        throw const FormatException(
          'Pinned facts require unique quoted evidence',
        );
      }
      for (final evidence in fact.evidence) {
        if (!ids.contains(evidence.turnId) ||
            !turns
                .firstWhere((t) => t.turnId == evidence.turnId)
                .content
                .contains(evidence.quote)) {
          throw const FormatException(
            'Pinned fact evidence is not in the story',
          );
        }
      }
    }
    for (final cp in directorCheckpoints) {
      if (!cpIds.add(cp.checkpointId) ||
          cp.coveredThroughOrdinal >= turns.length ||
          cp.planVersion > config.planVersion ||
          (cp.planVersion == config.planVersion &&
              cp.stageIndex >= (plan.isEmpty ? 1 : plan.length))) {
        throw const FormatException('Invalid checkpoint coverage');
      }
      final covered = turns.take(cp.coveredThroughOrdinal + 1).toList();
      if (cp.coveredTurnIdsHash != storyTurnsHash(covered)) {
        throw const FormatException('Checkpoint hash mismatch');
      }
      final coveredIds = covered.map((t) => t.turnId).toSet();
      for (final f in cp.confirmedFacts) {
        if (!coveredIds.containsAll(f.evidenceTurnIds)) {
          throw const FormatException('Missing fact evidence');
        }
      }
      for (final e in [
        ...cp.criterionEvidence,
        ...cp.goalEvidence,
        ...cp.confirmedFacts.expand((f) => f.evidence),
      ]) {
        if (!coveredIds.contains(e.turnId) ||
            !turns
                .firstWhere((t) => t.turnId == e.turnId)
                .content
                .contains(e.quote)) {
          throw const FormatException('Missing quoted evidence');
        }
      }
    }
    if (currentCheckpointId != null && !cpIds.contains(currentCheckpointId)) {
      throw const FormatException('Missing current checkpoint');
    }
    final eventIds = <String>{};
    for (final event in events) {
      if (!eventIds.add(event.eventId) ||
          event.effectiveAfterOrdinal >= turns.length ||
          (event.sourceCheckpointId != null &&
              !cpIds.contains(event.sourceCheckpointId))) {
        throw const FormatException('Invalid event reference');
      }
    }
    if (requestLedger.map((r) => r.requestId).toSet().length !=
        requestLedger.length) {
      throw const FormatException('Duplicate ledger request');
    }
    if (status == StoryStatus.completed &&
        (turns.length.isOdd ||
            goalStatus != 'reached' ||
            currentCheckpoint == null ||
            currentCheckpoint!.goalEvidence.isEmpty ||
            plan.isEmpty ||
            stageIndex != plan.length - 1)) {
      throw const FormatException('Unproven completion');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'usageTotals': usageTotals.toJson(),
  };
  AutoStoryDocument copyWith({
    int? revision,
    int? runGeneration,
    StoryStatus? status,
    StoryPauseReason? pauseReason,
    bool clearPauseReason = false,
    bool? pauseAfterCurrent,
    List<StoryActorSnapshot>? actors,
    StoryConfig? config,
    List<StoryStage>? plan,
    List<StoryTurn>? turns,
    List<StoryEvent>? events,
    List<DirectorCheckpoint>? directorCheckpoints,
    List<StoryFact>? lockedFacts,
    String? currentCheckpointId,
    bool clearCurrentCheckpoint = false,
    String? goalStatus,
    bool? privacyRequired,
    List<StoryRequestRecord>? requestLedger,
    DateTime? updatedAt,
  }) {
    final nextTurns = turns ?? this.turns;
    return AutoStoryDocument.fromJson({
      ...toJson(),
      'revision': ?revision,
      'runGeneration': ?runGeneration,
      if (status != null) 'status': status.name,
      if (pauseReason != null || clearPauseReason)
        'pauseReason': pauseReason?.name,
      'pauseAfterCurrent': ?pauseAfterCurrent,
      if (actors != null) 'actors': actors.map((v) => v.toJson()).toList(),
      if (config != null) 'config': config.toJson(),
      if (plan != null) 'plan': plan.map((v) => v.toJson()).toList(),
      if (turns != null) 'turns': turns.map((v) => v.toJson()).toList(),
      'nextActor': nextTurns.length.isEven ? 'A' : 'B',
      'completedRounds': nextTurns.length ~/ 2,
      if (events != null) 'events': events.map((v) => v.toJson()).toList(),
      if (directorCheckpoints != null)
        'directorCheckpoints': directorCheckpoints
            .map((v) => v.toJson())
            .toList(),
      if (lockedFacts != null)
        'lockedFacts': lockedFacts.map((v) => v.toJson()).toList(),
      if (currentCheckpointId != null || clearCurrentCheckpoint)
        'currentCheckpointId': currentCheckpointId,
      'goalStatus': ?goalStatus,
      'privacyRequired': ?privacyRequired,
      if (requestLedger != null)
        'requestLedger': requestLedger.map((v) => v.toJson()).toList(),
      if (updatedAt != null) 'updatedAt': updatedAt.toIso8601String(),
    });
  }
}

class AutoStoryHeader {
  AutoStoryHeader(AutoStoryDocument doc)
    : id = doc.id,
      title = doc.config.title,
      actors = List.unmodifiable(doc.actors),
      status = doc.status,
      pauseReason = doc.pauseReason,
      completedRounds = doc.completedRounds,
      plannedRounds = doc.config.plannedRounds,
      stageIndex = doc.stageIndex,
      privacyRequired = doc.privacyRequired,
      updatedAt = doc.updatedAt;
  final String id, title;
  final List<StoryActorSnapshot> actors;
  final StoryStatus status;
  final StoryPauseReason? pauseReason;
  final int completedRounds, plannedRounds, stageIndex;
  final bool privacyRequired;
  final DateTime updatedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': privacyRequired ? '' : title,
    'actors': actors
        .map(
          (a) => {
            'actorId': a.actorId,
            'name': privacyRequired ? '' : a.name,
            'sourceId': a.sourceId,
            'avatarRelativePath': privacyRequired ? null : a.avatarRelativePath,
            'lockedSource': a.lockedSource,
          },
        )
        .toList(),
    'status': status.name,
    'pauseReason': pauseReason?.name,
    'completedRounds': completedRounds,
    'plannedRounds': plannedRounds,
    'stageIndex': stageIndex,
    'privacyRequired': privacyRequired,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class StoryOperationToken {
  const StoryOperationToken({
    required this.storyId,
    required this.datasetEpoch,
    required this.runGeneration,
    required this.expectedNextOrdinal,
    required this.expectedSpeaker,
    required this.requestId,
    required this.planVersion,
    this.replaceLast = false,
  });
  final String storyId, expectedSpeaker, requestId;
  final int datasetEpoch, runGeneration, expectedNextOrdinal, planVersion;
  final bool replaceLast;
}

class DirectorResult {
  DirectorResult({
    List<StoryStage>? plan,
    this.checkpoint,
    List<StoryEvent> events = const [],
    this.goalReached = false,
  }) : plan = plan == null ? null : List.unmodifiable(plan),
       events = List.unmodifiable(events);
  final List<StoryStage>? plan;
  final DirectorCheckpoint? checkpoint;
  final List<StoryEvent> events;
  final bool goalReached;
}
