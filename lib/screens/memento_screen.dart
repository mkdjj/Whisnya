import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/memento.dart';
import '../models/app_character.dart';
import '../utils/app_i18n.dart';
import '../services/memento_service.dart';
import '../services/share_card_service.dart';

typedef MementoLocateCallback =
    Future<void> Function(
      MementoSnapshot snapshot,
      int entryIndex,
      SourceNavigationResult result,
    );
void _error(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t(
            error is StateError ? error.message.toString() : error.toString(),
          ),
        ),
      ),
    );

class MementoScreen extends StatefulWidget {
  const MementoScreen({
    super.key,
    required this.service,
    this.innerVoiceEnabled = false,
    this.characterId,
    this.onLocate,
  });
  final MementoService service;
  final bool innerVoiceEnabled;
  final String? characterId;
  final MementoLocateCallback? onLocate;
  @override
  State<MementoScreen> createState() => _MementoScreenState();
}

class _MementoScreenState extends State<MementoScreen> {
  final search = TextEditingController(), tag = TextEditingController();
  late Future<List<MementoIndex>> rows;
  late Future<List<AppCharacter>> characters;
  String? selectedCharacter;
  @override
  void initState() {
    super.initState();
    selectedCharacter = widget.characterId;
    characters = widget.service.storage.loadCharacters();
    _reload();
    widget.service.storage.datasetEpochListenable.addListener(_epoch);
  }

  void _epoch() {
    selectedCharacter = widget.characterId;
    characters = widget.service.storage.loadCharacters();
    if (mounted) setState(_reload);
  }

  void _reload() {
    rows = widget.service.queryMementos(
      MementoQuery(
        characterId: selectedCharacter,
        keyword: search.text,
        tag: tag.text.trim().isEmpty ? null : tag.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    widget.service.storage.datasetEpochListenable.removeListener(_epoch);
    search.dispose();
    tag.dispose();
    super.dispose();
  }

  Future<void> _open(MementoIndex row) async {
    try {
      final s = await widget.service.loadMemento(row.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MementoDetailScreen(
            service: widget.service,
            snapshot: s,
            innerVoiceEnabled: widget.innerVoiceEnabled,
            onLocate: widget.onLocate,
          ),
        ),
      );
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('回忆册'))),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (widget.characterId == null)
                FutureBuilder<List<AppCharacter>>(
                  future: characters,
                  builder: (c, s) => DropdownButtonFormField<String>(
                    initialValue: selectedCharacter ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: c.isEnglish ? 'Character' : '角色筛选',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(c.isEnglish ? 'All characters' : '全部角色'),
                      ),
                      for (final character in s.data ?? <AppCharacter>[])
                        DropdownMenuItem(
                          value: character.id,
                          child: Text(
                            character.isLocked
                                ? (c.isEnglish ? 'Locked character' : '已锁定角色')
                                : character.name,
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() {
                      selectedCharacter = id == '' ? null : id;
                      _reload();
                    }),
                  ),
                ),
              TextField(
                controller: search,
                decoration: InputDecoration(
                  labelText: context.t('搜索标题、备注和正文'),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(_reload),
              ),
              TextField(
                controller: tag,
                decoration: InputDecoration(labelText: context.t('按标签筛选')),
                onChanged: (_) => setState(_reload),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<MementoIndex>>(
            future: rows,
            builder: (context, s) {
              if (s.hasError) {
                return Center(child: Text(context.t('${s.error}')));
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) {
                return Center(child: Text(context.t('暂无收藏')));
              }
              return ListView.builder(
                itemCount: s.data!.length,
                itemBuilder: (context, i) {
                  final r = s.data![i];
                  return ListTile(
                    leading: Icon(
                      r.requiresUnlock ? Icons.lock : Icons.bookmark,
                    ),
                    title: Text(
                      r.requiresUnlock ? context.t('受保护的收藏') : r.title,
                    ),
                    subtitle: r.requiresUnlock
                        ? null
                        : Text(r.tags.join(' · ')),
                    onTap: () => _open(r),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

class MementoDetailScreen extends StatefulWidget {
  const MementoDetailScreen({
    super.key,
    required this.service,
    required this.snapshot,
    this.innerVoiceEnabled = false,
    this.onLocate,
  });
  final MementoService service;
  final MementoSnapshot snapshot;
  final bool innerVoiceEnabled;
  final MementoLocateCallback? onLocate;
  @override
  State<MementoDetailScreen> createState() => _MementoDetailScreenState();
}

class _MementoDetailScreenState extends State<MementoDetailScreen>
    with WidgetsBindingObserver {
  late MementoSnapshot snapshot;
  bool valid = true;
  @override
  void initState() {
    super.initState();
    snapshot = widget.snapshot;
    WidgetsBinding.instance.addObserver(this);
    widget.service.storage.datasetEpochListenable.addListener(_invalidate);
  }

  void _invalidate() {
    if (mounted) setState(() => valid = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.service.storage.datasetEpochListenable.removeListener(_invalidate);
    super.dispose();
  }

  Future<void> _unlock() async {
    try {
      final s = await widget.service.loadMemento(snapshot.id);
      if (mounted) {
        setState(() {
          snapshot = s;
          valid = true;
        });
      }
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _edit() async {
    final result = await editMementoMetadata(
      context,
      title: snapshot.title,
      tags: snapshot.tags,
      note: snapshot.note,
    );
    if (result == null) return;
    try {
      await widget.service.updateMementoMetadata(
        MementoMetadataPatch(
          id: snapshot.id,
          title: result.title,
          tags: result.tags,
          note: result.note,
        ),
      );
      final s = await widget.service.loadMemento(snapshot.id);
      if (mounted) setState(() => snapshot = s);
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _share() async {
    try {
      final s = await widget.service.loadMemento(snapshot.id);
      final paths = await widget.service.paths;
      final protected = await widget.service.protectionState(s.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ShareCardEditorScreen(
            snapshot: s,
            innerVoiceEnabled: widget.innerVoiceEnabled,
            mediaDirectory: '${paths.root.path}/collection/media',
            authorize: () => widget.service.loadMemento(s.id),
            datasetEpoch: widget.service.storage.datasetEpochListenable,
            initialProtectionState: protected,
            protectionState: () => widget.service.protectionState(s.id),
          ),
        ),
      );
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.t('删除收藏？')),
        content: Text(context.t('原对话和角色不会删除。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.t('删除')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.service.deleteMemento(snapshot.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _locate(int i) async {
    try {
      final r = await widget.service.locateMementoSource(snapshot.id, i);
      if (!mounted) return;
      const messages = {
        SourceNavigationResult.sourceMissing: '来源对话已删除；收藏保留当时内容',
        SourceNavigationResult.messageMissing: '原消息已删除；收藏保留当时内容',
        SourceNavigationResult.variantChanged: '原对话当前显示的是另一候选，不会切换候选',
        SourceNavigationResult.contentChanged: '原消息已改变；收藏保留当时内容',
      };
      if (messages[r] != null) _error(context, messages[r]!);
      if (r != SourceNavigationResult.sourceMissing &&
          r != SourceNavigationResult.messageMissing) {
        await widget.onLocate?.call(snapshot, i, r);
      }
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(valid ? snapshot.title : context.t('回忆册')),
      actions: valid
          ? [
              IconButton(onPressed: _edit, icon: const Icon(Icons.edit)),
              IconButton(onPressed: _share, icon: const Icon(Icons.image)),
              IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            ]
          : [],
    ),
    body: !valid
        ? Center(
            child: TextButton(
              onPressed: _unlock,
              child: Text(context.t('重新验证并查看')),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${snapshot.characterNameSnapshot} · ${snapshot.sessionTitleSnapshot}',
              ),
              Text(snapshot.tags.join(' · ')),
              if (snapshot.note.isNotEmpty) Text(snapshot.note),
              for (var i = 0; i < snapshot.entries.length; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.entries[i].speakerNameSnapshot,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SelectableText(snapshot.entries[i].contentSnapshot),
                        if (widget.innerVoiceEnabled &&
                            snapshot.entries[i].innerVoiceSnapshot.isNotEmpty)
                          ExpansionTile(
                            title: Text(context.t('心声')),
                            children: [
                              SelectableText(
                                snapshot.entries[i].innerVoiceSnapshot,
                              ),
                            ],
                          ),
                        TextButton(
                          onPressed: () => _locate(i),
                          child: Text(context.t('回到当时对话')),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}

typedef MementoMetadata = ({String title, List<String> tags, String note});
Future<MementoMetadata?> editMementoMetadata(
  BuildContext context, {
  required String title,
  List<String> tags = const [],
  String note = '',
  List<MementoEntry>? preview,
}) async {
  final t = TextEditingController(text: title),
      g = TextEditingController(text: tags.join(', ')),
      n = TextEditingController(text: note);
  String? error;
  final result = await showDialog<MementoMetadata>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(context.t(preview == null ? '编辑收藏' : '收藏到回忆册')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: t,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: context.t('标题')),
                ),
                TextField(
                  controller: g,
                  decoration: InputDecoration(
                    labelText: context.t('标签（逗号分隔，最多 8 个）'),
                  ),
                ),
                TextField(
                  controller: n,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: context.t('备注')),
                ),
                if (preview != null) ...[
                  Text(context.t('已选 ${preview.length} 条')),
                  for (final e in preview)
                    Text(
                      e.contentSnapshot,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
                if (error != null)
                  Text(
                    context.t(error!),
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final tags = g.text
                  .split(RegExp('[,，]'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              try {
                validateMetadata(t.text, tags, n.text);
                Navigator.pop(c, (
                  title: t.text.trim(),
                  tags: tags,
                  note: n.text,
                ));
              } catch (e) {
                set(() => error = '请检查标题、标签和备注长度');
              }
            },
            child: Text(context.t('保存')),
          ),
        ],
      ),
    ),
  );
  // Dialog exit animation can retain the fields until the next frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    t.dispose();
    g.dispose();
    n.dispose();
  });
  return result;
}

class ShareCardEditorScreen extends StatefulWidget {
  const ShareCardEditorScreen({
    super.key,
    required this.snapshot,
    required this.authorize,
    required this.datasetEpoch,
    required this.initialProtectionState,
    required this.protectionState,
    this.innerVoiceEnabled = false,
    this.mediaDirectory,
  });
  final MementoSnapshot snapshot;
  final bool innerVoiceEnabled;
  final String? mediaDirectory;
  final Future<MementoSnapshot> Function() authorize;
  final ValueListenable<int> datasetEpoch;
  final bool initialProtectionState;
  final Future<bool> Function() protectionState;
  @override
  State<ShareCardEditorScreen> createState() => _ShareCardEditorScreenState();
}

class _ShareCardEditorScreenState extends State<ShareCardEditorScreen>
    with WidgetsBindingObserver {
  late final TextEditingController title, character, user;
  final capture = GlobalKey();
  final hidden = <int>{};
  ShareCardTemplate template = ShareCardTemplate.dialogue;
  bool avatars = false, time = false, inner = false, busy = false, valid = true;
  bool _localizedDefaultName = false;
  String? background;
  Color? color;
  int page = 0;
  ShareCardPlan? plan;
  String? error;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.snapshot.title);
    character = TextEditingController(
      text: widget.snapshot.characterNameSnapshot,
    );
    user = TextEditingController(text: '我');
    WidgetsBinding.instance.addObserver(this);
    widget.datasetEpoch.addListener(_invalidate);
    _prepare();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_localizedDefaultName) {
      _localizedDefaultName = true;
      user.text = context.t('我');
      _prepare();
    }
  }

  void _invalidate() {
    if (mounted) {
      setState(() {
        valid = false;
        plan = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _invalidate();
  }

  @override
  void dispose() {
    title.dispose();
    character.dispose();
    user.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.datasetEpoch.removeListener(_invalidate);
    super.dispose();
  }

  void _prepare() {
    try {
      plan = ShareCardPlan.prepare(
        widget.snapshot,
        ShareCardOptions(
          title: title.text,
          characterName: character.text,
          userName: user.text,
          template: template,
          showAvatars: avatars,
          showTime: time,
          showInnerVoice: inner,
          innerVoiceAllowed: widget.innerVoiceEnabled,
          hiddenEntries: hidden,
          backgroundPath: background,
          backgroundColor: color,
          mediaDirectory: widget.mediaDirectory,
        ),
      );
      page = page.clamp(0, plan!.pages.length - 1);
      error = null;
    } catch (e) {
      plan = null;
      error = e.toString();
    }
  }

  void _change(VoidCallback action) => setState(() {
    action();
    _prepare();
  });
  Future<void> _background() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    if (await File(path).length() > 10 * 1024 * 1024) {
      if (mounted) _error(context, '背景图片不能超过 10 MiB');
      return;
    }
    if (mounted) _change(() => background = path);
  }

  Future<void> _save() async {
    if (plan == null || busy || !valid) return;
    setState(() => busy = true);
    final p = plan!;
    final epoch = widget.datasetEpoch.value;
    try {
      await widget.authorize();
      if (!mounted) return;
      final result = await saveSharePages(
        pageCount: p.pages.length,
        render: (i) async {
          if (await widget.protectionState() != widget.initialProtectionState) {
            _invalidate();
            throw StateError('Privacy changed; reopen preview');
          }
          if (!mounted || !valid || epoch != widget.datasetEpoch.value) {
            throw StateError('预览已失效');
          }
          setState(() => page = i);
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || !valid) throw StateError('Preview invalidated');
          final boundaryContext = capture.currentContext;
          if (boundaryContext == null || !boundaryContext.mounted) {
            throw StateError('Preview not ready');
          }
          await Scrollable.ensureVisible(boundaryContext);
          if (!mounted || !valid) throw StateError('Preview invalidated');
          if (background != null) {
            await precacheImage(
              ResizeImage(FileImage(File(background!)), width: 1080),
              context,
            );
          }
          for (final block in p.pages[i].blocks) {
            if (block.avatarAssetId != null &&
                widget.mediaDirectory != null &&
                mounted) {
              await precacheImage(
                ResizeImage(
                  FileImage(
                    File('${widget.mediaDirectory}/${block.avatarAssetId}'),
                  ),
                  width: 72,
                ),
                context,
                onError: (_, _) {},
              );
            }
          }
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || !valid || epoch != widget.datasetEpoch.value) {
            throw StateError('Preview invalidated');
          }
          return renderShareCardPage(capture);
        },
        save: (i, bytes) async {
          if (await widget.protectionState() != widget.initialProtectionState) {
            _invalidate();
            throw StateError('Privacy changed; reopen preview');
          }
          if (!mounted || !valid || epoch != widget.datasetEpoch.value) {
            throw StateError('预览已失效');
          }
          return FilePicker.platform.saveFile(
            dialogTitle: context.t('保存 PNG'),
            fileName: 'memento-${i + 1}.png',
            type: FileType.custom,
            allowedExtensions: const ['png'],
            bytes: bytes,
          );
        },
      );
      if (mounted) {
        _error(
          context,
          result.status == ShareExportStatus.cancelled
              ? '已取消'
              : result.status == ShareExportStatus.failed
              ? '保存失败：${result.error}'
              : '已保存 ${result.paths.length}/${p.pages.length} 页${result.error == null ? '' : '；${result.error}'}',
        );
      }
    } catch (e) {
      if (mounted) _error(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t('分享卡预览')),
      actions: [
        TextButton(
          onPressed: busy || !valid || plan == null ? null : _save,
          child: Text(context.t(busy ? '保存中…' : '保存 PNG')),
        ),
      ],
    ),
    body: !valid
        ? Center(child: Text(context.t('预览已失效，请返回重新打开')))
        : AbsorbPointer(
            absorbing: busy,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(context.t('隐藏姓名、头像和时间不会清除正文或标题中的个人信息，请自行确认。')),
                TextField(
                  controller: title,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: context.t('分享标题')),
                  onChanged: (_) => _change(() {}),
                ),
                DropdownButton<ShareCardTemplate>(
                  value: template,
                  items: [
                    DropdownMenuItem(
                      value: ShareCardTemplate.dialogue,
                      child: Text(context.t('简洁对白')),
                    ),
                    DropdownMenuItem(
                      value: ShareCardTemplate.note,
                      child: Text(context.t('便签')),
                    ),
                    DropdownMenuItem(
                      value: ShareCardTemplate.dark,
                      child: Text(context.t('深色卡片')),
                    ),
                  ],
                  onChanged: (v) => _change(() => template = v!),
                ),
                TextField(
                  controller: character,
                  decoration: InputDecoration(
                    labelText: context.t('角色显示名（可改为角色 A）'),
                  ),
                  onChanged: (_) => _change(() {}),
                ),
                TextField(
                  controller: user,
                  decoration: InputDecoration(
                    labelText: context.t('用户显示名（默认“我”）'),
                  ),
                  onChanged: (_) => _change(() {}),
                ),
                Wrap(
                  children: [
                    for (final c in [
                      Colors.white,
                      const Color(0xfffff5d6),
                      const Color(0xff20232a),
                    ])
                      IconButton(
                        onPressed: () => _change(() => color = c),
                        icon: Icon(Icons.circle, color: c),
                      ),
                    TextButton(
                      onPressed: _background,
                      child: Text(context.t('选择背景图')),
                    ),
                    if (background != null)
                      TextButton(
                        onPressed: () => _change(() => background = null),
                        child: Text(context.t('移除背景图')),
                      ),
                  ],
                ),
                SwitchListTile(
                  title: Text(context.t('显示头像')),
                  value: avatars,
                  onChanged: (v) => _change(() => avatars = v),
                ),
                SwitchListTile(
                  title: Text(context.t('显示时间')),
                  value: time,
                  onChanged: (v) => _change(() => time = v),
                ),
                SwitchListTile(
                  title: Text(context.t('显示心声')),
                  value: inner,
                  onChanged:
                      widget.innerVoiceEnabled &&
                          widget.snapshot.entries.any(
                            (e) => e.innerVoiceSnapshot.isNotEmpty,
                          )
                      ? (v) => _change(() => inner = v)
                      : null,
                ),
                ExpansionTile(
                  title: Text(context.t('选择分享的消息')),
                  children: [
                    for (var i = 0; i < widget.snapshot.entries.length; i++)
                      CheckboxListTile(
                        title: Text(
                          widget.snapshot.entries[i].contentSnapshot,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: !hidden.contains(i),
                        onChanged: (v) => _change(() {
                          v == true ? hidden.remove(i) : hidden.add(i);
                        }),
                      ),
                  ],
                ),
                if (error != null) Text(context.t(error!)),
                if (plan != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: page > 0
                            ? () => setState(() => page--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('${page + 1}/${plan!.pages.length}'),
                      IconButton(
                        onPressed: page + 1 < plan!.pages.length
                            ? () => setState(() => page++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 360,
                      child: RepaintBoundary(
                        key: capture,
                        child: ShareCardPageView(plan: plan!, page: page),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
  );
}
