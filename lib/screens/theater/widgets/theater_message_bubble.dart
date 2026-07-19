part of '../theater_screens.dart';

class _TheaterMessageBubble extends StatelessWidget {
  const _TheaterMessageBubble({
    required this.message,
    required this.participant,
    required this.appearance,
    required this.chatTextColor,
    required this.onCopy,
    this.onDelete,
    this.onMute,
    this.onSpeakAgain,
    this.onRetry,
  });

  final TheaterMessage message;
  final TheaterParticipant? participant;
  final ChatBubbleAppearance appearance;
  final int? chatTextColor;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;
  final VoidCallback? onMute;
  final VoidCallback? onSpeakAgain;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final maxWidth = isCompactWidth(MediaQuery.sizeOf(context).width)
        ? MediaQuery.sizeOf(context).width * 0.86
        : 760.0;
    return ChatBubble(
      isUser: isUser,
      appearance: appearance,
      isError: message.isError,
      fallbackTextColor: chatTextColor,
      maxWidth: maxWidth,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TheaterAvatar(
                    participant: participant,
                    name: message.speakerName,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          message.speakerName,
                          style: theme.textTheme.labelLarge,
                        ),
                        if (message.speakerType == TheaterSpeakerType.role) ...[
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: onMute,
                            icon: Icon(
                              participant?.isMuted == true
                                  ? Icons.volume_off_outlined
                                  : Icons.volume_up_outlined,
                              size: 17,
                            ),
                            label: Text(
                              context.t(
                                participant?.isMuted == true ? '已禁言' : '未禁言',
                              ),
                            ),
                          ),
                          Tooltip(
                            message: context.t('只让当前角色回复一次'),
                            child: TextButton.icon(
                              key: ValueKey('theater-reply-once-${message.id}'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: onSpeakAgain,
                              icon: const Icon(Icons.reply, size: 17),
                              label: Text(context.t('让TA回复')),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MessageContent(
                text: message.content,
                textColor: message.isError
                    ? null
                    : appearance.textColor ?? chatTextColor,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDate(message.time),
                    style: theme.textTheme.labelSmall,
                  ),
                  if (message.model.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        message.model,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                  ...messageBubbleActions(
                    context,
                    onCopy: onCopy,
                    onDelete: onDelete,
                  ),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(context.t('重试')),
                    ),
                ],
              ),
              if (message.isError &&
                  message.errorMessage.isNotEmpty &&
                  message.errorMessage.trim() != message.content.trim())
                Text(message.errorMessage, style: theme.textTheme.labelSmall),
            ],
          );
        },
      ),
    );
  }
}
