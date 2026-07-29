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

  factory ChatBubbleTheme.fromJson(
    Object? json, {
    double defaultOpacity = 0.92,
  }) {
    if (json is! Map<String, dynamic>) {
      return ChatBubbleTheme(
        role: ChatBubbleAppearance.fromJson(
          null,
          defaultOpacity: defaultOpacity,
        ),
        user: ChatBubbleAppearance.fromJson(
          null,
          defaultOpacity: defaultOpacity,
        ),
      );
    }
    return ChatBubbleTheme(
      role: ChatBubbleAppearance.fromJson(
        json['role'],
        defaultOpacity: defaultOpacity,
      ),
      user: ChatBubbleAppearance.fromJson(
        json['user'],
        defaultOpacity: defaultOpacity,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role.toJson(),
    'user': user.toJson(),
  };
}
