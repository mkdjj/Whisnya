import 'package:flutter/material.dart';

import '../models/chat_bubble_preset.dart';
import '../models/chat_bubble_theme.dart';
import '../utils/app_i18n.dart';
import 'chat_bubble.dart';

class ChatBubblePresetSelectionTile extends StatelessWidget {
  const ChatBubblePresetSelectionTile({
    required this.title,
    required this.presetId,
    required this.isUser,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String presetId;
  final bool isUser;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedStyle =
        builtInBubbleStyle(presetId) ?? ChatBubbleStyle.rounded;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text(context.t(title)),
      subtitle: Text(context.t(chatBubbleStyleLabel(selectedStyle))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await showChatBubblePresetPicker(
          context: context,
          selectedId: presetId,
          isUser: isUser,
        );
        if (result != null) onChanged(result);
      },
    );
  }
}

Future<String?> showChatBubblePresetPicker({
  required BuildContext context,
  required String selectedId,
  required bool isUser,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final style in ChatBubbleStyle.values)
          ListTile(
            title: Text(context.t(chatBubbleStyleLabel(style))),
            leading: SizedBox(
              width: 88,
              child: ChatBubble(
                isUser: isUser,
                appearance: ChatBubbleAppearance(style: style),
                margin: EdgeInsets.zero,
                child: Text(context.t('预览')),
              ),
            ),
            trailing: builtInBubbleStyle(selectedId) == style
                ? const Icon(Icons.check)
                : null,
            onTap: () =>
                Navigator.of(context).pop(builtInBubblePresetId(style)),
          ),
      ],
    ),
  ),
);
