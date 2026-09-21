import 'package:flutter/material.dart';
import '../../models/chat_session.dart';
import '../../services/story/story_checkpoint_service.dart';
import '../../utils/app_i18n.dart';

Future<String?> storyNameDialog(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(c.t(title)),
      content: TextField(
        controller: controller,
        maxLength: 80,
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('取消'))),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: Text(c.t('保存')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class StoryCheckpointsScreen extends StatefulWidget {
  const StoryCheckpointsScreen({
    super.key,
    required this.service,
    this.characterId,
    this.onFork,
  });
  final StoryCheckpointService service;
  final String? characterId;
  final ValueChanged<ChatSession>? onFork;
  @override
  State<StoryCheckpointsScreen> createState() => _StoryCheckpointsScreenState();
}

class _StoryCheckpointsScreenState extends State<StoryCheckpointsScreen> {
  late Future<List<Map<String, dynamic>>> _items;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = widget.service.list(characterId: widget.characterId);
  }

  Future<void> _open(String id) async {
    try {
      final snapshot = await widget.service.load(id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          builder: (c, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Text(snapshot.title, style: Theme.of(c).textTheme.titleLarge),
              Text(c.t('分支只继承存档中的正文和状态，不继承来源总结或记忆。当前角色设定与世界书仍会生效。')),
              for (final m in snapshot.messages)
                ListTile(
                  title: Text(m.isUser ? c.t('我') : snapshot.characterName),
                  subtitle: Text(m.effectiveContent),
                ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () async {
                      final title = await storyNameDialog(
                        c,
                        '重命名',
                        initial: snapshot.title,
                      );
                      if (title == null) return;
                      await widget.service.rename(id, title);
                      if (c.mounted) Navigator.pop(c);
                    },
                    child: Text(c.t('重命名')),
                  ),
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: c,
                        builder: (d) => AlertDialog(
                          title: Text(d.t('删除剧情存档？已有分支不受影响。')),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: Text(d.t('取消')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: Text(d.t('删除')),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      await widget.service.delete(id);
                      if (c.mounted) Navigator.pop(c);
                    },
                    child: Text(c.t('删除')),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final title = await storyNameDialog(
                        c,
                        '新分支名称',
                        initial: snapshot.title,
                      );
                      if (title == null) return;
                      try {
                        final branch = await widget.service.fork(
                          id,
                          title: title,
                        );
                        if (c.mounted) Navigator.pop(c);
                        widget.onFork?.call(branch);
                      } catch (e) {
                        if (c.mounted) {
                          ScaffoldMessenger.of(
                            c,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: Text(c.t('从存档继续')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('剧情存档'))),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (c, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) return Center(child: Text(c.t('暂无剧情存档')));
        return ListView(
          children: [
            for (final row in s.data!)
              ListTile(
                leading: Icon(
                  row['requiresUnlock'] == true
                      ? Icons.lock
                      : Icons.bookmark_outline,
                ),
                title: Text(c.t(row['title'] as String)),
                onTap: () => _open(row['id'] as String),
              ),
          ],
        );
      },
    ),
  );
}
