import 'package:flutter/material.dart';

import 'image_crop_region.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.globalBackgroundImage = '',
    this.globalBackgroundRegion = ImageCropRegion.full,
    this.globalBackgroundOpacity = 1,
    this.globalBackgroundBlur = 0,
    this.interfaceTextColor,
    this.chatTextColor,
    this.fontScale = 1,
    this.navigationBarOpacity = 1,
    this.streamResponses = true,
    this.showReasoningContent = false,
    this.useCustomChatSummaryItems = false,
    this.customChatSummaryItems = defaultChatSummaryItems,
    this.useCustomTheaterSummaryItems = false,
    this.customTheaterSummaryItems = defaultTheaterSummaryItems,
    this.languageCode = 'system',
    this.privacyPasswordHash = '',
    this.privacyPasswordSalt = '',
    this.recoveryQuestion = '',
    this.recoveryAnswerHash = '',
    this.recoveryAnswerSalt = '',
  });

  final ThemeMode themeMode;
  final String globalBackgroundImage;
  final ImageCropRegion globalBackgroundRegion;
  final double globalBackgroundOpacity;
  final double globalBackgroundBlur;
  final int? interfaceTextColor;
  final int? chatTextColor;
  final double fontScale;
  final double navigationBarOpacity;
  final bool streamResponses;
  final bool showReasoningContent;
  final bool useCustomChatSummaryItems;
  final List<String> customChatSummaryItems;
  final bool useCustomTheaterSummaryItems;
  final List<String> customTheaterSummaryItems;
  final String languageCode;
  final String privacyPasswordHash;
  final String privacyPasswordSalt;
  final String recoveryQuestion;
  final String recoveryAnswerHash;
  final String recoveryAnswerSalt;

  bool get hasPrivacyPassword =>
      privacyPasswordHash.isNotEmpty && privacyPasswordSalt.isNotEmpty;

  bool get hasRecoveryAnswer =>
      recoveryQuestion.isNotEmpty &&
      recoveryAnswerHash.isNotEmpty &&
      recoveryAnswerSalt.isNotEmpty;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? globalBackgroundImage,
    ImageCropRegion? globalBackgroundRegion,
    double? globalBackgroundOpacity,
    double? globalBackgroundBlur,
    int? interfaceTextColor,
    bool clearInterfaceTextColor = false,
    int? chatTextColor,
    bool clearChatTextColor = false,
    double? fontScale,
    double? navigationBarOpacity,
    bool? streamResponses,
    bool? showReasoningContent,
    bool? useCustomChatSummaryItems,
    List<String>? customChatSummaryItems,
    bool? useCustomTheaterSummaryItems,
    List<String>? customTheaterSummaryItems,
    String? languageCode,
    String? privacyPasswordHash,
    String? privacyPasswordSalt,
    String? recoveryQuestion,
    String? recoveryAnswerHash,
    String? recoveryAnswerSalt,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      globalBackgroundImage:
          globalBackgroundImage ?? this.globalBackgroundImage,
      globalBackgroundRegion:
          globalBackgroundRegion ?? this.globalBackgroundRegion,
      globalBackgroundOpacity:
          globalBackgroundOpacity ?? this.globalBackgroundOpacity,
      globalBackgroundBlur: globalBackgroundBlur ?? this.globalBackgroundBlur,
      interfaceTextColor: clearInterfaceTextColor
          ? null
          : interfaceTextColor ?? this.interfaceTextColor,
      chatTextColor: clearChatTextColor
          ? null
          : chatTextColor ?? this.chatTextColor,
      fontScale: fontScale ?? this.fontScale,
      navigationBarOpacity: navigationBarOpacity ?? this.navigationBarOpacity,
      streamResponses: streamResponses ?? this.streamResponses,
      showReasoningContent: showReasoningContent ?? this.showReasoningContent,
      useCustomChatSummaryItems:
          useCustomChatSummaryItems ?? this.useCustomChatSummaryItems,
      customChatSummaryItems: customChatSummaryItems == null
          ? this.customChatSummaryItems
          : cleanChatSummaryItems(customChatSummaryItems),
      useCustomTheaterSummaryItems:
          useCustomTheaterSummaryItems ?? this.useCustomTheaterSummaryItems,
      customTheaterSummaryItems: customTheaterSummaryItems == null
          ? this.customTheaterSummaryItems
          : cleanTheaterSummaryItems(customTheaterSummaryItems),
      languageCode: languageCode ?? this.languageCode,
      privacyPasswordHash: privacyPasswordHash ?? this.privacyPasswordHash,
      privacyPasswordSalt: privacyPasswordSalt ?? this.privacyPasswordSalt,
      recoveryQuestion: recoveryQuestion ?? this.recoveryQuestion,
      recoveryAnswerHash: recoveryAnswerHash ?? this.recoveryAnswerHash,
      recoveryAnswerSalt: recoveryAnswerSalt ?? this.recoveryAnswerSalt,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    return AppSettings(
      themeMode: _themeModeFromString(json?['themeMode'] as String?),
      globalBackgroundImage: json?['globalBackgroundImage'] as String? ?? '',
      globalBackgroundRegion: ImageCropRegion.fromJson(
        json?['globalBackgroundRegion'],
      ),
      globalBackgroundOpacity: _readDouble(
        json?['globalBackgroundOpacity'],
        fallback: 1,
      ),
      globalBackgroundBlur: _readDouble(
        json?['globalBackgroundBlur'],
        fallback: 0,
      ),
      interfaceTextColor: json?['interfaceTextColor'] as int?,
      chatTextColor: json?['chatTextColor'] as int?,
      fontScale: _readDouble(json?['fontScale'], fallback: 1).clamp(0.85, 1.3),
      navigationBarOpacity: _readDouble(
        json?['navigationBarOpacity'],
        fallback: 1,
      ).clamp(0, 1),
      streamResponses: json?['streamResponses'] as bool? ?? true,
      showReasoningContent: json?['showReasoningContent'] as bool? ?? false,
      useCustomChatSummaryItems:
          json?['useCustomChatSummaryItems'] as bool? ?? false,
      customChatSummaryItems: cleanChatSummaryItems(
        (json?['customChatSummaryItems'] as List?)?.whereType<String>() ??
            defaultChatSummaryItems,
      ),
      useCustomTheaterSummaryItems:
          json?['useCustomTheaterSummaryItems'] as bool? ?? false,
      customTheaterSummaryItems: cleanTheaterSummaryItems(
        (json?['customTheaterSummaryItems'] as List?)?.whereType<String>() ??
            defaultTheaterSummaryItems,
      ),
      languageCode: json?['languageCode'] as String? ?? 'system',
      privacyPasswordHash: json?['privacyPasswordHash'] as String? ?? '',
      privacyPasswordSalt: json?['privacyPasswordSalt'] as String? ?? '',
      recoveryQuestion: json?['recoveryQuestion'] as String? ?? '',
      recoveryAnswerHash: json?['recoveryAnswerHash'] as String? ?? '',
      recoveryAnswerSalt: json?['recoveryAnswerSalt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode.name,
      'globalBackgroundImage': globalBackgroundImage,
      'globalBackgroundRegion': globalBackgroundRegion.toJson(),
      'globalBackgroundOpacity': globalBackgroundOpacity,
      'globalBackgroundBlur': globalBackgroundBlur,
      'interfaceTextColor': interfaceTextColor,
      'chatTextColor': chatTextColor,
      'fontScale': fontScale,
      'navigationBarOpacity': navigationBarOpacity,
      'streamResponses': streamResponses,
      'showReasoningContent': showReasoningContent,
      'useCustomChatSummaryItems': useCustomChatSummaryItems,
      'customChatSummaryItems': customChatSummaryItems,
      'useCustomTheaterSummaryItems': useCustomTheaterSummaryItems,
      'customTheaterSummaryItems': customTheaterSummaryItems,
      'languageCode': languageCode,
      'privacyPasswordHash': privacyPasswordHash,
      'privacyPasswordSalt': privacyPasswordSalt,
      'recoveryQuestion': recoveryQuestion,
      'recoveryAnswerHash': recoveryAnswerHash,
      'recoveryAnswerSalt': recoveryAnswerSalt,
    };
  }

  static ThemeMode _themeModeFromString(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static double _readDouble(dynamic value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static const maxSummaryItems = 20;

  static const defaultChatSummaryItems = [
    '角色和用户当前的关系、态度与关系变化',
    '用户的喜好和重要个人信息',
    '角色需要长期记住的设定、约定和事件',
    '当前场景、最近情绪和未完成的话题/动作',
    '角色最近稳定使用的称呼、语气、句式和动作描写格式',
    '最近聊天发生了什么',
  ];

  static const defaultChatSummaryItemsEn = [
    'The current relationship, attitude, and changes between character and user',
    'The user\'s preferences and important personal information',
    'Settings, promises, and events the character must remember long-term',
    'The current scene, recent emotions, and unfinished topics or actions',
    'The character\'s stable forms of address, voice, sentence style, and action format',
    'What happened in the recent chat',
  ];

  static const defaultTheaterSummaryItems = [
    '各个角色、用户之间现在的相互关系',
    '用户表达出来的信息/动作',
    '这些人（包括用户）在干什么',
    '每个角色最近的语气、称呼和互动方式',
    '当前正在进行的话题、最后动作和下一步应接续的内容',
  ];

  static const defaultTheaterSummaryItemsEn = [
    'Current relationships among all characters and the user',
    'Information or actions expressed by the user',
    'What everyone, including the user, is doing',
    'Each character\'s recent voice, forms of address, and interaction style',
    'The current topic, last action, and what should happen next',
  ];

  static List<String> cleanChatSummaryItems(Iterable<String> items) {
    return _cleanSummaryItems(items, defaultChatSummaryItems);
  }

  static List<String> cleanTheaterSummaryItems(Iterable<String> items) {
    return _cleanSummaryItems(items, defaultTheaterSummaryItems);
  }

  static List<String> _cleanSummaryItems(
    Iterable<String> items,
    List<String> defaults,
  ) {
    final cleaned = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(maxSummaryItems)
        .toList();
    return cleaned.isEmpty ? List<String>.of(defaults) : cleaned;
  }
}
