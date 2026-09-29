import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';
import '../utils/page_layout.dart';

class ChatInputComposer extends StatelessWidget {
  const ChatInputComposer({
    required this.controller,
    this.focusNode,
    required this.isGenerating,
    this.enabled = true,
    required this.hasBackground,
    required this.inputOpacity,
    required this.onSend,
    required this.onStop,
    this.onContinue,
    this.onRetry,
    this.onEditResend,
    this.onInspiration,
    this.requireText = false,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool isGenerating;
  final bool enabled;
  final bool hasBackground;
  final double inputOpacity;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onContinue;
  final VoidCallback? onRetry;
  final VoidCallback? onEditResend;
  final VoidCallback? onInspiration;
  final bool requireText;

  @override
  Widget build(BuildContext context) {
    final alpha = inputOpacity.clamp(0, 1).toDouble();
    final colors = Theme.of(context).colorScheme;
    final inputBorder = OutlineInputBorder(
      borderSide: BorderSide(color: colors.outline.withValues(alpha: alpha)),
    );
    final focusedInputBorder = OutlineInputBorder(
      borderSide: BorderSide(color: colors.primary.withValues(alpha: alpha)),
    );
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: responsiveMaxContentWidth(
              MediaQuery.sizeOf(context).width,
            ),
          ),
          child: Material(
            color: colors.surface.withValues(alpha: alpha),
            elevation: hasBackground ? 8 * alpha : 0,
            shadowColor: Colors.black.withValues(alpha: alpha),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (onInspiration != null)
                        IconButton(
                          tooltip: context.t('回复灵感'),
                          onPressed: enabled ? onInspiration : null,
                          icon: const Icon(Icons.lightbulb_outline, size: 20),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (onContinue != null)
                        IconButton(
                          tooltip: context.t('继续一轮'),
                          onPressed: !enabled || isGenerating
                              ? null
                              : onContinue,
                          icon: const Icon(Icons.play_arrow),
                        ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: enabled,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: context.t('输入消息'),
                            isDense: true,
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: focusedInputBorder,
                            disabledBorder: inputBorder,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) => IconButton.filled(
                          tooltip: context.t(isGenerating ? '停止生成' : '发送'),
                          onPressed: isGenerating
                              ? onStop
                              : !enabled
                              ? null
                              : requireText && value.text.trim().isEmpty
                              ? null
                              : onSend,
                          icon: Icon(isGenerating ? Icons.stop : Icons.send),
                        ),
                      ),
                    ],
                  ),
                  if (!isGenerating &&
                      (onRetry != null || onEditResend != null))
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        if (onRetry != null)
                          Tooltip(
                            message: context.t('重试上一条'),
                            child: TextButton.icon(
                              onPressed: enabled ? onRetry : null,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(context.t('重试上一条')),
                            ),
                          ),
                        if (onEditResend != null)
                          Tooltip(
                            message: context.t('编辑并重发'),
                            child: TextButton.icon(
                              onPressed: enabled ? onEditResend : null,
                              icon: const Icon(Icons.edit_note, size: 18),
                              label: Text(context.t('编辑并重发')),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
