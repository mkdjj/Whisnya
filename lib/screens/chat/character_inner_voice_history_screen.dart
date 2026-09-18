import 'package:flutter/material.dart';

import '../../models/app_character.dart';
import '../../models/chat_message.dart';
import '../../utils/app_i18n.dart';
import '../../widgets/chat/character_inner_voice_dialog.dart';

class CharacterInnerVoiceHistoryScreen extends StatelessWidget {
  const CharacterInnerVoiceHistoryScreen({
    super.key,
    required this.character,
    required this.messages,
  });

  final AppCharacter character;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final entries = messages
        .where(
          (message) =>
              message.isAssistant &&
              message.effectiveInnerVoice.trim().isNotEmpty,
        )
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('历史心声'))),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 42,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.t('还没有角色心声'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      context.t('开启“显示角色心声”后，新生成的角色回复会记录在这里'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _HistoryEntryCard(
                character: character,
                message: entries[index],
              ),
            ),
    );
  }
}

class _HistoryEntryCard extends StatefulWidget {
  const _HistoryEntryCard({required this.character, required this.message});

  final AppCharacter character;
  final ChatMessage message;

  @override
  State<_HistoryEntryCard> createState() => _HistoryEntryCardState();
}

class _HistoryEntryCardState extends State<_HistoryEntryCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final material = MaterialLocalizations.of(context);
    final time = message.effectiveTime.toLocal();
    final formattedTime =
        '${material.formatMediumDate(time)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CharacterInnerVoiceAvatar(
                    character: widget.character,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.character.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          formattedTime,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${context.t('心声')}：\n${message.effectiveInnerVoice.trim()}',
                maxLines: _expanded ? null : 4,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Text(
                '${context.t('当时说')}：\n${message.effectiveContent.trim()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
