abstract interface class ChatAppearance<T> {
  double get backgroundImageOpacity;
  double get backgroundBlur;
  double get topBarOpacity;
  double get inputOpacity;
  String get roleBubblePresetId;
  String get userBubblePresetId;

  T copyWith({
    double? backgroundImageOpacity,
    double? backgroundBlur,
    double? topBarOpacity,
    double? inputOpacity,
    double? roleBubbleOpacity,
    double? userBubbleOpacity,
    String? roleBubblePresetId,
    String? userBubblePresetId,
    bool clearRoleBubbleOpacity = false,
    bool clearUserBubbleOpacity = false,
  });
}
