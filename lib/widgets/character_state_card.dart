import 'package:flutter/material.dart';
import '../models/character_state.dart';

class CharacterStateCard extends StatefulWidget {
  const CharacterStateCard({
    super.key,
    required this.view,
    required this.onEdit,
    required this.onRefresh,
    required this.onReset,
    this.busy = false,
    this.english = false,
  });
  final CharacterStateView view;
  final Future<void> Function(StateEdit) onEdit;
  final Future<void> Function() onRefresh, onReset;
  final bool busy, english;
  @override
  State<CharacterStateCard> createState() => _CharacterStateCardState();
}

class _CharacterStateCardState extends State<CharacterStateCard> {
  bool expanded = false, working = false;
  String? error;
  String t(String zh, String en) => widget.english ? en : zh;
  String label(String key) => switch (key) {
    'emotion' => t('情绪', 'Emotion'),
    'relationship' => t('双方关系', 'Relationship'),
    'location' => t('地点', 'Location'),
    _ => t('当前动作', 'Action'),
  };
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError && e.message == 'stateModified'
              ? t('状态已被手动修改，请重试', 'State changed. Please retry.')
              : t(
                  '状态更新失败，原状态已保留；请重试',
                  'State update failed. Previous state preserved; retry.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> edit() async {
    final original = widget.view;
    final controllers = {
      for (final k in characterStateLimits.keys)
        k: TextEditingController(text: original.values[k] ?? ''),
    };
    final locks = Map<String, bool>.of(original.locks);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t('编辑状态', 'Edit state')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in characterStateLimits.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        TextField(
                          controller: controllers[k],
                          maxLength: characterStateLimits[k],
                          maxLines: null,
                          decoration: InputDecoration(
                            labelText: label(k),
                            hintText: t('未知', 'Unknown'),
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            t('锁定（空值保持未知）', 'Lock (empty stays unknown)'),
                          ),
                          value: locks[k] ?? false,
                          onChanged: (v) =>
                              setDialogState(() => locks[k] = v ?? false),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    final values = {
      for (final k in controllers.keys)
        k: controllers[k]!.text.trim().isEmpty
            ? null
            : controllers[k]!.text.trim(),
    };
    // Dialog route animations may still refer to controllers until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
    if (saved == true && mounted) {
      await run(
        () => widget.onEdit(
          StateEdit(
            expectedRevision: original.revision,
            values: values,
            locks: locks,
          ),
        ),
      );
    }
  }

  Future<void> reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('恢复为未知？', 'Reset to unknown?')),
        content: Text(
          t(
            '当前四项状态和锁定将清空，历史剧情节点会保留。',
            'Clear the four current values and locks. Saved story checkpoints are preserved.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t('确认', 'Confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await run(widget.onReset);
  }

  @override
  Widget build(BuildContext context) {
    final busy = working || widget.busy;
    final preview =
        widget.view.values.values.whereType<String>().firstOrNull ??
        t('未知', 'Unknown');
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(t('当前状态', 'Current state')),
            subtitle: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => expanded = !expanded),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final k in characterStateLimits.keys)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${label(k)}: ${widget.view.values[k] ?? t('未知', 'Unknown')}',
                            ),
                          ),
                          IconButton(
                            tooltip: t('切换锁定', 'Toggle lock'),
                            visualDensity: VisualDensity.compact,
                            onPressed: busy
                                ? null
                                : () => run(
                                    () => widget.onEdit(
                                      StateEdit(
                                        expectedRevision: widget.view.revision,
                                        locks: {
                                          k: widget.view.locks[k] != true,
                                        },
                                      ),
                                    ),
                                  ),
                            icon: Icon(
                              widget.view.locks[k] == true
                                  ? Icons.lock
                                  : Icons.lock_open,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.view.createdAt.isNotEmpty)
                    Text(
                      '${t('最后更新于', 'Last updated')}: ${widget.view.createdAt}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy ? null : edit,
                        child: Text(t('编辑', 'Edit')),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => run(widget.onRefresh),
                        child: Text(t('AI 刷新', 'AI refresh')),
                      ),
                      TextButton(
                        onPressed: busy ? null : reset,
                        child: Text(t('恢复为未知', 'Reset to unknown')),
                      ),
                    ],
                  ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
