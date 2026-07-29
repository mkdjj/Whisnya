import 'chat_bubble_theme.dart';

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
  ChatBubbleAppearance fallback = const ChatBubbleAppearance(),
  double? opacityOverride,
}) {
  final style = builtInBubbleStyle(presetId);
  final appearance = style == null ? fallback : fallback.copyWith(style: style);
  return opacityOverride == null
      ? appearance
      : appearance.copyWith(opacity: opacityOverride);
}
