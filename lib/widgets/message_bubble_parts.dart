import 'package:flutter/material.dart';

import '../models/chat_bubble_theme.dart';
import '../utils/app_i18n.dart';
import 'chat_bubble.dart';

List<Widget> messageBubbleActions(
  BuildContext context, {
  required VoidCallback onCopy,
  VoidCallback? onDelete,
  VoidCallback? onAddMemory,
  bool showMemoryAction = true,
  VoidCallback? onStoryActions,
  VoidCallback? onSpeak,
  VoidCallback? onRegenerate,
  VoidCallback? onEditResend,
  bool canRegenerate = true,
  bool isSpeaking = false,
  double scale = 1,
}) {
  Widget action(String label, IconData icon, VoidCallback? callback) =>
      IconButton(
        tooltip: context.t(label),
        style: IconButton.styleFrom(
          fixedSize: Size.square(32 * scale),
          minimumSize: Size.square(32 * scale),
          maximumSize: Size.square(32 * scale),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        visualDensity: VisualDensity.standard,
        constraints: BoxConstraints.tightFor(
          width: 32 * scale,
          height: 32 * scale,
        ),
        padding: EdgeInsets.all(6 * scale),
        onPressed: callback,
        icon: Icon(icon, size: 14 * scale),
      );
  return [
    if (onRegenerate != null)
      action('重新生成', Icons.refresh, canRegenerate ? onRegenerate : null),
    action('复制消息', Icons.copy, onCopy),
    if (onEditResend != null) action('编辑并重发', Icons.edit_note, onEditResend),
    action('删除消息', Icons.delete_outline, onDelete),
    if (showMemoryAction)
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
