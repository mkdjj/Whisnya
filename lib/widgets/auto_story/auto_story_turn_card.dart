import 'package:flutter/material.dart';
import '../../models/auto_story.dart';
import '../../utils/role_message_segments.dart';

class AutoStoryTurnCard extends StatelessWidget {
  const AutoStoryTurnCard({
    required this.turn,
    required this.actor,
    required this.english,
    required this.split,
    required this.showReasoning,
    required this.onCollect,
    this.onSpeak,
    this.onEdit,
    super.key,
  });
  final StoryTurn turn;
  final StoryActorSnapshot actor;
  final bool english, split, showReasoning;
  final VoidCallback onCollect;
  final VoidCallback? onSpeak, onEdit;
  @override
  Widget build(BuildContext context) {
    final b = turn.speakerId == 'B';
    final name =
        '${actor.name}${b ? (english ? ' · AI portrayal' : ' · AI代演') : ''}${turn.source == StoryTurnSource.manual ? (english ? ' · Manual takeover' : ' · 本人接管') : ''}';
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: b ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: b
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                '$name · ${english ? 'Round' : '第'} ${turn.roundNumber}${english ? '' : '轮'}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              for (final part in roleMessageSegments(
                turn.content,
                enabled: split,
              ))
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: b
                        ? colors.primaryContainer
                        : colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    part,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    style: TextStyle(
                      color: b ? colors.onPrimaryContainer : colors.onSurface,
                    ),
                  ),
                ),
              if (showReasoning && turn.reasoningContent.isNotEmpty)
                ExpansionTile(
                  key: PageStorageKey('auto-story-reasoning-${turn.turnId}'),
                  title: Text(
                    english ? 'Reasoning (not story text)' : '推理内容（不属于正文）',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        turn.reasoningContent,
                        key: PageStorageKey(
                          'auto-story-reasoning-text-${turn.turnId}',
                        ),
                        scrollPhysics: const NeverScrollableScrollPhysics(),
                      ),
                    ),
                  ],
                ),
              Wrap(
                children: [
                  IconButton(
                    tooltip: english ? 'Save to memories' : '收藏到回忆册',
                    onPressed: onCollect,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 19),
                  ),
                  if (onSpeak != null)
                    IconButton(
                      tooltip: english ? 'Read aloud' : '朗读正文',
                      onPressed: onSpeak,
                      icon: const Icon(Icons.volume_up_outlined, size: 19),
                    ),
                  if (onEdit != null)
                    TextButton(
                      onPressed: onEdit,
                      child: Text(
                        english ? 'Edit last manual turn' : '编辑最后一次接管',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
