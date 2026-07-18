import 'package:flutter/material.dart';

import '../models/chat_bubble_theme.dart';
import '../utils/app_i18n.dart';
import 'chat_bubble.dart';
import 'color_picker_dialog.dart';

class ChatBubbleThemeEditor extends StatefulWidget {
  const ChatBubbleThemeEditor({
    required this.theme,
    required this.defaultTheme,
    required this.onPreview,
    required this.onSave,
    this.isTheater = false,
    super.key,
  });

  final ChatBubbleTheme theme;
  final ChatBubbleTheme defaultTheme;
  final ValueChanged<ChatBubbleTheme> onPreview;
  final ValueChanged<ChatBubbleTheme> onSave;
  final bool isTheater;

  @override
  State<ChatBubbleThemeEditor> createState() => _ChatBubbleThemeEditorState();
}

class _ChatBubbleThemeEditorState extends State<ChatBubbleThemeEditor> {
  var _editingUser = false;

  ChatBubbleAppearance get _appearance =>
      _editingUser ? widget.theme.user : widget.theme.role;

  void _update(ChatBubbleAppearance appearance, {bool save = true}) {
    final next = _editingUser
        ? widget.theme.copyWith(user: appearance)
        : widget.theme.copyWith(role: appearance);
    widget.onPreview(next);
    if (save) widget.onSave(next);
  }

  Future<void> _pickColor({required bool text}) async {
    final result = await showColorPickerDialog(
      context: context,
      title: context.t(text ? '文字颜色' : '气泡颜色'),
      value: text ? _appearance.textColor : _appearance.backgroundColor,
    );
    if (result == null) return;
    _update(
      text
          ? _appearance.copyWith(
              textColor: result.color,
              clearTextColor: result.color == null,
            )
          : _appearance.copyWith(
              backgroundColor: result.color,
              clearBackgroundColor: result.color == null,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChatBubbleThemePreview(
          theme: widget.theme,
          isTheater: widget.isTheater,
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(context.t('角色气泡'))),
            ButtonSegment(value: true, label: Text(context.t('我的气泡'))),
          ],
          selected: {_editingUser},
          onSelectionChanged: (value) =>
              setState(() => _editingUser = value.first),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in ChatBubbleStyle.values)
              ChoiceChip(
                label: Text(context.t(_styleLabel(style))),
                selected: _appearance.style == style,
                onSelected: (_) => _update(_appearance.copyWith(style: style)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.palette_outlined),
          title: Text(context.t('气泡颜色')),
          subtitle: Text(_colorLabel(context, _appearance.backgroundColor)),
          onTap: () => _pickColor(text: false),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.format_color_text),
          title: Text(context.t('文字颜色')),
          subtitle: Text(_colorLabel(context, _appearance.textColor)),
          onTap: () => _pickColor(text: true),
        ),
        Row(
          children: [
            Expanded(child: Text(context.t('气泡透明度'))),
            Text('${(_appearance.opacity * 100).round()}%'),
          ],
        ),
        Slider(
          value: _appearance.opacity.clamp(0, 1).toDouble(),
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: (value) =>
              _update(_appearance.copyWith(opacity: value), save: false),
          onChangeEnd: (value) => _update(_appearance.copyWith(opacity: value)),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _update(
                _editingUser
                    ? widget.defaultTheme.user
                    : widget.defaultTheme.role,
              ),
              icon: const Icon(Icons.restore),
              label: Text(context.t('恢复当前默认')),
            ),
            TextButton.icon(
              onPressed: () {
                widget.onPreview(widget.defaultTheme);
                widget.onSave(widget.defaultTheme);
              },
              icon: const Icon(Icons.restart_alt),
              label: Text(context.t('恢复全部默认')),
            ),
          ],
        ),
      ],
    );
  }
}

class ChatBubbleThemePreview extends StatelessWidget {
  const ChatBubbleThemePreview({
    required this.theme,
    this.isTheater = false,
    super.key,
  });

  final ChatBubbleTheme theme;
  final bool isTheater;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ChatBubble(
              isUser: false,
              appearance: theme.role,
              maxWidth: 360,
              child: Text(context.t(isTheater ? '角色甲：我们继续吧。' : '很高兴见到你。')),
            ),
            if (isTheater)
              ChatBubble(
                isUser: false,
                appearance: theme.role,
                maxWidth: 360,
                child: Text(context.t('角色乙：我也准备好了。')),
              ),
            ChatBubble(
              isUser: true,
              appearance: theme.user,
              maxWidth: 360,
              child: Text(context.t('好的，开始吧。')),
            ),
          ],
        ),
      ),
    );
  }
}

String _styleLabel(ChatBubbleStyle style) => switch (style) {
  ChatBubbleStyle.rounded => '默认圆润',
  ChatBubbleStyle.square => '极简方角',
  ChatBubbleStyle.capsule => '胶囊气泡',
  ChatBubbleStyle.glass => '玻璃磨砂',
  ChatBubbleStyle.note => '纸张便签',
  ChatBubbleStyle.comic => '漫画对白框',
  ChatBubbleStyle.pixel => '像素复古',
  ChatBubbleStyle.candy => '软糖气泡',
  ChatBubbleStyle.outline => '描边透明',
  ChatBubbleStyle.textOnly => '无气泡纯文字',
};

String _colorLabel(BuildContext context, int? value) => value == null
    ? context.t('默认')
    : '#${value.toRadixString(16).substring(2).toUpperCase()}';
