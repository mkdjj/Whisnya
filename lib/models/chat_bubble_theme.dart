enum ChatBubbleStyle {
  rounded,
  square,
  capsule,
  glass,
  note,
  comic,
  pixel,
  candy,
  outline,
  textOnly;

  static ChatBubbleStyle fromJson(Object? value) => values.firstWhere(
    (style) => style.name == value,
    orElse: () => ChatBubbleStyle.rounded,
  );
}

class ChatBubbleAppearance {
  const ChatBubbleAppearance({
    this.style = ChatBubbleStyle.rounded,
    this.backgroundColor,
    this.textColor,
    double opacity = 0.92,
  }) : opacity = opacity < 0
           ? 0
           : opacity > 1
           ? 1
           : opacity;

  final ChatBubbleStyle style;
  final int? backgroundColor;
  final int? textColor;
  final double opacity;

  ChatBubbleAppearance copyWith({
    ChatBubbleStyle? style,
    int? backgroundColor,
    bool clearBackgroundColor = false,
    int? textColor,
    bool clearTextColor = false,
    double? opacity,
  }) => ChatBubbleAppearance(
    style: style ?? this.style,
    backgroundColor: clearBackgroundColor
        ? null
        : backgroundColor ?? this.backgroundColor,
    textColor: clearTextColor ? null : textColor ?? this.textColor,
    opacity: (opacity ?? this.opacity).clamp(0, 1).toDouble(),
  );

  factory ChatBubbleAppearance.fromJson(
    Object? json, {
    double defaultOpacity = 0.92,
  }) {
    if (json is! Map<String, dynamic>) {
      return ChatBubbleAppearance(
        opacity: defaultOpacity.clamp(0, 1).toDouble(),
      );
    }
    final rawOpacity = json['opacity'];
    return ChatBubbleAppearance(
      style: ChatBubbleStyle.fromJson(json['style']),
      backgroundColor: json['backgroundColor'] as int?,
      textColor: json['textColor'] as int?,
      opacity: (rawOpacity is num ? rawOpacity.toDouble() : defaultOpacity)
          .clamp(0, 1)
          .toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'style': style.name,
    'backgroundColor': backgroundColor,
    'textColor': textColor,
    'opacity': opacity,
  };
}

class ChatBubbleTheme {
  const ChatBubbleTheme({
    this.role = const ChatBubbleAppearance(),
    this.user = const ChatBubbleAppearance(),
  });

  static const characterDefault = ChatBubbleTheme();
  static const theaterDefault = ChatBubbleTheme(
    role: ChatBubbleAppearance(opacity: 0.94),
    user: ChatBubbleAppearance(opacity: 0.94),
  );

  final ChatBubbleAppearance role;
  final ChatBubbleAppearance user;

  factory ChatBubbleTheme.sameOpacity(double opacity) {
    final value = opacity.clamp(0, 1).toDouble();
    return ChatBubbleTheme(
      role: ChatBubbleAppearance(opacity: value),
      user: ChatBubbleAppearance(opacity: value),
    );
  }

  ChatBubbleTheme copyWith({
    ChatBubbleAppearance? role,
    ChatBubbleAppearance? user,
  }) => ChatBubbleTheme(role: role ?? this.role, user: user ?? this.user);

  ChatBubbleTheme resetRole([ChatBubbleAppearance? value]) =>
      copyWith(role: value ?? const ChatBubbleAppearance());

  ChatBubbleTheme resetUser([ChatBubbleAppearance? value]) =>
      copyWith(user: value ?? const ChatBubbleAppearance());

  factory ChatBubbleTheme.fromJson(
    Object? json, {
    double legacyOpacity = 0.92,
  }) {
    if (json is! Map<String, dynamic>) {
      return ChatBubbleTheme(
        role: ChatBubbleAppearance.fromJson(
          null,
          defaultOpacity: legacyOpacity,
        ),
        user: ChatBubbleAppearance.fromJson(
          null,
          defaultOpacity: legacyOpacity,
        ),
      );
    }
    return ChatBubbleTheme(
      role: ChatBubbleAppearance.fromJson(
        json['role'],
        defaultOpacity: legacyOpacity,
      ),
      user: ChatBubbleAppearance.fromJson(
        json['user'],
        defaultOpacity: legacyOpacity,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role.toJson(),
    'user': user.toJson(),
  };
}
