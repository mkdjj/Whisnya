import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/api_config.dart';
import '../models/app_character.dart';
import '../models/image_crop_region.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';
import '../utils/role_import_parser.dart';
import '../utils/snack.dart';
import '../widgets/app_background.dart';
import 'image_crop_screen.dart';

class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({required this.storage, this.character, super.key});

  final LocalStorageService storage;
  final AppCharacter? character;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final String _draftCharacterId;
  late final TextEditingController _nameController;
  late final TextEditingController _avatarController;
  late final TextEditingController _backgroundImageController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _personalityController;
  late final TextEditingController _backgroundController;
  late final TextEditingController _speakingStyleController;
  late final TextEditingController _openingMessageController;
  late final TextEditingController _extraPromptController;

  var _apiConfig = ApiConfig();
  var _defaultEndpointId = '';
  var _isSaving = false;
  var _isPickingImage = false;
  var _backgroundImageRegion = ImageCropRegion.full;

  bool get _isEditing => widget.character != null;

  @override
  void initState() {
    super.initState();
    final character = widget.character;
    _draftCharacterId =
        character?.id ?? 'character_${DateTime.now().microsecondsSinceEpoch}';
    _nameController = TextEditingController(text: character?.name ?? '');
    _avatarController = TextEditingController(text: character?.avatar ?? '');
    _backgroundImageController = TextEditingController(
      text: character?.backgroundImage ?? '',
    );
    _backgroundImageRegion =
        character?.backgroundImageRegion ?? ImageCropRegion.full;
    _descriptionController = TextEditingController(
      text: character?.description ?? '',
    );
    _personalityController = TextEditingController(
      text: character?.personality ?? '',
    );
    _backgroundController = TextEditingController(
      text: character?.background ?? '',
    );
    _speakingStyleController = TextEditingController(
      text: character?.speakingStyle ?? '',
    );
    _openingMessageController = TextEditingController(
      text: character?.openingMessage ?? '',
    );
    _extraPromptController = TextEditingController(
      text: character?.extraPrompt ?? '',
    );
    _defaultEndpointId = character?.defaultEndpointId ?? '';
    unawaited(_loadApiConfig());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _avatarController.dispose();
    _backgroundImageController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    _backgroundController.dispose();
    _speakingStyleController.dispose();
    _openingMessageController.dispose();
    _extraPromptController.dispose();
    super.dispose();
  }

  AppCharacter _buildCharacter(DateTime now) {
    final existing = widget.character;
    return AppCharacter(
      id: _draftCharacterId,
      name: _nameController.text.trim(),
      avatar: _avatarController.text.trim(),
      backgroundImage: _backgroundImageController.text.trim(),
      backgroundImageRegion: _backgroundImageController.text.trim().isEmpty
          ? ImageCropRegion.full
          : _backgroundImageRegion,
      backgroundImageOpacity: existing?.backgroundImageOpacity ?? 1,
      backgroundBlur: existing?.backgroundBlur ?? 0,
      bubbleOpacity: existing?.bubbleOpacity ?? 0.92,
      inputOpacity: existing?.inputOpacity ?? 0.92,
      description: _descriptionController.text.trim(),
      personality: _personalityController.text.trim(),
      background: _backgroundController.text.trim(),
      speakingStyle: _speakingStyleController.text.trim(),
      openingMessage: _openingMessageController.text.trim(),
      extraPrompt: _extraPromptController.text.trim(),
      defaultEndpointId: _defaultEndpointId,
      useFullChatContext: existing?.useFullChatContext ?? true,
      isPinned: existing?.isPinned ?? false,
      isHidden: existing?.isHidden ?? false,
      isLocked: existing?.isLocked ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastUsedAt: existing?.lastUsedAt ?? now,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      await widget.storage.saveCharacter(_buildCharacter(now));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      context.showSnack(error.toString());
      setState(() => _isSaving = false);
    }
  }

  Future<void> _loadApiConfig() async {
    try {
      final config = await widget.storage.loadApiConfig();
      if (!mounted) return;
      setState(() {
        _apiConfig = config;
        _defaultEndpointId =
            config.effectiveEndpoint(_defaultEndpointId)?.id ?? '';
      });
    } catch (_) {
      // Keep character editing usable even if API config is broken.
    }
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboard?.text?.trim();
    if (clipboardText != null && clipboardText.isNotEmpty) {
      controller.text = clipboardText;
    }

    if (!mounted) return;
    final parsed = await showDialog<ParsedRoleFields>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('导入角色设定')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              hintText: context.t('粘贴包含名称、简介、性格、说话风格等内容的角色卡'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton.icon(
            onPressed: () {
              final parsed = RoleImportParser.parse(controller.text);
              Navigator.of(context).pop(parsed);
            },
            icon: const Icon(Icons.auto_fix_high),
            label: Text(context.t('自动识别')),
          ),
        ],
      ),
    );
    controller.dispose();

    if (parsed == null) {
      return;
    }

    _applyParsedFields(parsed);
  }

  void _applyParsedFields(ParsedRoleFields parsed) {
    void setIfNotEmpty(TextEditingController controller, String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        controller.text = trimmed;
      }
    }

    setState(() {
      setIfNotEmpty(_nameController, parsed.name);
      setIfNotEmpty(_descriptionController, parsed.description);
      setIfNotEmpty(_personalityController, parsed.personality);
      setIfNotEmpty(_backgroundController, parsed.background);
      setIfNotEmpty(_speakingStyleController, parsed.speakingStyle);
      setIfNotEmpty(_openingMessageController, parsed.openingMessage);
      setIfNotEmpty(_extraPromptController, parsed.extraPrompt);
    });
    context.showSnack(
      parsed.filledCount == 0 ? '未识别到明确字段' : '已识别 ${parsed.filledCount} 个字段',
    );
  }

  Future<void> _copyRoleText() async {
    final now = DateTime.now();
    final character = _buildCharacter(now);
    await Clipboard.setData(
      ClipboardData(text: RoleImportParser.formatCharacter(character)),
    );
    if (!mounted) return;
    context.showSnack('角色设定已复制');
  }

  Future<void> _exportCharacterPackage() async {
    try {
      final dialogTitle = context.t('保存角色包');
      final character = _buildCharacter(DateTime.now());
      final bytes = await widget.storage.exportCharacterPackage(character);
      await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: '${_safeFileName(character.name)}.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      context.showSnack('角色包已导出');
    } catch (error) {
      if (!mounted) return;
      context.showSnack(error.toString());
    }
  }

  String _safeFileName(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return safe.isEmpty
        ? (context.isEnglish ? 'character_package' : '角色包')
        : safe;
  }

  Future<void> _pickAndCropImage(_CharacterImageKind kind) async {
    if (_isPickingImage) return;

    setState(() => _isPickingImage = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final picked = result.files.single;
      var sourcePath = picked.path;
      if (sourcePath == null && picked.bytes != null) {
        final file = await widget.storage.saveTemporaryImage(picked.bytes!);
        sourcePath = file.path;
      }
      if (!mounted) return;
      if (sourcePath == null) {
        context.showSnack('没有拿到可读取的图片路径。');
        return;
      }

      if (kind == _CharacterImageKind.background) {
        final selection = await _openBackgroundCropper(kind, sourcePath);
        if (selection == null) return;
        final savedPath = await widget.storage.saveMediaImage(
          folder: kind.folder,
          characterId: _draftCharacterId,
          bytes: picked.bytes ?? await File(sourcePath).readAsBytes(),
        );
        setState(() {
          _backgroundImageController.text = savedPath;
          _backgroundImageRegion = selection;
        });
        return;
      }

      final cropped = await _openCropper(kind, sourcePath);
      if (cropped == null) {
        return;
      }

      final savedPath = await widget.storage.saveMediaImage(
        folder: kind.folder,
        characterId: _draftCharacterId,
        bytes: cropped,
      );
      setState(() => kind.controller(this).text = savedPath);
    } catch (error) {
      if (!mounted) return;
      context.showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _cropCurrentImage(_CharacterImageKind kind) async {
    final path = kind.controller(this).text.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      context.showSnack('当前没有可裁剪的图片。');
      return;
    }

    if (kind == _CharacterImageKind.background) {
      final selection = await _openBackgroundCropper(kind, path);
      if (selection == null) return;
      setState(() => _backgroundImageRegion = selection);
      return;
    }

    final cropped = await _openCropper(kind, path);
    if (cropped == null) {
      return;
    }

    final savedPath = await widget.storage.saveMediaImage(
      folder: kind.folder,
      characterId: _draftCharacterId,
      bytes: cropped,
    );
    setState(() => kind.controller(this).text = savedPath);
  }

  Future<Uint8List?> _openCropper(_CharacterImageKind kind, String imagePath) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(
          imagePath: imagePath,
          title: context.t(kind.cropTitle),
          aspectRatio: kind.aspectRatio,
          outputWidth: kind.outputWidth,
          outputHeight: kind.outputHeight,
        ),
      ),
    );
  }

  Future<ImageCropRegion?> _openBackgroundCropper(
    _CharacterImageKind kind,
    String imagePath,
  ) {
    return Navigator.of(context).push<ImageCropRegion>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(
          imagePath: imagePath,
          title: context.t(kind.cropTitle),
          aspectRatio: kind.aspectRatio,
          outputWidth: kind.outputWidth,
          outputHeight: kind.outputHeight,
          renderOutput: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(_isEditing ? '编辑角色' : '新建角色')),
        actions: [
          IconButton(
            tooltip: context.t('导入角色设定'),
            onPressed: _showImportDialog,
            icon: const Icon(Icons.content_paste_search),
          ),
          IconButton(
            tooltip: context.t('复制角色设定'),
            onPressed: _copyRoleText,
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: context.t('保存角色'),
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ImagePickerField(
              label: context.t('头像'),
              path: _avatarController.text,
              shape: BoxShape.circle,
              isBusy: _isPickingImage,
              onPick: () => _pickAndCropImage(_CharacterImageKind.avatar),
              onCrop: () => _cropCurrentImage(_CharacterImageKind.avatar),
              onClear: () => setState(_avatarController.clear),
            ),
            const SizedBox(height: 12),
            _ImagePickerField(
              label: context.t('聊天背景图'),
              path: _backgroundImageController.text,
              region: _backgroundImageRegion,
              shape: BoxShape.rectangle,
              isBusy: _isPickingImage,
              onPick: () => _pickAndCropImage(_CharacterImageKind.background),
              onCrop: () => _cropCurrentImage(_CharacterImageKind.background),
              onClear: () => setState(() {
                _backgroundImageController.clear();
                _backgroundImageRegion = ImageCropRegion.full;
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: context.t('名称')),
              textInputAction: TextInputAction.next,
              validator: (value) => value == null || value.trim().isEmpty
                  ? context.t('请输入角色名称')
                  : null,
            ),
            const SizedBox(height: 12),
            _multiLineField(_descriptionController, context.t('简介')),
            const SizedBox(height: 12),
            _multiLineField(_personalityController, context.t('性格')),
            const SizedBox(height: 12),
            _multiLineField(_backgroundController, context.t('背景故事')),
            const SizedBox(height: 12),
            _multiLineField(_speakingStyleController, context.t('说话风格')),
            const SizedBox(height: 12),
            _multiLineField(_openingMessageController, context.t('开场白')),
            const SizedBox(height: 12),
            _multiLineField(_extraPromptController, context.t('补充设定')),
            const SizedBox(height: 12),
            if (_apiConfig.endpoints.isEmpty)
              InputDecorator(
                decoration: InputDecoration(labelText: context.t('默认模型')),
                child: Text(context.t('请先到 API 设置添加配置')),
              )
            else
              DropdownButtonFormField<String>(
                initialValue:
                    _apiConfig.endpointById(_defaultEndpointId) == null
                    ? null
                    : _defaultEndpointId,
                decoration: InputDecoration(labelText: context.t('默认模型')),
                items: [
                  for (final endpoint in _apiConfig.endpoints)
                    DropdownMenuItem(
                      value: endpoint.id,
                      child: Text(endpoint.name),
                    ),
                ],
                onChanged: (endpointId) {
                  if (endpointId != null) {
                    setState(() => _defaultEndpointId = endpointId);
                  }
                },
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(context.t('保存角色')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _exportCharacterPackage,
              icon: const Icon(Icons.archive_outlined),
              label: Text(context.t('导出角色包')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _multiLineField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      minLines: 2,
      maxLines: 5,
    );
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.label,
    required this.path,
    required this.shape,
    required this.isBusy,
    required this.onPick,
    required this.onCrop,
    required this.onClear,
    this.region = ImageCropRegion.full,
  });

  final String label;
  final String path;
  final ImageCropRegion region;
  final BoxShape shape;
  final bool isBusy;
  final VoidCallback onPick;
  final VoidCallback onCrop;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final file = path.trim().isEmpty ? null : File(path.trim());
    final hasImage = file != null && file.existsSync();
    final previewWidth = shape == BoxShape.circle ? 72.0 : 84.0;
    final previewHeight = shape == BoxShape.circle ? 72.0 : 112.0;

    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Container(
            width: previewWidth,
            height: previewHeight,
            decoration: BoxDecoration(
              shape: shape,
              borderRadius: shape == BoxShape.rectangle
                  ? BorderRadius.circular(8)
                  : null,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              image: hasImage && shape == BoxShape.circle
                  ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
                  : null,
            ),
            child: !hasImage
                ? const Icon(Icons.image_outlined)
                : shape == BoxShape.rectangle
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: croppedFileImage(context, file, region: region),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isBusy ? null : onPick,
                  icon: const Icon(Icons.folder_open),
                  label: Text(context.t('选择图片')),
                ),
                OutlinedButton.icon(
                  onPressed: hasImage ? onCrop : null,
                  icon: const Icon(Icons.crop),
                  label: Text(context.t('裁剪')),
                ),
                OutlinedButton.icon(
                  onPressed: path.trim().isEmpty ? null : onClear,
                  icon: const Icon(Icons.clear),
                  label: Text(context.t('清空')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CharacterImageKind {
  avatar,
  background;

  TextEditingController controller(_CharacterEditScreenState state) {
    return switch (this) {
      _CharacterImageKind.avatar => state._avatarController,
      _CharacterImageKind.background => state._backgroundImageController,
    };
  }

  String get folder {
    return switch (this) {
      _CharacterImageKind.avatar => 'avatars',
      _CharacterImageKind.background => 'backgrounds',
    };
  }

  String get cropTitle {
    return switch (this) {
      _CharacterImageKind.avatar => '裁剪头像',
      _CharacterImageKind.background => '裁剪聊天背景',
    };
  }

  double get aspectRatio {
    return switch (this) {
      _CharacterImageKind.avatar => 1,
      _CharacterImageKind.background => 9 / 16,
    };
  }

  int get outputWidth {
    return switch (this) {
      _CharacterImageKind.avatar => 512,
      _CharacterImageKind.background => 1080,
    };
  }

  int get outputHeight {
    return switch (this) {
      _CharacterImageKind.avatar => 512,
      _CharacterImageKind.background => 1920,
    };
  }
}
