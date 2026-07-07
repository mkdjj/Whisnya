import 'package:flutter/material.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.globalBackgroundImage = '',
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
    '角色和用户的关系、态度等等',
    '用户的喜好和一些提到的重要信息',
    '角色需要记住的设定或者关系变化',
    '这些聊天说了什么发生了什么',
  ];

  static const defaultChatSummaryItemsEn = [
    'The relationship and attitude between the character and user',
    'The user\'s preferences and important information they mentioned',
    'Settings or relationship changes the character needs to remember',
    'What was said and what happened in this chat',
  ];

  static const defaultTheaterSummaryItems = [
    '各个角色、用户之间现在的相互关系',
    '用户表达出来的信息/动作',
    '这些人（包括用户）在干什么',
    '有没有什么未完成/计划中的事',
  ];

  static const defaultTheaterSummaryItemsEn = [
    'Current relationships among all characters and the user',
    'Information or actions expressed by the user',
    'What everyone, including the user, is doing',
    'Unfinished or planned matters',
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
