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

class BubbleNormalizedRect {
  const BubbleNormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  static const stretchDefault = BubbleNormalizedRect(
    left: 0.35,
    top: 0.35,
    right: 0.65,
    bottom: 0.65,
  );
  static const fillDefault = BubbleNormalizedRect(
    left: 0.12,
    top: 0.12,
    right: 0.88,
    bottom: 0.88,
  );

  final double left;
  final double top;
  final double right;
  final double bottom;

  BubbleNormalizedRect get mirrored => BubbleNormalizedRect(
    left: 1 - right,
    top: top,
    right: 1 - left,
    bottom: bottom,
  );

  factory BubbleNormalizedRect.fromJson(
    Object? json,
    BubbleNormalizedRect fallback,
  ) {
    if (json is! Map<String, dynamic>) return fallback;
    final left = _unitDouble(json['left'], fallback.left);
    final top = _unitDouble(json['top'], fallback.top);
    final right = _unitDouble(json['right'], fallback.right);
    final bottom = _unitDouble(json['bottom'], fallback.bottom);
    return BubbleNormalizedRect(
      left: left < right ? left : right,
      top: top < bottom ? top : bottom,
      right: right > left ? right : left,
      bottom: bottom > top ? bottom : top,
    );
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

class BubbleContentInsets {
  const BubbleContentInsets({
    this.left = 18,
    this.top = 12,
    this.right = 18,
    this.bottom = 12,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  BubbleContentInsets get mirrored =>
      BubbleContentInsets(left: right, top: top, right: left, bottom: bottom);

  factory BubbleContentInsets.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const BubbleContentInsets();
    return BubbleContentInsets(
      left: _nonNegativeDouble(json['left'], 18),
      top: _nonNegativeDouble(json['top'], 12),
      right: _nonNegativeDouble(json['right'], 18),
      bottom: _nonNegativeDouble(json['bottom'], 12),
    );
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

class ChatBubbleImageSkin {
  const ChatBubbleImageSkin({
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    this.stretchRegion = BubbleNormalizedRect.stretchDefault,
    this.fillRegion = BubbleNormalizedRect.fillDefault,
    this.textPadding = const BubbleContentInsets(),
    this.mirrorForUser = true,
  });

  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final BubbleNormalizedRect stretchRegion;
  final BubbleNormalizedRect fillRegion;
  final BubbleContentInsets textPadding;
  final bool mirrorForUser;

  ChatBubbleImageSkin copyWith({
    String? imagePath,
    int? imageWidth,
    int? imageHeight,
    BubbleNormalizedRect? stretchRegion,
    BubbleNormalizedRect? fillRegion,
    BubbleContentInsets? textPadding,
    bool? mirrorForUser,
  }) => ChatBubbleImageSkin(
    imagePath: imagePath ?? this.imagePath,
    imageWidth: imageWidth ?? this.imageWidth,
    imageHeight: imageHeight ?? this.imageHeight,
    stretchRegion: stretchRegion ?? this.stretchRegion,
    fillRegion: fillRegion ?? this.fillRegion,
    textPadding: textPadding ?? this.textPadding,
    mirrorForUser: mirrorForUser ?? this.mirrorForUser,
  );

  factory ChatBubbleImageSkin.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const ChatBubbleImageSkin(
        imagePath: '',
        imageWidth: 0,
        imageHeight: 0,
      );
    }
    return ChatBubbleImageSkin(
      imagePath: json['imagePath'] as String? ?? '',
      imageWidth: json['imageWidth'] as int? ?? 0,
      imageHeight: json['imageHeight'] as int? ?? 0,
      stretchRegion: BubbleNormalizedRect.fromJson(
        json['stretchRegion'],
        BubbleNormalizedRect.stretchDefault,
      ),
      fillRegion: BubbleNormalizedRect.fromJson(
        json['fillRegion'],
        BubbleNormalizedRect.fillDefault,
      ),
      textPadding: BubbleContentInsets.fromJson(json['textPadding']),
      mirrorForUser: json['mirrorForUser'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'imagePath': imagePath,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'stretchRegion': stretchRegion.toJson(),
    'fillRegion': fillRegion.toJson(),
    'textPadding': textPadding.toJson(),
    'mirrorForUser': mirrorForUser,
  };
}

class ChatBubbleAppearance {
  const ChatBubbleAppearance({
    this.style = ChatBubbleStyle.rounded,
    this.backgroundColor,
    this.textColor,
    this.imageSkin,
    double opacity = 0.92,
  }) : opacity = opacity < 0
           ? 0
           : opacity > 1
           ? 1
           : opacity;

  final ChatBubbleStyle style;
  final int? backgroundColor;
  final int? textColor;
  final ChatBubbleImageSkin? imageSkin;
  final double opacity;

  bool get isImageSkin => imageSkin != null;

  ChatBubbleAppearance copyWith({
    ChatBubbleStyle? style,
    int? backgroundColor,
    bool clearBackgroundColor = false,
    int? textColor,
    bool clearTextColor = false,
    ChatBubbleImageSkin? imageSkin,
    bool clearImageSkin = false,
    double? opacity,
  }) => ChatBubbleAppearance(
    style: style ?? this.style,
    backgroundColor: clearBackgroundColor
        ? null
        : backgroundColor ?? this.backgroundColor,
    textColor: clearTextColor ? null : textColor ?? this.textColor,
    imageSkin: clearImageSkin ? null : imageSkin ?? this.imageSkin,
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
      imageSkin: json['renderMode'] == 'imageSkin'
          ? ChatBubbleImageSkin.fromJson(json['imageSkin'])
          : null,
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
    if (imageSkin != null) 'renderMode': 'imageSkin',
    if (imageSkin != null) 'imageSkin': imageSkin!.toJson(),
  };
}

double _unitDouble(Object? value, double fallback) =>
    (value is num ? value.toDouble() : fallback).clamp(0, 1).toDouble();

double _nonNegativeDouble(Object? value, double fallback) =>
    (value is num ? value.toDouble() : fallback).clamp(0, double.infinity);

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
