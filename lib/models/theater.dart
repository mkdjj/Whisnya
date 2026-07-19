import 'app_character.dart';
import 'chat_bubble_theme.dart';
import 'image_crop_region.dart';
import 'novel_book.dart';
import 'user_profile.dart';

int _nonNegative(int value) => value < 0 ? 0 : value;

enum TheaterRoleSource {
  appCharacter('appCharacter'),
  novelRole('novelRole');

  const TheaterRoleSource(this.id);

  final String id;

  static TheaterRoleSource fromId(String? id) {
    return values.firstWhere(
      (value) => value.id == id,
      orElse: () => TheaterRoleSource.appCharacter,
    );
  }
}

enum TheaterApiMode {
  singleApi('singleApi'),
  multiApi('multiApi');

  const TheaterApiMode(this.id);

  final String id;

  static TheaterApiMode fromId(String? id) {
    return values.firstWhere(
      (value) => value.id == id,
      orElse: () => TheaterApiMode.singleApi,
    );
  }
}

enum TheaterMultiApiReplyMode {
  randomSequential('randomSequential'),
  parallel('parallel'),
  turnBased('turnBased');

  const TheaterMultiApiReplyMode(this.id);

  final String id;

  static TheaterMultiApiReplyMode fromId(String? id) {
    return values.firstWhere(
      (value) => value.id == id,
      orElse: () => TheaterMultiApiReplyMode.turnBased,
    );
  }
}

enum TheaterSpeakerType {
  user('user'),
  role('role'),
  system('system');

  const TheaterSpeakerType(this.id);

  final String id;

  static TheaterSpeakerType fromId(String? id) {
    return values.firstWhere(
      (value) => value.id == id,
      orElse: () => TheaterSpeakerType.role,
    );
  }
}

enum TheaterGenerationIntent { userReply, continueConversation }

enum TheaterReplyPhase { main, extra }

class TheaterReplyDraft {
  const TheaterReplyDraft({required this.speaker, required this.content});

  final String speaker;
  final String content;
}

class TheaterParticipant {
  const TheaterParticipant({
    required this.id,
    required this.source,
    required this.name,
    required this.avatar,
    required this.description,
    required this.personality,
    required this.background,
    required this.speakingStyle,
    this.sourceNovelId = '',
    this.sourceNovelTitle = '',
    this.sourceRoleId = '',
    this.sourceCharacterId = '',
    this.endpointId = '',
    this.enabled = true,
    this.isMuted = false,
  });

  final String id;
  final TheaterRoleSource source;
  final String sourceNovelId;
  final String sourceNovelTitle;
  final String sourceRoleId;
  final String sourceCharacterId;
  final String name;
  final String avatar;
  final String description;
  final String personality;
  final String background;
  final String speakingStyle;
  final String endpointId;
  final bool enabled;
  final bool isMuted;

  TheaterParticipant copyWith({
    String? id,
    TheaterRoleSource? source,
    String? sourceNovelId,
    String? sourceNovelTitle,
    String? sourceRoleId,
    String? sourceCharacterId,
    String? name,
    String? avatar,
    String? description,
    String? personality,
    String? background,
    String? speakingStyle,
    String? endpointId,
    bool? enabled,
    bool? isMuted,
  }) {
    return TheaterParticipant(
      id: id ?? this.id,
      source: source ?? this.source,
      sourceNovelId: sourceNovelId ?? this.sourceNovelId,
      sourceNovelTitle: sourceNovelTitle ?? this.sourceNovelTitle,
      sourceRoleId: sourceRoleId ?? this.sourceRoleId,
      sourceCharacterId: sourceCharacterId ?? this.sourceCharacterId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      background: background ?? this.background,
      speakingStyle: speakingStyle ?? this.speakingStyle,
      endpointId: endpointId ?? this.endpointId,
      enabled: enabled ?? this.enabled,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  factory TheaterParticipant.fromAppCharacter(
    AppCharacter character, {
    required String id,
    String endpointId = '',
  }) {
    return TheaterParticipant(
      id: id,
      source: TheaterRoleSource.appCharacter,
      sourceCharacterId: character.id,
      sourceNovelId: character.sourceNovelId,
      sourceNovelTitle: character.sourceNovelTitle,
      sourceRoleId: character.sourceNovelRoleName,
      name: character.name,
      avatar: character.avatar,
      description: character.description,
      personality: character.personality,
      background: character.background,
      speakingStyle: character.speakingStyle,
      endpointId: endpointId,
    );
  }

  factory TheaterParticipant.fromUserProfile(
    UserProfile profile, {
    required String id,
  }) {
    return TheaterParticipant(
      id: id,
      source: TheaterRoleSource.appCharacter,
      name: profile.name,
      avatar: profile.avatar,
      description: profile.description,
      personality: profile.personality,
      background: profile.extraPrompt,
      speakingStyle: profile.speakingStyle,
    );
  }

  factory TheaterParticipant.fromNovelRole({
    required NovelBook book,
    required NovelRoleCandidate role,
    required String id,
    String endpointId = '',
  }) {
    return TheaterParticipant(
      id: id,
      source: TheaterRoleSource.novelRole,
      sourceNovelId: book.id,
      sourceNovelTitle: book.title,
      sourceRoleId: role.name,
      sourceCharacterId: '',
      name: role.name,
      avatar: '',
      description: role.description,
      personality: role.personality,
      background: role.background,
      speakingStyle: role.speakingStyle,
      endpointId: endpointId,
    );
  }

  factory TheaterParticipant.fromJson(Map<String, dynamic> json) {
    return TheaterParticipant(
      id: json['id'] as String? ?? '',
      source: TheaterRoleSource.fromId(json['source'] as String?),
      sourceNovelId: json['sourceNovelId'] as String? ?? '',
      sourceNovelTitle: json['sourceNovelTitle'] as String? ?? '',
      sourceRoleId: json['sourceRoleId'] as String? ?? '',
      sourceCharacterId: json['sourceCharacterId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      description: json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      background: json['background'] as String? ?? '',
      speakingStyle: json['speakingStyle'] as String? ?? '',
      endpointId: json['endpointId'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      isMuted: json['isMuted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source.id,
      'sourceNovelId': sourceNovelId,
      'sourceNovelTitle': sourceNovelTitle,
      'sourceRoleId': sourceRoleId,
      'sourceCharacterId': sourceCharacterId,
      'name': name,
      'avatar': avatar,
      'description': description,
      'personality': personality,
      'background': background,
      'speakingStyle': speakingStyle,
      'endpointId': endpointId,
      'enabled': enabled,
      'isMuted': isMuted,
    };
  }
}

List<TheaterParticipant> reorderTheaterAiParticipants(
  List<TheaterParticipant> participants, {
  required String userParticipantId,
  required int oldIndex,
  required int newIndex,
}) {
  final ai = participants
      .where((participant) => participant.id != userParticipantId)
      .toList();
  if (oldIndex < 0 ||
      oldIndex >= ai.length ||
      newIndex < 0 ||
      newIndex > ai.length) {
    return [...participants];
  }
  final moved = ai.removeAt(oldIndex);
  ai.insert(newIndex, moved);
  var index = 0;
  return [
    for (final participant in participants)
      participant.id == userParticipantId ? participant : ai[index++],
  ];
}

class TheaterSession {
  const TheaterSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.avatar = '',
    this.backgroundImage = '',
    this.backgroundImageRegion = ImageCropRegion.full,
    this.backgroundImageOpacity = 1,
    this.backgroundBlur = 0,
    this.bubbleTheme = ChatBubbleTheme.theaterDefault,
    this.inputOpacity = 0.92,
    this.topBarOpacity = 0,
    this.isHidden = false,
    this.isLocked = false,
    this.boundNovelId = '',
    this.boundNovelTitle = '',
    this.apiMode = TheaterApiMode.singleApi,
    this.multiApiReplyMode = TheaterMultiApiReplyMode.turnBased,
    this.singleEndpointId = '',
    this.userParticipantId = '',
    this.keepRoundCount = 30,
    this.mainReplyCount = 0,
    this.extraReplyMode = 0,
    this.theaterSummary = '',
    this.summarizedMessageCount = 0,
    this.nextSpeakerIndex = 0,
    this.participants = const [],
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String avatar;
  final String backgroundImage;
  final ImageCropRegion backgroundImageRegion;
  final double backgroundImageOpacity;
  final double backgroundBlur;
  final ChatBubbleTheme bubbleTheme;
  final double inputOpacity;
  final double topBarOpacity;
  final bool isHidden;
  final bool isLocked;
  final String boundNovelId;
  final String boundNovelTitle;
  final TheaterApiMode apiMode;
  final TheaterMultiApiReplyMode multiApiReplyMode;
  final String singleEndpointId;
  final String userParticipantId;
  final int keepRoundCount;
  final int mainReplyCount;
  final int extraReplyMode;
  final String theaterSummary;
  final int summarizedMessageCount;
  final int nextSpeakerIndex;
  final List<TheaterParticipant> participants;
  final DateTime? lastOpenedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get lastOpenedSortTime => lastOpenedAt ?? updatedAt;

  List<TheaterParticipant> get enabledParticipants =>
      participants.where((participant) => participant.enabled).toList();

  List<TheaterParticipant> get allAiParticipants => enabledParticipants
      .where((participant) => participant.id != userParticipantId)
      .toList();

  List<TheaterParticipant> get activeAiParticipants =>
      allAiParticipants.where((participant) => !participant.isMuted).toList();

  List<TheaterParticipant> get aiParticipants => activeAiParticipants;

  TheaterParticipant? get userParticipant {
    if (userParticipantId.isEmpty) return null;
    for (final participant in participants) {
      if (participant.id == userParticipantId) return participant;
    }
    return null;
  }

  int get participantUnitCount => 1 + activeAiParticipants.length;

  int get recentMessageLimit => participantUnitCount * keepRoundCount;

  TheaterSession copyWith({
    String? id,
    String? title,
    String? avatar,
    String? backgroundImage,
    ImageCropRegion? backgroundImageRegion,
    double? backgroundImageOpacity,
    double? backgroundBlur,
    ChatBubbleTheme? bubbleTheme,
    double? inputOpacity,
    double? topBarOpacity,
    bool? isHidden,
    bool? isLocked,
    String? boundNovelId,
    String? boundNovelTitle,
    TheaterApiMode? apiMode,
    TheaterMultiApiReplyMode? multiApiReplyMode,
    String? singleEndpointId,
    String? userParticipantId,
    int? keepRoundCount,
    int? mainReplyCount,
    int? extraReplyMode,
    String? theaterSummary,
    int? summarizedMessageCount,
    int? nextSpeakerIndex,
    List<TheaterParticipant>? participants,
    DateTime? lastOpenedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TheaterSession(
      id: id ?? this.id,
      title: title ?? this.title,
      avatar: avatar ?? this.avatar,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      backgroundImageRegion:
          backgroundImageRegion ?? this.backgroundImageRegion,
      backgroundImageOpacity:
          backgroundImageOpacity ?? this.backgroundImageOpacity,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      bubbleTheme: bubbleTheme ?? this.bubbleTheme,
      inputOpacity: inputOpacity ?? this.inputOpacity,
      topBarOpacity: topBarOpacity ?? this.topBarOpacity,
      isHidden: isHidden ?? this.isHidden,
      isLocked: isLocked ?? this.isLocked,
      boundNovelId: boundNovelId ?? this.boundNovelId,
      boundNovelTitle: boundNovelTitle ?? this.boundNovelTitle,
      apiMode: apiMode ?? this.apiMode,
      multiApiReplyMode: multiApiReplyMode ?? this.multiApiReplyMode,
      singleEndpointId: singleEndpointId ?? this.singleEndpointId,
      userParticipantId: userParticipantId ?? this.userParticipantId,
      keepRoundCount: (keepRoundCount ?? this.keepRoundCount).clamp(5, 100),
      mainReplyCount: _nonNegative(mainReplyCount ?? this.mainReplyCount),
      extraReplyMode: _nonNegative(extraReplyMode ?? this.extraReplyMode),
      theaterSummary: theaterSummary ?? this.theaterSummary,
      summarizedMessageCount:
          summarizedMessageCount ?? this.summarizedMessageCount,
      nextSpeakerIndex: nextSpeakerIndex ?? this.nextSpeakerIndex,
      participants: participants ?? this.participants,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TheaterSession.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawParticipants = json['participants'];
    return TheaterSession(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      backgroundImage: json['backgroundImage'] as String? ?? '',
      backgroundImageRegion: ImageCropRegion.fromJson(
        json['backgroundImageRegion'],
      ),
      backgroundImageOpacity: jsonDouble(json['backgroundImageOpacity'], 1),
      backgroundBlur: jsonDouble(json['backgroundBlur'], 0),
      bubbleTheme: ChatBubbleTheme.fromJson(
        json['bubbleTheme'],
        legacyOpacity: jsonDouble(json['bubbleOpacity'], 0.94),
      ),
      inputOpacity: jsonDouble(json['inputOpacity'], 0.92),
      topBarOpacity: jsonDouble(json['topBarOpacity'], 0),
      isHidden: json['isHidden'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      boundNovelId: json['boundNovelId'] as String? ?? '',
      boundNovelTitle: json['boundNovelTitle'] as String? ?? '',
      apiMode: TheaterApiMode.fromId(json['apiMode'] as String?),
      multiApiReplyMode: TheaterMultiApiReplyMode.fromId(
        json['multiApiReplyMode'] as String?,
      ),
      singleEndpointId: json['singleEndpointId'] as String? ?? '',
      userParticipantId: json['userParticipantId'] as String? ?? '',
      keepRoundCount: (json['keepRoundCount'] as int? ?? 30).clamp(5, 100),
      mainReplyCount: _nonNegative(json['mainReplyCount'] as int? ?? 0),
      extraReplyMode: _nonNegative(json['extraReplyMode'] as int? ?? 0),
      theaterSummary: json['theaterSummary'] as String? ?? '',
      summarizedMessageCount: json['summarizedMessageCount'] as int? ?? 0,
      nextSpeakerIndex: json['nextSpeakerIndex'] as int? ?? 0,
      participants: rawParticipants is List
          ? rawParticipants
                .whereType<Map<String, dynamic>>()
                .map(TheaterParticipant.fromJson)
                .where((participant) => participant.id.isNotEmpty)
                .toList()
          : const [],
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'avatar': avatar,
      'backgroundImage': backgroundImage,
      'backgroundImageRegion': backgroundImageRegion.toJson(),
      'backgroundImageOpacity': backgroundImageOpacity,
      'backgroundBlur': backgroundBlur,
      'bubbleTheme': bubbleTheme.toJson(),
      'inputOpacity': inputOpacity,
      'topBarOpacity': topBarOpacity,
      'isHidden': isHidden,
      'isLocked': isLocked,
      'boundNovelId': boundNovelId,
      'boundNovelTitle': boundNovelTitle,
      'apiMode': apiMode.id,
      'multiApiReplyMode': multiApiReplyMode.id,
      'singleEndpointId': singleEndpointId,
      'userParticipantId': userParticipantId,
      'keepRoundCount': keepRoundCount,
      'mainReplyCount': mainReplyCount,
      'extraReplyMode': extraReplyMode,
      'theaterSummary': theaterSummary,
      'summarizedMessageCount': summarizedMessageCount,
      'nextSpeakerIndex': nextSpeakerIndex,
      'participants': participants
          .map((participant) => participant.toJson())
          .toList(),
      if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt!.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class TheaterMessage {
  const TheaterMessage({
    required this.id,
    required this.sessionId,
    required this.round,
    required this.speakerType,
    required this.speakerId,
    required this.speakerName,
    required this.content,
    required this.time,
    this.endpointId = '',
    this.endpointName = '',
    this.model = '',
    this.isError = false,
    this.errorMessage = '',
  });

  final String id;
  final String sessionId;
  final int round;
  final TheaterSpeakerType speakerType;
  final String speakerId;
  final String speakerName;
  final String content;
  final String endpointId;
  final String endpointName;
  final String model;
  final bool isError;
  final String errorMessage;
  final DateTime time;

  bool get isUser => speakerType == TheaterSpeakerType.user;

  TheaterMessage copyWith({
    String? content,
    bool? isError,
    String? errorMessage,
  }) {
    return TheaterMessage(
      id: id,
      sessionId: sessionId,
      round: round,
      speakerType: speakerType,
      speakerId: speakerId,
      speakerName: speakerName,
      content: content ?? this.content,
      endpointId: endpointId,
      endpointName: endpointName,
      model: model,
      isError: isError ?? this.isError,
      errorMessage: errorMessage ?? this.errorMessage,
      time: time,
    );
  }

  factory TheaterMessage.fromJson(Map<String, dynamic> json) {
    return TheaterMessage(
      id: json['id'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      round: json['round'] as int? ?? 0,
      speakerType: TheaterSpeakerType.fromId(json['speakerType'] as String?),
      speakerId: json['speakerId'] as String? ?? '',
      speakerName: json['speakerName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      endpointId: json['endpointId'] as String? ?? '',
      endpointName: json['endpointName'] as String? ?? '',
      model: json['model'] as String? ?? '',
      isError: json['isError'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'round': round,
      'speakerType': speakerType.id,
      'speakerId': speakerId,
      'speakerName': speakerName,
      'content': content,
      'endpointId': endpointId,
      'endpointName': endpointName,
      'model': model,
      'isError': isError,
      'errorMessage': errorMessage,
      'time': time.toIso8601String(),
    };
  }
}
