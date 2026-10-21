import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';
import '../utils/page_layout.dart';
import 'chat_images.dart';

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
    this.onPickImage,
    this.imagePaths = const [],
    this.onRemoveImage,
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
  final VoidCallback? onPickImage;
  final List<String> imagePaths;
  final ValueChanged<String>? onRemoveImage;
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChatImages(paths: imagePaths, onRemove: onRemoveImage),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (onInspiration != null)
                        SizedBox(
                          width: 28,
                          height: 36,
                          child: IconButton(
                            tooltip: context.t('回复灵感'),
                            onPressed: enabled ? onInspiration : null,
                            icon: const Icon(Icons.lightbulb_outline, size: 18),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 36,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      if (onPickImage != null)
                        SizedBox(
                          width: 28,
                          height: 36,
                          child: IconButton(
                            tooltip: context.t('发送图片'),
                            onPressed: enabled && imagePaths.length < 4
                                ? onPickImage
                                : null,
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.image_outlined, size: 18),
                          ),
                        ),
                      if (onContinue != null)
                        SizedBox(
                          width: 28,
                          height: 36,
                          child: IconButton(
                            tooltip: context.t('继续一轮'),
                            onPressed: !enabled || isGenerating
                                ? null
                                : onContinue,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            padding: EdgeInsets.zero,
                          ),
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
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: focusedInputBorder,
                            disabledBorder: inputBorder,
                          ),
                        ),
                      ),
                      if (onRetry != null && !isGenerating)
                        SizedBox(
                          width: 28,
                          height: 36,
                          child: IconButton(
                            key: const ValueKey('chat-input-actions'),
                            tooltip: context.t('重新生成'),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: enabled ? onRetry : null,
                          ),
                        ),
                      if (onEditResend != null && !isGenerating)
                        SizedBox(
                          width: 28,
                          height: 36,
                          child: IconButton(
                            tooltip: context.t('编辑并重发'),
                            padding: EdgeInsets.zero,
                            onPressed: enabled ? onEditResend : null,
                            icon: const Icon(Icons.edit_note, size: 18),
                          ),
                        ),
                      const SizedBox(width: 4),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) => IconButton.filled(
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(36),
                            minimumSize: const Size.square(36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          padding: const EdgeInsets.all(8),
                          iconSize: 20,
                          tooltip: context.t(isGenerating ? '停止生成' : '发送'),
                          onPressed: isGenerating
                              ? onStop
                              : !enabled
                              ? null
                              : requireText &&
                                    value.text.trim().isEmpty &&
                                    imagePaths.isEmpty
                              ? null
                              : onSend,
                          icon: Icon(isGenerating ? Icons.stop : Icons.send),
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
