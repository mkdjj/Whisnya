import 'package:flutter/material.dart';

import '../models/chat_bubble_preset.dart';
import '../models/chat_bubble_theme.dart';
import '../utils/app_i18n.dart';
import 'chat_bubble.dart';

class ChatBubblePresetSelectionTile extends StatelessWidget {
  const ChatBubblePresetSelectionTile({
    required this.title,
    required this.presetId,
    required this.presets,
    required this.isUser,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String presetId;
  final ChatBubblePresetSettings presets;
  final bool isUser;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = presets.presetById(presetId);
    final selectedStyle = builtInBubbleStyle(presetId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text(context.t(title)),
      subtitle: Text(
        selected?.name ??
            (selectedStyle == null
                ? context.t('默认圆润')
                : context.t(chatBubbleStyleLabel(selectedStyle))),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await showChatBubblePresetPicker(
          context: context,
          presets: presets,
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
  required ChatBubblePresetSettings presets,
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
        for (final preset in presets.userPresets)
          ListTile(
            title: Text(preset.name),
            subtitle: Text(
              context.t(
                preset.appearanceFor(isUser).isImageSkin ? '图片皮肤' : '参数气泡',
              ),
            ),
            leading: SizedBox(
              width: 88,
              child: ChatBubble(
                isUser: isUser,
                appearance: preset.appearanceFor(isUser),
                margin: EdgeInsets.zero,
                child: Text(context.t('预览')),
              ),
            ),
            trailing: selectedId == preset.id ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(context).pop(preset.id),
          ),
      ],
    ),
  ),
);
