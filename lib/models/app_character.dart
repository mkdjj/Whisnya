import 'ai_provider.dart';

class AppCharacter {
  const AppCharacter({
    required this.id,
    required this.name,
    required this.avatar,
    required this.backgroundImage,
    required this.backgroundImageOpacity,
    required this.backgroundBlur,
    required this.bubbleOpacity,
    required this.inputOpacity,
    required this.description,
    required this.personality,
    required this.background,
    required this.speakingStyle,
    required this.openingMessage,
    required this.extraPrompt,
    required this.defaultProvider,
    this.defaultEndpointId = '',
    this.useFullChatContext = true,
    this.chatSummaryMessageLimit = defaultChatSummaryMessageLimit,
    this.sourceType = '',
    this.sourceNovelId = '',
    this.sourceNovelTitle = '',
    this.sourceNovelRoleName = '',
    this.isPinned = false,
    this.isHidden = false,
    this.isLocked = false,
    required this.createdAt,
    required this.updatedAt,
    required this.lastUsedAt,
  });

  static const minChatSummaryMessageLimit = 30;
  static const maxChatSummaryMessageLimit = 150;
  static const defaultChatSummaryMessageLimit = 50;

  final String id;
  final String name;
  final String avatar;
  final String backgroundImage;
  final double backgroundImageOpacity;
  final double backgroundBlur;
  final double bubbleOpacity;
  final double inputOpacity;
  final String description;
  final String personality;
  final String background;
  final String speakingStyle;
  final String openingMessage;
  final String extraPrompt;
  final AiProvider defaultProvider;
  final String defaultEndpointId;
  final bool useFullChatContext;
  final int chatSummaryMessageLimit;
  final String sourceType;
  final String sourceNovelId;
  final String sourceNovelTitle;
  final String sourceNovelRoleName;
  final bool isPinned;
  final bool isHidden;
  final bool isLocked;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastUsedAt;

  AppCharacter copyWith({
    String? id,
    String? name,
    String? avatar,
    String? backgroundImage,
    double? backgroundImageOpacity,
    double? backgroundBlur,
    double? bubbleOpacity,
    double? inputOpacity,
    String? description,
    String? personality,
    String? background,
    String? speakingStyle,
    String? openingMessage,
    String? extraPrompt,
    AiProvider? defaultProvider,
    String? defaultEndpointId,
    bool? useFullChatContext,
    int? chatSummaryMessageLimit,
    String? sourceType,
    String? sourceNovelId,
    String? sourceNovelTitle,
    String? sourceNovelRoleName,
    bool? isPinned,
    bool? isHidden,
    bool? isLocked,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
  }) {
    return AppCharacter(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      backgroundImageOpacity:
          backgroundImageOpacity ?? this.backgroundImageOpacity,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      bubbleOpacity: bubbleOpacity ?? this.bubbleOpacity,
      inputOpacity: inputOpacity ?? this.inputOpacity,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      background: background ?? this.background,
      speakingStyle: speakingStyle ?? this.speakingStyle,
      openingMessage: openingMessage ?? this.openingMessage,
      extraPrompt: extraPrompt ?? this.extraPrompt,
      defaultProvider: defaultProvider ?? this.defaultProvider,
      defaultEndpointId: defaultEndpointId ?? this.defaultEndpointId,
      useFullChatContext: useFullChatContext ?? this.useFullChatContext,
      chatSummaryMessageLimit: _clampSummaryLimit(
        chatSummaryMessageLimit ?? this.chatSummaryMessageLimit,
      ),
      sourceType: sourceType ?? this.sourceType,
      sourceNovelId: sourceNovelId ?? this.sourceNovelId,
      sourceNovelTitle: sourceNovelTitle ?? this.sourceNovelTitle,
      sourceNovelRoleName: sourceNovelRoleName ?? this.sourceNovelRoleName,
      isPinned: isPinned ?? this.isPinned,
      isHidden: isHidden ?? this.isHidden,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  factory AppCharacter.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return AppCharacter(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      backgroundImage: json['backgroundImage'] as String? ?? '',
      backgroundImageOpacity: _readDouble(
        json['backgroundImageOpacity'],
        fallback: 1,
      ),
      backgroundBlur: _readDouble(json['backgroundBlur'], fallback: 0),
      bubbleOpacity: _readDouble(json['bubbleOpacity'], fallback: 0.92),
      inputOpacity: _readDouble(json['inputOpacity'], fallback: 0.92),
      description: json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      background: json['background'] as String? ?? '',
      speakingStyle: json['speakingStyle'] as String? ?? '',
      openingMessage: json['openingMessage'] as String? ?? '',
      extraPrompt: json['extraPrompt'] as String? ?? '',
      defaultProvider: AiProviderX.fromId(json['defaultProvider'] as String?),
      defaultEndpointId:
          json['defaultEndpointId'] as String? ??
          (json['defaultProvider'] as String? ?? 'deepseek'),
      useFullChatContext: json['useFullChatContext'] as bool? ?? true,
      chatSummaryMessageLimit: _clampSummaryLimit(
        json['chatSummaryMessageLimit'] as int? ??
            defaultChatSummaryMessageLimit,
      ),
      sourceType: json['sourceType'] as String? ?? '',
      sourceNovelId: json['sourceNovelId'] as String? ?? '',
      sourceNovelTitle: json['sourceNovelTitle'] as String? ?? '',
      sourceNovelRoleName: json['sourceNovelRoleName'] as String? ?? '',
      isPinned: json['isPinned'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      lastUsedAt:
          DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'backgroundImage': backgroundImage,
      'backgroundImageOpacity': backgroundImageOpacity,
      'backgroundBlur': backgroundBlur,
      'bubbleOpacity': bubbleOpacity,
      'inputOpacity': inputOpacity,
      'description': description,
      'personality': personality,
      'background': background,
      'speakingStyle': speakingStyle,
      'openingMessage': openingMessage,
      'extraPrompt': extraPrompt,
      'defaultProvider': defaultProvider.id,
      'defaultEndpointId': defaultEndpointId,
      'useFullChatContext': useFullChatContext,
      'chatSummaryMessageLimit': chatSummaryMessageLimit,
      'sourceType': sourceType,
      'sourceNovelId': sourceNovelId,
      'sourceNovelTitle': sourceNovelTitle,
      'sourceNovelRoleName': sourceNovelRoleName,
      'isPinned': isPinned,
      'isHidden': isHidden,
      'isLocked': isLocked,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
    };
  }

  static double _readDouble(dynamic value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static int _clampSummaryLimit(int value) {
    return value.clamp(minChatSummaryMessageLimit, maxChatSummaryMessageLimit);
  }
}
