import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/chat_bubble_preset.dart';
import '../models/chat_bubble_theme.dart';
import '../services/local_storage_service.dart';
import 'bubble_package_import_screen.dart';
import '../utils/app_i18n.dart';
import '../utils/confirm_dialog.dart';
import '../utils/snack.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/setting_slider.dart';

class ChatBubblePresetScreen extends StatefulWidget {
  const ChatBubblePresetScreen({required this.storage, super.key});

  final LocalStorageService storage;

  @override
  State<ChatBubblePresetScreen> createState() => _ChatBubblePresetScreenState();
}

class _ChatBubblePresetScreenState extends State<ChatBubblePresetScreen> {
  var _settings = const ChatBubblePresetSettings();
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final settings = await widget.storage.loadChatBubblePresets();
      if (mounted) {
        setState(() {
          _settings = settings;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showSnack(error.toString());
    }
  }

  Future<void> _save(ChatBubblePresetSettings settings) async {
    await widget.storage.saveChatBubblePresets(settings);
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _edit([ChatBubblePreset? preset]) async {
    final result = await Navigator.of(context).push<ChatBubblePreset>(
      MaterialPageRoute(
        builder: (_) => _ChatBubblePresetEditScreen(
          storage: widget.storage,
          preset: preset,
        ),
      ),
    );
    if (result == null) return;
    final presets = [..._settings.presets];
    final index = presets.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      presets.add(result);
    } else {
      presets[index] = result;
    }
    await _save(_settings.copyWith(presets: presets));
  }

  Future<void> _importPackage() async {
    final imported = await pickBubblePackage(context, widget.storage);
    if (imported != null) await _load();
  }

  Future<void> _duplicate(ChatBubblePreset preset) async {
    final now = DateTime.now();
    await _save(
      _settings.copyWith(
        presets: [
          ..._settings.presets,
          preset.copyWith(
            id: 'bubble_${now.microsecondsSinceEpoch}',
            name: '${preset.name}（副本）',
          ),
        ],
      ),
    );
  }

  Future<void> _delete(ChatBubblePreset preset) async {
    final refs = await widget.storage.bubblePresetReferences(preset.id);
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除气泡预设',
      content:
          '角色气泡 ${refs.characterRole} 个，我的气泡 ${refs.characterUser} 个；'
          '群聊 AI ${refs.theaterRole} 个，群聊我的 ${refs.theaterUser} 个。\n'
          '已有引用无需改写，会自动回退默认圆润。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    await _save(
      _settings.copyWith(
        presets: _settings.presets
            .where((item) => item.id != preset.id)
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = _settings.userPresets.toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('聊天气泡'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(context.t('新建气泡')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _importPackage,
                      icon: const Icon(Icons.folder_zip_outlined),
                      label: const Text('导入气泡资源包'),
                    ),
                  ),
                ),
                Expanded(
                  child: presets.isEmpty
                      ? Center(child: Text(context.t('还没有气泡预设')))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                          itemCount: presets.length,
                          itemBuilder: (context, index) {
                            final preset = presets[index];
                            return Card(
                              child: ListTile(
                                title: Text(preset.name),
                                subtitle: Text(
                                  context.t(
                                    preset.appearance.isImageSkin
                                        ? '图片皮肤'
                                        : '参数气泡',
                                  ),
                                ),
                                trailing: Wrap(
                                  children: [
                                    IconButton(
                                      tooltip: context.t('编辑'),
                                      onPressed: () => _edit(preset),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: context.t('复制'),
                                      onPressed: () => _duplicate(preset),
                                      icon: const Icon(Icons.copy_outlined),
                                    ),
                                    IconButton(
                                      tooltip: context.t('删除'),
                                      onPressed: () => _delete(preset),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _ChatBubblePresetEditScreen extends StatefulWidget {
  const _ChatBubblePresetEditScreen({required this.storage, this.preset});

  final LocalStorageService storage;
  final ChatBubblePreset? preset;

  @override
  State<_ChatBubblePresetEditScreen> createState() =>
      _ChatBubblePresetEditScreenState();
}

class _ChatBubblePresetEditScreenState
    extends State<_ChatBubblePresetEditScreen> {
  late final TextEditingController _name;
  late final String _id;
  late ChatBubbleAppearance _appearance;
  late bool _imageMode;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    _id = preset?.id ?? 'bubble_${DateTime.now().microsecondsSinceEpoch}';
    _name = TextEditingController(text: preset?.name ?? '');
    _appearance = preset?.appearance ?? const ChatBubbleAppearance();
    _imageMode = _appearance.isImageSkin;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickColor(bool text) async {
    final result = await showColorPickerDialog(
      context: context,
      title: text ? '文字颜色' : '填充颜色',
      value: text ? _appearance.textColor : _appearance.backgroundColor,
    );
    if (result == null) return;
    setState(() {
      _appearance = text
          ? _appearance.copyWith(
              textColor: result.color,
              clearTextColor: result.color == null,
            )
          : _appearance.copyWith(
              backgroundColor: result.color,
              clearBackgroundColor: result.color == null,
            );
    });
  }

  void _updateSkin(ChatBubbleImageSkin Function(ChatBubbleImageSkin) update) {
    final skin = _appearance.imageSkin;
    if (skin != null) {
      setState(
        () => _appearance = _appearance.copyWith(imageSkin: update(skin)),
      );
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      context.showSnack('请输入预设名称');
      return;
    }
    Navigator.of(context).pop(
      ChatBubblePreset(
        id: _id,
        name: name,
        appearance: _imageMode
            ? _appearance
            : _appearance.copyWith(clearImageSkin: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = _appearance.imageSkin;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(widget.preset == null ? '新建气泡' : '编辑气泡')),
        actions: [
          IconButton(
            tooltip: context.t('保存'),
            onPressed: _save,
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.t('预设名称')),
          ),
          const SizedBox(height: 12),
          Text(context.t(_imageMode ? '导入图片气泡' : '参数气泡')),
          const SizedBox(height: 16),
          Text(context.t('角色预览')),
          _bubblePreview(
            isUser: false,
            appearance: _imageMode
                ? _appearance
                : _appearance.copyWith(clearImageSkin: true),
            text: _imageMode ? '预览' : '你好，很高兴见到你。',
          ),
          Text(context.t('我的预览')),
          _bubblePreview(
            isUser: true,
            appearance: _imageMode
                ? _appearance
                : _appearance.copyWith(clearImageSkin: true),
            text: _imageMode ? '预览' : '好的，开始吧。',
          ),
          if (!_imageMode) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in ChatBubbleStyle.values)
                  ChoiceChip(
                    label: Text(context.t(chatBubbleStyleLabel(style))),
                    selected: _appearance.style == style,
                    onSelected: (_) => setState(
                      () => _appearance = _appearance.copyWith(style: style),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined),
            title: Text(context.t(_imageMode ? '填充颜色' : '气泡颜色')),
            onTap: () => _pickColor(false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.format_color_text),
            title: Text(context.t('文字颜色')),
            onTap: () => _pickColor(true),
          ),
          SettingSlider.transparency(
            label: _imageMode ? '填充透明度' : '气泡透明度',
            opacity: _appearance.opacity,
            onChanged: (opacity) => setState(
              () => _appearance = _appearance.copyWith(opacity: opacity),
            ),
          ),
          if (_imageMode) ...[
            if (skin != null) ...[
              const SizedBox(height: 12),
              _BubbleSkinRegionPreview(skin: skin),
              const SizedBox(height: 12),
              _rangeSetting(
                '拉伸区域：左右',
                RangeValues(skin.stretchRegion.left, skin.stretchRegion.right),
                (value) => _updateSkin(
                  (skin) => skin.copyWith(
                    stretchRegion: BubbleNormalizedRect(
                      left: value.start,
                      top: skin.stretchRegion.top,
                      right: value.end,
                      bottom: skin.stretchRegion.bottom,
                    ),
                  ),
                ),
              ),
              _rangeSetting(
                '拉伸区域：上下',
                RangeValues(skin.stretchRegion.top, skin.stretchRegion.bottom),
                (value) => _updateSkin(
                  (skin) => skin.copyWith(
                    stretchRegion: BubbleNormalizedRect(
                      left: skin.stretchRegion.left,
                      top: value.start,
                      right: skin.stretchRegion.right,
                      bottom: value.end,
                    ),
                  ),
                ),
              ),
              _rangeSetting(
                '填充区域：左右',
                RangeValues(skin.fillRegion.left, skin.fillRegion.right),
                (value) => _updateSkin(
                  (skin) => skin.copyWith(
                    fillRegion: BubbleNormalizedRect(
                      left: value.start,
                      top: skin.fillRegion.top,
                      right: value.end,
                      bottom: skin.fillRegion.bottom,
                    ),
                  ),
                ),
              ),
              _rangeSetting(
                '填充区域：上下',
                RangeValues(skin.fillRegion.top, skin.fillRegion.bottom),
                (value) => _updateSkin(
                  (skin) => skin.copyWith(
                    fillRegion: BubbleNormalizedRect(
                      left: skin.fillRegion.left,
                      top: value.start,
                      right: skin.fillRegion.right,
                      bottom: value.end,
                    ),
                  ),
                ),
              ),
              for (final side in _PaddingSide.values)
                SettingSlider(
                  label: '文字边距：${side.label}',
                  value: side.value(skin.textPadding),
                  min: 0,
                  max: 48,
                  divisions: 48,
                  display: side.value(skin.textPadding).round().toString(),
                  onChanged: (value) => _updateSkin(
                    (skin) => skin.copyWith(
                      textPadding: side.update(skin.textPadding, value),
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(context.t('保存')),
          ),
        ],
      ),
    );
  }

  Widget _bubblePreview({
    required bool isUser,
    required ChatBubbleAppearance appearance,
    required String text,
  }) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: SizedBox(
      width: 180,
      height: 96,
      child: ChatBubble(
        isUser: isUser,
        appearance: appearance,
        maxWidth: 180,
        margin: EdgeInsets.zero,
        child: Text(context.t(text)),
      ),
    ),
  );

  Widget _rangeSetting(
    String label,
    RangeValues values,
    ValueChanged<RangeValues> onChanged,
  ) => InputDecorator(
    decoration: InputDecoration(labelText: context.t(label)),
    child: RangeSlider(
      values: values,
      min: 0,
      max: 1,
      divisions: 100,
      labels: RangeLabels(
        values.start.toStringAsFixed(2),
        values.end.toStringAsFixed(2),
      ),
      onChanged: onChanged,
    ),
  );
}

class _BubbleSkinRegionPreview extends StatelessWidget {
  const _BubbleSkinRegionPreview({required this.skin});

  final ChatBubbleImageSkin skin;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 180),
      child: AspectRatio(
        aspectRatio: skin.imageWidth / skin.imageHeight,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            key: const ValueKey('bubble-skin-region-preview'),
            fit: StackFit.expand,
            children: [
              Image.file(File(skin.imagePath), fit: BoxFit.fill),
              _region(
                constraints,
                skin.stretchRegion,
                Colors.orange,
                const ValueKey('bubble-skin-stretch-region'),
              ),
              _region(
                constraints,
                skin.fillRegion,
                Colors.green,
                const ValueKey('bubble-skin-fill-region'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _region(
    BoxConstraints constraints,
    BubbleNormalizedRect rect,
    Color color,
    Key key,
  ) => Positioned(
    left: constraints.maxWidth * rect.left,
    top: constraints.maxHeight * rect.top,
    width: constraints.maxWidth * (rect.right - rect.left),
    height: constraints.maxHeight * (rect.bottom - rect.top),
    child: IgnorePointer(
      key: key,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color, width: 2),
        ),
      ),
    ),
  );
}

enum _PaddingSide {
  left('左'),
  top('上'),
  right('右'),
  bottom('下');

  const _PaddingSide(this.label);
  final String label;

  double value(BubbleContentInsets insets) => switch (this) {
    left => insets.left,
    top => insets.top,
    right => insets.right,
    bottom => insets.bottom,
  };

  BubbleContentInsets update(BubbleContentInsets value, double next) =>
      BubbleContentInsets(
        left: this == left ? next : value.left,
        top: this == top ? next : value.top,
        right: this == right ? next : value.right,
        bottom: this == bottom ? next : value.bottom,
      );
}
