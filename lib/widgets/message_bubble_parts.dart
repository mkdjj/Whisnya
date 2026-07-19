import 'package:flutter/material.dart';

import '../models/chat_bubble_theme.dart';
import '../utils/app_i18n.dart';
import 'chat_bubble.dart';

List<Widget> messageBubbleActions(
  BuildContext context, {
  required VoidCallback onCopy,
  VoidCallback? onDelete,
}) => [
  IconButton(
    tooltip: context.t('复制消息'),
    visualDensity: VisualDensity.compact,
    onPressed: onCopy,
    icon: const Icon(Icons.copy, size: 16),
  ),
  IconButton(
    tooltip: context.t('删除消息'),
    visualDensity: VisualDensity.compact,
    onPressed: onDelete,
    icon: const Icon(Icons.delete_outline, size: 16),
  ),
];

class TypingBubble extends StatelessWidget {
  const TypingBubble({
    required this.appearance,
    this.chatTextColor,
    this.showLabel = true,
    super.key,
  });

  final ChatBubbleAppearance appearance;
  final int? chatTextColor;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return ChatBubble(
      isUser: false,
      appearance: appearance,
      fallbackTextColor: chatTextColor,
      child: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(context.t('生成中')),
              ],
            )
          : const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}
