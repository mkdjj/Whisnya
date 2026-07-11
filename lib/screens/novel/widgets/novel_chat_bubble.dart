part of '../novel_screens.dart';

class _NovelBubble extends StatelessWidget {
  const _NovelBubble({required this.text, required this.isUser, this.onDelete});

  final String text;
  final bool isUser;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = isCompactWidth(screenWidth)
        ? screenWidth * 0.82
        : 760.0;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MessageContent(text: text),
              if (onDelete != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: context.t('删除消息'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
