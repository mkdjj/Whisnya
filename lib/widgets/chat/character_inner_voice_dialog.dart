import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/app_character.dart';
import '../../models/chat_message.dart';
import '../../screens/chat/character_inner_voice_history_screen.dart';
import '../../utils/app_i18n.dart';

Future<void> showCharacterInnerVoiceDialog({
  required BuildContext context,
  required AppCharacter character,
  required String innerVoice,
  required ValueGetter<List<ChatMessage>> messagesProvider,
}) {
  final navigator = Navigator.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final dialogWidth = (size.width * 0.88).clamp(0, 520).toDouble();
      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: dialogWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.height * 0.78),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dialogContext.t('角色心声'),
                          style: Theme.of(dialogContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          dialogContext,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      CharacterInnerVoiceAvatar(character: character),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          character.name,
                          style: Theme.of(dialogContext).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    dialogContext.t('此刻心声'),
                    style: Theme.of(dialogContext).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: SelectableText(innerVoice.trim()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await navigator.push<void>(
                        MaterialPageRoute(
                          builder: (_) => CharacterInnerVoiceHistoryScreen(
                            character: character,
                            messages: messagesProvider(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: Text(dialogContext.t('查看历史心声')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class CharacterInnerVoiceAvatar extends StatelessWidget {
  const CharacterInnerVoiceAvatar({
    super.key,
    required this.character,
    this.radius = 20,
  });

  final AppCharacter character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = character.avatar.trim();
    if (path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return CircleAvatar(radius: radius, backgroundImage: FileImage(file));
      }
    }
    return CircleAvatar(
      radius: radius,
      child: const Icon(Icons.person_outline),
    );
  }
}
