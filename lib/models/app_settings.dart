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
}
