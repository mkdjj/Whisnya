import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';
import '../utils/page_layout.dart';

class ChatInputComposer extends StatelessWidget {
  const ChatInputComposer({
    required this.controller,
    required this.isGenerating,
    required this.hasBackground,
    required this.inputOpacity,
    required this.onSend,
    required this.onStop,
    this.onContinue,
    this.onRetry,
    this.onEditResend,
    this.requireText = false,
    super.key,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final bool hasBackground;
  final double inputOpacity;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onContinue;
  final VoidCallback? onRetry;
  final VoidCallback? onEditResend;
  final bool requireText;

  @override
  Widget build(BuildContext context) {
    final alpha = inputOpacity.clamp(0, 1).toDouble();
    final colors = Theme.of(context).colorScheme;
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (onContinue != null)
                    IconButton(
                      tooltip: context.t('继续一轮'),
                      onPressed: isGenerating ? null : onContinue,
                      icon: const Icon(Icons.play_arrow),
                    ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: context.t('输入消息'),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: colors.outline.withValues(alpha: alpha),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: colors.primary.withValues(alpha: alpha),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!isGenerating && onRetry != null) ...[
                    IconButton(
                      tooltip: context.t('重试上一条'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (!isGenerating && onEditResend != null) ...[
                    IconButton(
                      tooltip: context.t('编辑并重发'),
                      onPressed: onEditResend,
                      icon: const Icon(Icons.edit_note),
                    ),
                    const SizedBox(width: 4),
                  ],
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => IconButton.filled(
                      tooltip: context.t(isGenerating ? '停止生成' : '发送'),
                      onPressed: isGenerating
                          ? onStop
                          : requireText && value.text.trim().isEmpty
                          ? null
                          : onSend,
                      icon: Icon(isGenerating ? Icons.stop : Icons.send),
                    ),
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
