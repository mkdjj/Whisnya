import 'package:flutter/material.dart';

import '../../utils/app_i18n.dart';

class TheaterReplySettings extends StatelessWidget {
  const TheaterReplySettings({
    required this.participantCount,
    required this.mainReplyCount,
    required this.extraReplyMode,
    required this.onMainReplyCountChanged,
    required this.onExtraReplyModeChanged,
    super.key,
  });

  final int participantCount;
  final int mainReplyCount;
  final int extraReplyMode;
  final ValueChanged<int> onMainReplyCountChanged;
  final ValueChanged<int> onExtraReplyModeChanged;

  @override
  Widget build(BuildContext context) {
    final maximum = participantCount > 1 ? participantCount - 1 : 0;
    final selectedMain = mainReplyCount > 0 && mainReplyCount <= maximum
        ? mainReplyCount
        : 0;
    final selectedExtra = extraReplyMode.clamp(0, maximum).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('主要回复人数')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var value = 1; value <= maximum; value++)
              _choice(
                context,
                context.isEnglish ? '$value roles' : '$value 人',
                value,
                selectedMain,
                onMainReplyCountChanged,
              ),
            _choice(context, '全部角色', 0, selectedMain, onMainReplyCountChanged),
          ],
        ),
        const SizedBox(height: 12),
        Text(context.t('追加发言')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _choice(context, '不追加', 0, selectedExtra, onExtraReplyModeChanged),
            for (var value = 1; value <= maximum; value++)
              _choice(
                context,
                context.isEnglish ? '0-$value roles' : '0-$value个',
                value,
                selectedExtra,
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
