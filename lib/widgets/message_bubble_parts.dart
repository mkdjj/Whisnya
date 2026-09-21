import 'package:flutter/material.dart';

import '../models/chat_bubble_theme.dart';
import '../utils/app_i18n.dart';
import 'chat_bubble.dart';

List<Widget> messageBubbleActions(
  BuildContext context, {
  required VoidCallback onCopy,
  VoidCallback? onDelete,
  VoidCallback? onAddMemory,
  VoidCallback? onStoryActions,
  VoidCallback? onSpeak,
  bool isSpeaking = false,
  double scale = 1,
}) {
  Widget action(String label, IconData icon, VoidCallback? callback) =>
      IconButton(
        tooltip: context.t(label),
        visualDensity: VisualDensity.standard,
        constraints: BoxConstraints.tightFor(
          width: 40 * scale,
          height: 40 * scale,
        ),
        padding: EdgeInsets.all(8 * scale),
        onPressed: callback,
        icon: Icon(icon, size: 16 * scale),
      );
  return [
    action('复制消息', Icons.copy, onCopy),
    action('删除消息', Icons.delete_outline, onDelete),
    action('加入记忆', Icons.bookmark_add_outlined, onAddMemory),
    if (onStoryActions != null)
      action('剧情与回忆', Icons.bookmarks_outlined, onStoryActions),
    if (onSpeak != null)
      action(
        isSpeaking ? '停止朗读' : '朗读正文',
        isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
        onSpeak,
      ),
  ];
}

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
