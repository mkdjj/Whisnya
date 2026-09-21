import 'package:flutter/material.dart';
import '../../models/auto_story.dart';

class AutoStoryOutlineDialog extends StatefulWidget {
  const AutoStoryOutlineDialog({
    required this.story,
    required this.english,
    super.key,
  });
  final AutoStoryDocument story;
  final bool english;
  @override
  State<AutoStoryOutlineDialog> createState() => _AutoStoryOutlineDialogState();
}

class _AutoStoryOutlineDialogState extends State<AutoStoryOutlineDialog> {
  late final List<List<TextEditingController>> _fields = [
    for (final stage in widget.story.plan)
      [
        stage.title,
        stage.objective,
        '${stage.minRounds}',
        '${stage.targetRounds}',
        stage.acceptanceCriteria.join('\n'),
      ].map((text) => TextEditingController(text: text)).toList(),
  ];
  String? _error;
  bool _past(int index) =>
      widget.story.turns.isNotEmpty && index < widget.story.stageIndex;
  String tr(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    for (final row in _fields) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _save() {
    try {
      final plan = <StoryStage>[
        for (var i = 0; i < _fields.length; i++)
          if (_past(i))
            widget.story.plan[i]
          else
            widget.story.plan[i].copyWith(
              title: _fields[i][0].text.trim(),
              objective: _fields[i][1].text.trim(),
              minRounds: int.parse(_fields[i][2].text),
              targetRounds: int.parse(_fields[i][3].text),
              acceptanceCriteria: _fields[i][4].text
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            ),
      ];
      widget.story.copyWith(plan: plan);
      Navigator.of(context).pop(plan);
    } catch (_) {
      setState(
        () => _error = tr(
          '需 3～8 阶段、每阶段 1～3 项条件，建议轮数合计须等于总轮数，最短轮数不能超过建议轮数。',
          'Use 3–8 stages, 1–3 criteria each, minimum ≤ target, and targets totaling the planned rounds.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('查看与编辑大纲', 'Review and edit outline')),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                '目标结局：${widget.story.config.targetEnding}',
                'Target ending: ${widget.story.config.targetEnding}',
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _fields.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text('${i + 1} / ${_fields.length}'),
                      if (_past(i))
                        Text(tr('已完成阶段（只读）', 'Completed stage (read-only)')),
                      TextField(
                        readOnly: _past(i),
                        controller: _fields[i][0],
                        decoration: InputDecoration(
                          labelText: tr('阶段名称', 'Stage name'),
                        ),
                      ),
                      TextField(
                        readOnly: _past(i),
                        controller: _fields[i][1],
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: tr('阶段目标', 'Stage objective'),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              readOnly: _past(i),
                              controller: _fields[i][2],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: tr('最短轮数', 'Minimum rounds'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              readOnly: _past(i),
                              controller: _fields[i][3],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: tr('建议轮数', 'Target rounds'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        readOnly: _past(i),
                        controller: _fields[i][4],
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: tr(
                            '达成条件（每行一项）',
                            'Acceptance criteria (one per line)',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('取消', 'Cancel')),
      ),
      FilledButton(
        key: const ValueKey('auto-story-outline-save'),
        onPressed: _save,
        child: Text(tr('保存大纲', 'Save outline')),
      ),
    ],
  );
}
