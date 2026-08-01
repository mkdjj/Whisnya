import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';

class ChatVariantControls extends StatelessWidget {
  const ChatVariantControls({
    required this.selectedIndex,
    required this.variantCount,
    this.isGenerating = false,
    this.onPrevious,
    this.onNext,
    this.onRegenerate,
    super.key,
  });

  final int selectedIndex;
  final int variantCount;
  final bool isGenerating;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    if (variantCount <= 1 && onRegenerate == null) {
      return const SizedBox.shrink();
    }
    final index = variantCount <= 0
        ? 0
        : selectedIndex.clamp(0, variantCount - 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (variantCount > 1) ...[
          IconButton(
            tooltip: context.t('上一个候选'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: !isGenerating && index > 0 ? onPrevious : null,
          ),
          Text('${index + 1} / $variantCount'),
          IconButton(
            tooltip: context.t('下一个候选'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: !isGenerating && index < variantCount - 1
                ? onNext
                : null,
          ),
        ],
        if (onRegenerate != null)
          TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: isGenerating ? null : onRegenerate,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(context.t('重新生成')),
          ),
      ],
    );
  }
}
