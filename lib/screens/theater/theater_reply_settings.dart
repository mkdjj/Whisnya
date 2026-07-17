import 'package:flutter/material.dart';

import '../../utils/app_i18n.dart';

class TheaterReplySettings extends StatelessWidget {
  const TheaterReplySettings({
    required this.mainReplyCount,
    required this.extraReplyMode,
    required this.onMainReplyCountChanged,
    required this.onExtraReplyModeChanged,
    super.key,
  });

  final int mainReplyCount;
  final int extraReplyMode;
  final ValueChanged<int> onMainReplyCountChanged;
  final ValueChanged<int> onExtraReplyModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('主要回复人数')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _choice(context, '1 人', 1, mainReplyCount, onMainReplyCountChanged),
            _choice(context, '2 人', 2, mainReplyCount, onMainReplyCountChanged),
            _choice(
              context,
              '全部角色',
              0,
              mainReplyCount,
              onMainReplyCountChanged,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(context.t('追加发言')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _choice(context, '不追加', 0, extraReplyMode, onExtraReplyModeChanged),
            _choice(
              context,
              '随机追加 0～1 个角色',
              1,
              extraReplyMode,
              onExtraReplyModeChanged,
            ),
            _choice(
              context,
              '随机追加 0～2 个角色',
              2,
              extraReplyMode,
              onExtraReplyModeChanged,
            ),
          ],
        ),
      ],
    );
  }

  Widget _choice(
    BuildContext context,
    String label,
    int value,
    int selected,
    ValueChanged<int> onChanged,
  ) {
    return ChoiceChip(
      label: Text(context.t(label)),
      selected: selected == value,
      onSelected: (_) => onChanged(value),
    );
  }
}
