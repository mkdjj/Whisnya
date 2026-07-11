part of '../theater_screens.dart';

class _TheaterInputComposer extends StatelessWidget {
  const _TheaterInputComposer({
    required this.controller,
    required this.isGenerating,
    required this.hasBackground,
    required this.inputOpacity,
    required this.onRegenerate,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final bool hasBackground;
  final double inputOpacity;
  final VoidCallback onRegenerate;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final alpha = inputOpacity.clamp(0, 1).toDouble();
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface.withValues(alpha: alpha);
    final borderColor = colorScheme.outline.withValues(alpha: alpha);
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
            color: surfaceColor,
            elevation: hasBackground ? 8 * alpha : 0,
            shadowColor: Colors.black.withValues(alpha: alpha),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: context.t('再生成一轮'),
                    onPressed: isGenerating ? null : onRegenerate,
                    icon: const Icon(Icons.replay),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: context.t('输入消息'),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: colorScheme.primary.withValues(alpha: alpha),
                          ),
                        ),
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
                          : value.text.trim().isEmpty
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
