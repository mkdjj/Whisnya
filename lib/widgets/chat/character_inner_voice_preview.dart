import 'package:flutter/material.dart';

import '../../utils/app_i18n.dart';

class CharacterInnerVoicePreview extends StatelessWidget {
  const CharacterInnerVoicePreview({
    super.key,
    this.innerVoice = '',
    this.isGenerating = false,
    this.isFailed = false,
    this.onTap,
    this.maxWidth = 560,
  });

  final String innerVoice;
  final bool isGenerating;
  final bool isFailed;
  final VoidCallback? onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final voice = innerVoice.trim();
    if (voice.isEmpty && !isGenerating && !isFailed) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final status = isGenerating
        ? context.t('心声生成中…')
        : isFailed
        ? context.t('心声生成失败')
        : '';

    return Align(
      key: const ValueKey('character-inner-voice-preview'),
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Material(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: voice.isNotEmpty ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: status.isNotEmpty
                          ? Text(
                              status,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${context.t('心声')}：$voice',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  context.t('查看完整心声'),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: colors.primary),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
