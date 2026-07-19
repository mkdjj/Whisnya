import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/chat_bubble_preset.dart';
import '../models/chat_bubble_theme.dart';
import '../services/bubble_import/bubble_import_models.dart';
import '../services/bubble_import/bubble_package_detector.dart';
import '../services/bubble_import/bubble_package_import_service.dart';
import '../services/bubble_import/bubble_package_scanner.dart';
import '../services/local_storage_service.dart';
import '../utils/snack.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/color_picker_dialog.dart';

Future<ChatBubblePreset?> pickBubblePackage(
  BuildContext context,
  LocalStorageService storage,
) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['zip'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  BubblePackageScanResult? scan;
  try {
    final file = picked.files.single;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    scan = await BubblePackageScanner().scan(
      bytes: bytes,
      originalFileName: file.name,
    );
    final candidate = await BubblePackageDetector().detect(scan);
    if (!context.mounted) return null;
    if (candidate.level == BubblePackageRecognitionLevel.failed) {
      context.showSnack(candidate.reasons.join('；'));
      return null;
    }
    return await Navigator.of(context).push<ChatBubblePreset>(
      MaterialPageRoute(
        builder: (_) => BubblePackageImportScreen(
          storage: storage,
          scan: scan!,
          candidate: candidate,
        ),
      ),
    );
  } catch (error) {
    if (context.mounted) context.showSnack(error.toString());
    return null;
  } finally {
    await scan?.dispose();
  }
}

class BubblePackageImportScreen extends StatefulWidget {
  const BubblePackageImportScreen({
    required this.storage,
    required this.scan,
    required this.candidate,
    super.key,
  });

  final LocalStorageService storage;
  final BubblePackageScanResult scan;
  final BubblePackageCandidate candidate;

  @override
  State<BubblePackageImportScreen> createState() =>
      _BubblePackageImportScreenState();
}

class _BubblePackageImportScreenState extends State<BubblePackageImportScreen> {
  late final TextEditingController _name;
  late String _rolePath;
  String? _userPath;
  late BubblePackageUserImageMode _userMode;
  late RangeValues _stretchX;
  late RangeValues _stretchY;
  late RangeValues _fillX;
  late RangeValues _fillY;
  late List<double> _padding;
  late int _fillColor;
  late int _textColor;
  late double _opacity;
  var _saving = false;

  List<BubblePackageFile> get _images => widget.scan.files
      .where((file) => file.isImage && !file.isAnimated)
      .toList();

  @override
  void initState() {
    super.initState();
    final candidate = widget.candidate;
    _name = TextEditingController(text: candidate.name ?? '导入气泡');
    _rolePath = candidate.rolePath ?? _images.first.relativePath;
    _userPath = candidate.userPath;
    _userMode = candidate.userPath == null
        ? BubblePackageUserImageMode.mirrorRole
        : BubblePackageUserImageMode.manual;
    final stretch = candidate.stretchRegion;
    final fill = candidate.fillRegion;
    final padding = candidate.textPadding;
    _stretchX = RangeValues(stretch?.left ?? .33, stretch?.right ?? .67);
    _stretchY = RangeValues(stretch?.top ?? .33, stretch?.bottom ?? .67);
    _fillX = RangeValues(fill?.left ?? .12, fill?.right ?? .88);
    _fillY = RangeValues(fill?.top ?? .12, fill?.bottom ?? .88);
    _padding = [
      padding?.left ?? 18,
      padding?.top ?? 12,
      padding?.right ?? 18,
      padding?.bottom ?? 12,
    ];
    _fillColor = candidate.fillColor ?? 0xffffffff;
    _textColor = candidate.textColor ?? 0xff000000;
    _opacity = candidate.opacity ?? .92;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ChatBubbleAppearance _appearance(String path, {required bool mirror}) {
    final file = widget.scan.find(path)!;
    return ChatBubbleAppearance(
      backgroundColor: _fillColor,
      textColor: _textColor,
      opacity: _opacity,
      imageSkin: ChatBubbleImageSkin(
        imagePath: file.file.path,
        imageWidth: file.width ?? 100,
        imageHeight: file.height ?? 60,
        stretchRegion: BubbleNormalizedRect(
          left: _stretchX.start,
          top: _stretchY.start,
          right: _stretchX.end,
          bottom: _stretchY.end,
        ),
        fillRegion: BubbleNormalizedRect(
          left: _fillX.start,
          top: _fillY.start,
          right: _fillX.end,
          bottom: _fillY.end,
        ),
        textPadding: BubbleContentInsets(
          left: _padding[0],
          top: _padding[1],
          right: _padding[2],
          bottom: _padding[3],
        ),
        mirrorForUser: mirror,
      ),
    );
  }

  Future<void> _pickColor(bool text) async {
    final result = await showColorPickerDialog(
      context: context,
      title: text ? '文字颜色' : '填充颜色',
      value: text ? _textColor : _fillColor,
    );
    if (result?.color == null) return;
    setState(
      () => text ? _textColor = result!.color! : _fillColor = result!.color!,
    );
  }

  Future<void> _import() async {
    setState(() => _saving = true);
    try {
      final preset = await BubblePackageImportService(storage: widget.storage)
          .import(
            BubblePackageMapping(
              scan: widget.scan,
              candidate: widget.candidate,
              name: _name.text,
              rolePath: _rolePath,
              userMode: _userMode,
              userPath: _userPath,
              stretchRegion: BubbleNormalizedRect(
                left: _stretchX.start,
                top: _stretchY.start,
                right: _stretchX.end,
                bottom: _stretchY.end,
              ),
              fillRegion: BubbleNormalizedRect(
                left: _fillX.start,
                top: _fillY.start,
                right: _fillX.end,
                bottom: _fillY.end,
              ),
              textPadding: BubbleContentInsets(
                left: _padding[0],
                top: _padding[1],
                right: _padding[2],
                bottom: _padding[3],
              ),
              fillColor: _fillColor,
              textColor: _textColor,
              opacity: _opacity,
            ),
          );
      if (mounted) Navigator.of(context).pop(preset);
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userPath = _userMode == BubblePackageUserImageMode.manual
        ? (_userPath ?? _rolePath)
        : _rolePath;
    return Scaffold(
      appBar: AppBar(title: const Text('导入气泡资源包')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '扫描结果：${widget.scan.files.length} 个文件，${widget.scan.imageCount} 张图片，'
            '${widget.scan.configCount} 个配置',
          ),
          Text(
            '识别格式：${widget.candidate.detectedFormat}（${widget.candidate.level.name}）',
          ),
          for (final reason in widget.candidate.reasons) Text('• $reason'),
          for (final warning in [
            ...widget.scan.warnings,
            ...widget.candidate.warnings,
          ])
            Text(
              '⚠ $warning',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '气泡名称'),
          ),
          _imageSelect(
            '角色 / AI 气泡',
            _rolePath,
            (value) => setState(() => _rolePath = value!),
          ),
          SegmentedButton<BubblePackageUserImageMode>(
            segments: const [
              ButtonSegment(
                value: BubblePackageUserImageMode.mirrorRole,
                label: Text('自动镜像'),
              ),
              ButtonSegment(
                value: BubblePackageUserImageMode.shareRole,
                label: Text('共用角色图'),
              ),
              ButtonSegment(
                value: BubblePackageUserImageMode.manual,
                label: Text('手动指定'),
              ),
            ],
            selected: {_userMode},
            onSelectionChanged: (value) =>
                setState(() => _userMode = value.first),
          ),
          if (_userMode == BubblePackageUserImageMode.manual)
            _imageSelect(
              '我的气泡',
              _userPath ?? _rolePath,
              (value) => setState(() => _userPath = value),
            ),
          const SizedBox(height: 12),
          const Text('实时预览：短文本 / 长文本换行'),
          _preview(false, _rolePath, false),
          _preview(
            true,
            userPath,
            _userMode == BubblePackageUserImageMode.mirrorRole,
          ),
          _range(
            '拉伸区域：左右',
            _stretchX,
            (value) => setState(() => _stretchX = value),
          ),
          _range(
            '拉伸区域：上下',
            _stretchY,
            (value) => setState(() => _stretchY = value),
          ),
          _range('填充区域：左右', _fillX, (value) => setState(() => _fillX = value)),
          _range('填充区域：上下', _fillY, (value) => setState(() => _fillY = value)),
          for (var i = 0; i < 4; i++)
            _paddingSlider(i, const ['左', '上', '右', '下'][i]),
          ListTile(
            title: const Text('填充颜色'),
            leading: const Icon(Icons.palette_outlined),
            onTap: () => _pickColor(false),
          ),
          ListTile(
            title: const Text('文字颜色'),
            leading: const Icon(Icons.format_color_text),
            onTap: () => _pickColor(true),
          ),
          Slider(
            value: _opacity,
            onChanged: (value) => setState(() => _opacity = value),
          ),
          Text('填充透明度：${(_opacity * 100).round()}%'),
          FilledButton.icon(
            onPressed: _saving ? null : _import,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done),
            label: const Text('确认导入'),
          ),
        ],
      ),
    );
  }

  Widget _imageSelect(
    String label,
    String value,
    ValueChanged<String?> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final file in _images)
        DropdownMenuItem(
          value: file.relativePath,
          child: Text(file.relativePath, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: changed,
  );

  Widget _preview(bool isUser, String path, bool mirror) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: ChatBubble(
        isUser: isUser,
        appearance: _appearance(path, mirror: mirror),
        maxWidth: 230,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Text(isUser ? '好的，开始吧。' : '这是一段会自动换行的长文本，用来检查拉伸和文字边距。'),
      ),
    ),
  );

  Widget _range(
    String label,
    RangeValues value,
    ValueChanged<RangeValues> changed,
  ) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: RangeSlider(values: value, divisions: 100, onChanged: changed),
  );

  Widget _paddingSlider(int index, String side) => Row(
    children: [
      SizedBox(width: 90, child: Text('文字边距：$side')),
      Expanded(
        child: Slider(
          value: _padding[index],
          max: 64,
          divisions: 64,
          onChanged: (value) => setState(() => _padding[index] = value),
        ),
      ),
      SizedBox(width: 32, child: Text(_padding[index].round().toString())),
    ],
  );
}
