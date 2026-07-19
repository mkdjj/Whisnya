import 'chat_bubble_theme.dart';

class ChatBubblePreset {
  ChatBubblePreset({
    required this.id,
    required this.name,
    required this.appearance,
    this.userAppearance,
    this.author = '',
    this.license = '',
    this.sourceDescription = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? _bubblePresetEpoch,
       updatedAt = updatedAt ?? _bubblePresetEpoch;

  final String id;
  final String name;
  final ChatBubbleAppearance appearance;
  final ChatBubbleAppearance? userAppearance;
  final String author;
  final String license;
  final String sourceDescription;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatBubbleAppearance appearanceFor(bool isUser) =>
      isUser ? userAppearance ?? appearance : appearance;

  bool get isLegacyMigration =>
      id.startsWith('character_legacy_bubble_') ||
      id.startsWith('theater_legacy_bubble_');

  ChatBubblePreset copyWith({
    String? id,
    String? name,
    ChatBubbleAppearance? appearance,
    ChatBubbleAppearance? userAppearance,
    bool clearUserAppearance = false,
    String? author,
    String? license,
    String? sourceDescription,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ChatBubblePreset(
    id: id ?? this.id,
    name: name ?? this.name,
    appearance: appearance ?? this.appearance,
    userAppearance: clearUserAppearance
        ? null
        : userAppearance ?? this.userAppearance,
    author: author ?? this.author,
    license: license ?? this.license,
    sourceDescription: sourceDescription ?? this.sourceDescription,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory ChatBubblePreset.fromJson(Map<String, dynamic> json) =>
      ChatBubblePreset(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        appearance: ChatBubbleAppearance.fromJson(json['appearance']),
        userAppearance: json['userAppearance'] is Map<String, dynamic>
            ? ChatBubbleAppearance.fromJson(json['userAppearance'])
            : null,
        author: json['author'] as String? ?? '',
        license: json['license'] as String? ?? '',
        sourceDescription: json['sourceDescription'] as String? ?? '',
        createdAt: _presetDate(json['createdAt']),
        updatedAt: _presetDate(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'appearance': appearance.toJson(),
    if (userAppearance != null) 'userAppearance': userAppearance!.toJson(),
    'author': author,
    'license': license,
    'sourceDescription': sourceDescription,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

final _bubblePresetEpoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime _presetDate(Object? value) => value is String
    ? DateTime.tryParse(value) ?? _bubblePresetEpoch
    : _bubblePresetEpoch;

class ChatBubblePresetSettings {
  const ChatBubblePresetSettings({this.presets = const []});

  final List<ChatBubblePreset> presets;

  ChatBubblePreset? presetById(String id) =>
      presets.where((preset) => preset.id == id).firstOrNull;

  Iterable<ChatBubblePreset> get userPresets =>
      presets.where((preset) => !preset.isLegacyMigration);

  ChatBubblePresetSettings copyWith({List<ChatBubblePreset>? presets}) =>
      ChatBubblePresetSettings(presets: presets ?? this.presets);

  factory ChatBubblePresetSettings.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const ChatBubblePresetSettings();
    }
    final rawPresets = json['presets'];
    return ChatBubblePresetSettings(
      presets: rawPresets is List
          ? rawPresets
                .whereType<Map<String, dynamic>>()
                .map(ChatBubblePreset.fromJson)
                .where((preset) => preset.id.isNotEmpty)
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'presets': presets.map((preset) => preset.toJson()).toList(),
  };
}

class ChatBubblePresetReferences {
  const ChatBubblePresetReferences({
    this.characterRole = 0,
    this.characterUser = 0,
    this.theaterRole = 0,
    this.theaterUser = 0,
  });

  final int characterRole;
  final int characterUser;
  final int theaterRole;
  final int theaterUser;
}

String builtInBubblePresetId(ChatBubbleStyle style) =>
    style == ChatBubbleStyle.rounded ? '' : 'builtin:${style.name}';

ChatBubbleStyle? builtInBubbleStyle(String id) {
  if (id.isEmpty) return ChatBubbleStyle.rounded;
  if (!id.startsWith('builtin:')) return null;
  final name = id.substring('builtin:'.length);
  return ChatBubbleStyle.values
      .where((style) => style.name == name)
      .firstOrNull;
}

String chatBubbleStyleLabel(ChatBubbleStyle style) => switch (style) {
  ChatBubbleStyle.rounded => '默认圆润',
  ChatBubbleStyle.square => '极简方角',
  ChatBubbleStyle.capsule => '胶囊气泡',
  ChatBubbleStyle.glass => '玻璃磨砂',
  ChatBubbleStyle.note => '纸张便签',
  ChatBubbleStyle.comic => '漫画对白框',
  ChatBubbleStyle.pixel => '像素复古',
  ChatBubbleStyle.candy => '软糖气泡',
  ChatBubbleStyle.outline => '描边透明',
  ChatBubbleStyle.textOnly => '无气泡纯文字',
};

ChatBubbleAppearance resolveBubbleAppearance({
  required String presetId,
  required ChatBubblePresetSettings presets,
  required bool isUser,
  ChatBubbleAppearance fallback = const ChatBubbleAppearance(),
}) {
  final selected = presets.presetById(presetId);
  if (selected != null) return selected.appearanceFor(isUser);
  final style = builtInBubbleStyle(presetId);
  return style == null
      ? fallback
      : fallback.copyWith(style: style, clearImageSkin: true);
}
