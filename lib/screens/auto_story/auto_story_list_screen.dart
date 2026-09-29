import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/app_settings.dart';
import '../../models/auto_story.dart';
import '../../services/ai/ai_gateway.dart';
import '../../services/auto_story/auto_story_export.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/page_layout.dart';
import '../../utils/snack.dart';
import 'auto_story_access.dart';
import 'auto_story_editor_screen.dart';
import 'auto_story_play_screen.dart';

class AutoStoryListScreen extends StatefulWidget {
  const AutoStoryListScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    super.key,
  });
  final LocalStorageService storage;
  final AiGateway aiService;
  final AppSettings settings;
  @override
  State<AutoStoryListScreen> createState() => AutoStoryListScreenState();
}

class AutoStoryListScreenState extends State<AutoStoryListScreen> {
  Future<void> refresh() async {
    if (!mounted) return;
    // Hide cached public cards until current source privacy is known.
    setState(() => _loading = true);
    await _load();
  }

  List<AutoStoryHeader> _stories = [];
  Set<String> _lockedSources = {};
  String _root = '';
  bool _loading = true;
  String? _error;
  int _loadId = 0;
  @override
  void initState() {
    super.initState();
    widget.storage.datasetEpochListenable.addListener(_datasetChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.storage.datasetEpochListenable.removeListener(_datasetChanged);
    super.dispose();
  }

  void _datasetChanged() {
    if (mounted) {
      setState(() => _stories = []);
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final id = ++_loadId, epoch = widget.storage.datasetEpoch;
    try {
      final stories = await widget.storage.autoStories.listStories();
      final characters = await widget.storage.loadCharacters();
      final root = await widget.storage.appDataDirectory;
      if (!mounted || id != _loadId || epoch != widget.storage.datasetEpoch) {
        return;
      }
      setState(() {
        _stories = stories;
        _lockedSources = characters
            .where((c) => c.isLocked)
            .map((c) => c.id)
            .toSet();
        _root = root.path;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && id == _loadId) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  bool _locked(AutoStoryHeader h) =>
      h.privacyRequired ||
      h.actors.any((a) => _lockedSources.contains(a.sourceId));
  Future<void> createStory() async {
    final result = await Navigator.of(context).push<AutoStoryEditorResult>(
      MaterialPageRoute(
        builder: (_) => AutoStoryEditorScreen(
          storage: widget.storage,
          settings: widget.settings,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      await _showStory(result.story.id, generatePlan: result.generatePlan);
    }
    await _load();
  }

  Future<void> _showStory(String id, {bool generatePlan = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AutoStoryPlayScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          settings: widget.settings,
          storyId: id,
          generatePlanOnOpen: generatePlan,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _open(AutoStoryHeader header) async {
    await _showStory(header.id);
  }

  Future<void> _menu(AutoStoryHeader header, String action) async {
    final epoch = widget.storage.datasetEpoch;
    try {
      if (!await unlockAutoStory(context, widget.storage, header) ||
          !mounted ||
          epoch != widget.storage.datasetEpoch) {
        return;
      }
      final story = await widget.storage.autoStories.loadStory(header.id);
      if (!mounted || epoch != widget.storage.datasetEpoch) return;
      if (action == 'rename') {
        final title = await showTextInputDialog(
          context: context,
          title: '重命名故事',
          initialText: story.config.title,
          emptyIsNull: true,
        );
        if (title != null && epoch == widget.storage.datasetEpoch) {
          await widget.storage.autoStories.mutateStory(
            story.id,
            (s) => s.copyWith(config: s.config.copyWith(title: title)),
            expectedRevision: story.revision,
          );
        }
      } else if (action == 'delete') {
        if (await showConfirmDialog(
          context: context,
          title: '删除故事',
          content: context.t('删除后无法恢复，确定删除这个故事？'),
        )) {
          if (epoch != widget.storage.datasetEpoch) return;
          await widget.storage.autoStories.deleteStory(story.id);
          await widget.storage.cleanupUnusedMedia();
        }
      } else if (action == 'export') {
        final include = await showDialog<bool>(
          context: context,
          builder: (c) => SimpleDialog(
            title: Text(c.t('导出演绎')),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, false),
                child: Text(c.t('仅正式正文（默认）')),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, true),
                child: Text(c.t('包含目标与大纲')),
              ),
            ],
          ),
        );
        if (include == null ||
            !mounted ||
            epoch != widget.storage.datasetEpoch) {
          return;
        }
        final ok = await exportAutoStoryText(
          story.toJson(),
          includePlan: include,
          english: context.isEnglish,
        );
        if (ok && mounted) context.showSnack('导出成功');
      }
      if (mounted) await _load();
    } catch (e) {
      if (mounted) context.showSnack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: Text(context.t('重试'))),
          ],
        ),
      );
    }
    final warning = widget.storage.autoStories.unreadableStories.isNotEmpty;
    return Column(
      children: [
        if (warning)
          MaterialBanner(
            content: Text(context.t('部分故事文件无法读取，原文件已保留。')),
            actions: [
              TextButton(onPressed: _load, child: Text(context.t('重试'))),
            ],
          ),
        Expanded(
          child: AdaptivePage(
            child: _stories.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.t('选好角色，写下结局，让故事自己展开。')),
                    ),
                  )
                : ListView.builder(
                    key: const PageStorageKey('auto-story-list'),
                    padding: EdgeInsets.fromLTRB(
                      0,
                      homeListTop(context) - kToolbarHeight,
                      0,
                      24,
                    ),
                    itemCount: _stories.length,
                    itemBuilder: (context, index) {
                      final story = _stories[index],
                          locked = _locked(_stories[index]);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Theme.of(context).colorScheme.surface.withValues(
                          alpha: widget.settings.characterListCardOpacity,
                        ),
                        child: ListTile(
                          leading: locked
                              ? const Icon(Icons.lock_outline)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: story.actors
                                      .map(
                                        (a) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 4,
                                          ),
                                          child: CircleAvatar(
                                            radius: 16,
                                            backgroundImage:
                                                a.avatarRelativePath == null
                                                ? null
                                                : FileImage(
                                                    File(
                                                      '$_root/${a.avatarRelativePath}',
                                                    ),
                                                  ),
                                            onBackgroundImageError:
                                                a.avatarRelativePath == null
                                                ? null
                                                : (_, _) {},
                                            child: a.avatarRelativePath == null
                                                ? Text(a.actorId)
                                                : null,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                          title: Text(
                            locked ? context.t('受保护的故事') : story.title,
                          ),
                          subtitle: locked
                              ? Text(context.t('解锁后查看'))
                              : Text(
                                  '${story.actors.map((a) => a.name).join(' / ')}\n'
                                  '${context.t(switch (story.status) {
                                    StoryStatus.draft => '草稿',
                                    StoryStatus.ready => '准备就绪',
                                    StoryStatus.running => '演绎中',
                                    StoryStatus.paused => '已暂停',
                                    StoryStatus.completed => '已完成',
                                  })} · ${story.completedRounds}/${story.plannedRounds} ${context.t('轮')} · ${context.t('阶段')} ${story.stageIndex + 1}\n'
                                  '${story.updatedAt.toLocal().toString().substring(0, 16)}',
                                ),
                          onTap: () => _open(story),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) => unawaited(_menu(story, v)),
                            itemBuilder: (c) => [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text(c.t('重命名故事')),
                              ),
                              PopupMenuItem(
                                value: 'export',
                                child: Text(c.t('导出演绎')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(c.t('删除故事')),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
