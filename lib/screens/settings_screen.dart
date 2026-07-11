import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/image_crop_region.dart';
import '../services/ai_service.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';
import '../utils/character_import_flow.dart';
import '../utils/page_layout.dart';
import '../utils/password_lock.dart';
import '../utils/snack.dart';
import '../widgets/app_background.dart';
import 'api_settings_screen.dart';
import 'image_crop_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.storage,
    required this.settings,
    required this.onSettingsChanged,
    this.aiService,
    super.key,
  });

  final LocalStorageService storage;
  final AiService? aiService;
  final AppSettings settings;
  final Future<void> Function() onSettingsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;
  var _isBusy = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _settings = widget.settings;
    }
  }

  void _applySettings(AppSettings settings) {
    setState(() => _settings = settings);
    unawaited(() async {
      await widget.storage.saveSettings(settings);
      await widget.onSettingsChanged();
    }());
  }

  void _previewSettings(AppSettings settings) {
    setState(() => _settings = settings);
  }

  Future<void> _openApiSettings() async {
    final aiService = widget.aiService;
    if (aiService == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ApiSettingsScreen(storage: widget.storage, aiService: aiService),
      ),
    );
  }

  Future<void> _pickBackground() async {
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
    if (sourcePath == null) {
      _showSnack('没有拿到可读取的图片路径。');
      return;
    }

    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final aspectRatio = size.height <= 0 ? 9 / 16 : size.width / size.height;
    final outputWidth = aspectRatio >= 1 ? 1920 : 1080;
    final outputHeight = (outputWidth / aspectRatio).round();

    final selection = await Navigator.of(context).push<ImageCropSelection>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(
          imagePath: sourcePath!,
          title: context.t('裁剪界面背景'),
          aspectRatio: aspectRatio,
          outputWidth: outputWidth,
          outputHeight: outputHeight,
          renderOutput: false,
        ),
      ),
    );
    if (selection == null) {
      return;
    }

    final path = await widget.storage.saveMediaImage(
      folder: 'global',
      characterId: 'app',
      bytes: picked.bytes ?? await File(sourcePath).readAsBytes(),
    );
    _applySettings(
      _settings.copyWith(
        globalBackgroundImage: path,
        globalBackgroundRegion: selection.region,
      ),
    );
  }

  Future<void> _exportAllData() async {
    var includeApiKeys = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.t('导出全部数据')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.t('备份可能包含角色、聊天记录、小说原文、图片、设置和 API 配置，请不要公开上传。')),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeApiKeys,
                title: Text(context.t('包含 API Key')),
                subtitle: Text(context.t('默认不包含 API Key')),
                onChanged: (value) {
                  setDialogState(() => includeApiKeys = value ?? false);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t('继续')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _runBusy(() async {
      final bytes = await widget.storage.exportAllData(
        includeApiKeys: includeApiKeys,
      );
      await _saveBytes('Whisnya_backup_${_dateStamp()}.zip', bytes);
    });
  }

  Future<void> _importAllData() async {
    final ok = await _confirm(
      title: '导入全部数据',
      content: '这会覆盖当前 App 本地数据。建议先导出一份备份。',
    );
    if (!ok) return;

    final bytes = await _pickZipBytes();
    if (bytes == null) return;

    await _runBusy(() async {
      await widget.storage.importAllData(bytes);
      _settings = await widget.storage.loadSettings();
      await widget.onSettingsChanged();
    });
  }

  Future<void> _importCharacterCards() async {
    if (_isBusy) return;
    await showCharacterImportFlow(context: context, storage: widget.storage);
  }

  Future<Uint8List?> _pickZipBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final picked = result.files.single;
    if (picked.bytes != null) {
      return picked.bytes;
    }
    if (picked.path != null) {
      return File(picked.path!).readAsBytes();
    }
    return null;
  }

  Future<void> _saveBytes(String fileName, Uint8List bytes) async {
    await FilePicker.platform.saveFile(
      dialogTitle: context.t('保存文件'),
      fileName: fileName,
      bytes: bytes,
    );
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await action();
      if (mounted) _showSnack('完成');
    } catch (error) {
      if (mounted) _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String content,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.t(title)),
            content: Text(context.t(content)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.t('继续')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _pickThemeMode() async {
    final value = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.t('主题模式')),
        children: [
          _themeOption(context, ThemeMode.system, context.t('跟随系统')),
          _themeOption(context, ThemeMode.light, context.t('白天')),
          _themeOption(context, ThemeMode.dark, context.t('黑夜')),
        ],
      ),
    );
    if (value != null) {
      _applySettings(_settings.copyWith(themeMode: value));
    }
  }

  Widget _themeOption(BuildContext context, ThemeMode value, String label) {
    return ListTile(
      title: Text(label),
      trailing: _settings.themeMode == value ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(value),
    );
  }

  Future<void> _pickLanguage() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.t('语言')),
        children: [
          for (final code in [appLanguageSystem, appLanguageZh, appLanguageEn])
            ListTile(
              title: Text(languageName(context, code)),
              trailing: _settings.languageCode == code
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(code),
            ),
        ],
      ),
    );
    if (value != null) {
      _applySettings(_settings.copyWith(languageCode: value));
    }
  }

  Future<void> _pickColor({
    required String title,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) async {
    var red = value == null ? 17 : (value >> 16) & 0xFF;
    var green = value == null ? 24 : (value >> 8) & 0xFF;
    var blue = value == null ? 39 : value & 0xFF;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final color = Color(_argb(red, green, blue));
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                ),
                _rgbSlider('R', red, (value) {
                  setDialogState(() => red = value.round());
                }),
                _rgbSlider('G', green, (value) {
                  setDialogState(() => green = value.round());
                }),
                _rgbSlider('B', blue, (value) {
                  setDialogState(() => blue = value.round());
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  onChanged(null);
                  Navigator.of(context).pop();
                },
                child: Text(context.t('默认')),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('取消')),
              ),
              FilledButton(
                onPressed: () {
                  onChanged(_argb(red, green, blue));
                  Navigator.of(context).pop();
                },
                child: Text(context.t('应用')),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rgbSlider(String label, int value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }

  int _argb(int red, int green, int blue) {
    return 0xFF000000 | (red << 16) | (green << 8) | blue;
  }

  Widget _compactSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return SizedBox(
      height: 24,
      child: Slider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }

  Future<void> _showPasswordSettings() async {
    if (!_settings.hasPrivacyPassword) {
      await _setPassword();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.t('隐私密码')),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(context).pop();
              _setPassword(requireCurrent: true);
            },
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.t('修改密码')),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(context).pop();
              _recoverPassword();
            },
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline),
              title: Text(context.t('忘记密码')),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(context).pop();
              _deletePassword();
            },
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline),
              title: Text(context.t('删除密码')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setPassword({bool requireCurrent = false}) async {
    final currentController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final questionController = TextEditingController(
      text: _settings.recoveryQuestion,
    );
    final answerController = TextEditingController();

    final saved = await showDialog<AppSettings>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t(requireCurrent ? '修改隐私密码' : '设置隐私密码')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (requireCurrent) ...[
                TextField(
                  controller: currentController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: context.t('当前密码')),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: context.t('新密码')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: InputDecoration(labelText: context.t('确认新密码')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: questionController,
                decoration: InputDecoration(labelText: context.t('恢复问题')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: answerController,
                decoration: InputDecoration(labelText: context.t('恢复答案')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final current = currentController.text.trim();
              final password = passwordController.text.trim();
              final confirm = confirmController.text.trim();
              final question = questionController.text.trim();
              final answer = answerController.text.trim();
              if (requireCurrent &&
                  !PasswordLock.verify(
                    current,
                    _settings.privacyPasswordSalt,
                    _settings.privacyPasswordHash,
                  )) {
                _showSnack('当前密码不正确');
                return;
              }
              final next = _settingsWithPassword(
                password: password,
                confirm: confirm,
                question: question,
                answer: answer,
              );
              if (next == null) return;
              Navigator.of(context).pop(next);
            },
            child: Text(context.t('保存')),
          ),
        ],
      ),
    );

    currentController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    questionController.dispose();
    answerController.dispose();

    if (saved == null) return;
    _applySettings(saved);
    _showSnack('隐私密码已保存');
  }

  Future<void> _recoverPassword() async {
    if (!_settings.hasRecoveryAnswer) {
      _showSnack('没有设置恢复问题，无法找回密码。');
      return;
    }

    final answerController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    final saved = await showDialog<AppSettings>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('找回隐私密码')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_settings.recoveryQuestion),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: answerController,
                decoration: InputDecoration(labelText: context.t('恢复答案')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: context.t('新密码')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: InputDecoration(labelText: context.t('确认新密码')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final answer = PasswordLock.normalizeAnswer(
                answerController.text,
              );
              if (!PasswordLock.verify(
                answer,
                _settings.recoveryAnswerSalt,
                _settings.recoveryAnswerHash,
              )) {
                _showSnack('恢复答案不正确');
                return;
              }
              final password = passwordController.text.trim();
              final confirm = confirmController.text.trim();
              if (password.length < 4) {
                _showSnack('密码至少 4 位');
                return;
              }
              if (password != confirm) {
                _showSnack('两次输入的密码不一致');
                return;
              }
              final salt = PasswordLock.newSalt();
              final recoveryAnswerHash =
                  PasswordLock.needsRehash(_settings.recoveryAnswerHash)
                  ? PasswordLock.hash(answer, _settings.recoveryAnswerSalt)
                  : _settings.recoveryAnswerHash;
              Navigator.of(context).pop(
                _settings.copyWith(
                  privacyPasswordSalt: salt,
                  privacyPasswordHash: PasswordLock.hash(password, salt),
                  recoveryAnswerHash: recoveryAnswerHash,
                ),
              );
            },
            child: Text(context.t('重置密码')),
          ),
        ],
      ),
    );

    answerController.dispose();
    passwordController.dispose();
    confirmController.dispose();

    if (saved == null) return;
    _applySettings(saved);
    _showSnack('隐私密码已重置');
  }

  Future<void> _deletePassword() async {
    final passwordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('删除隐私密码')),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(labelText: context.t('当前密码')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              if (!PasswordLock.verify(
                passwordController.text.trim(),
                _settings.privacyPasswordSalt,
                _settings.privacyPasswordHash,
              )) {
                _showSnack('当前密码不正确');
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: Text(context.t('删除')),
          ),
        ],
      ),
    );

    passwordController.dispose();

    if (confirmed != true) return;
    _applySettings(
      _settings.copyWith(
        privacyPasswordSalt: '',
        privacyPasswordHash: '',
        recoveryQuestion: '',
        recoveryAnswerSalt: '',
        recoveryAnswerHash: '',
      ),
    );
    _showSnack('隐私密码已删除');
  }

  AppSettings? _settingsWithPassword({
    required String password,
    required String confirm,
    required String question,
    required String answer,
  }) {
    if (password.length < 4) {
      _showSnack('密码至少 4 位');
      return null;
    }
    if (password != confirm) {
      _showSnack('两次输入的密码不一致');
      return null;
    }
    if (question.isEmpty || answer.trim().isEmpty) {
      _showSnack('请填写恢复问题和答案');
      return null;
    }

    final passwordSalt = PasswordLock.newSalt();
    final answerSalt = PasswordLock.newSalt();
    return _settings.copyWith(
      privacyPasswordSalt: passwordSalt,
      privacyPasswordHash: PasswordLock.hash(password, passwordSalt),
      recoveryQuestion: question,
      recoveryAnswerSalt: answerSalt,
      recoveryAnswerHash: PasswordLock.hash(
        PasswordLock.normalizeAnswer(answer),
        answerSalt,
      ),
    );
  }

  String _dateStamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  void _setCustomChatSummaryEnabled(bool value) {
    _applySettings(
      _settings.copyWith(
        useCustomChatSummaryItems: value,
        customChatSummaryItems:
            value && _isDefaultSummaryItems(_settings.customChatSummaryItems)
            ? _summaryDefaults(isTheater: false)
            : _settings.customChatSummaryItems,
      ),
    );
  }

  void _setCustomTheaterSummaryEnabled(bool value) {
    _applySettings(
      _settings.copyWith(
        useCustomTheaterSummaryItems: value,
        customTheaterSummaryItems:
            value &&
                _isDefaultSummaryItems(
                  _settings.customTheaterSummaryItems,
                  isTheater: true,
                )
            ? _summaryDefaults(isTheater: true)
            : _settings.customTheaterSummaryItems,
      ),
    );
  }

  Future<void> _addSummaryItem({required bool isTheater}) async {
    final items = _summaryItems(isTheater);
    if (items.length >= AppSettings.maxSummaryItems) {
      _showSnack('最多 20 个总结项目');
      return;
    }
    final text = await _summaryItemDialog(title: '添加项目');
    if (text == null) return;
    _saveSummaryItems(isTheater: isTheater, items: [...items, text]);
  }

  Future<void> _editSummaryItem({
    required int index,
    required bool isTheater,
  }) async {
    final items = _summaryItems(isTheater);
    if (index < 0 || index >= items.length) return;
    final text = await _summaryItemDialog(
      title: '编辑项目',
      initialText: items[index],
    );
    if (text == null) return;
    final next = [...items]..[index] = text;
    _saveSummaryItems(isTheater: isTheater, items: next);
  }

  void _deleteSummaryItem({required int index, required bool isTheater}) {
    final items = _summaryItems(isTheater);
    if (items.length <= 1) {
      _showSnack('至少保留一个总结项目');
      return;
    }
    final next = [...items]..removeAt(index);
    _saveSummaryItems(isTheater: isTheater, items: next);
  }

  void _restoreSummaryItems({required bool isTheater}) {
    _saveSummaryItems(
      isTheater: isTheater,
      items: _summaryDefaults(isTheater: isTheater),
    );
  }

  List<String> _summaryItems(bool isTheater) {
    return isTheater
        ? _settings.customTheaterSummaryItems
        : _settings.customChatSummaryItems;
  }

  void _saveSummaryItems({
    required bool isTheater,
    required List<String> items,
  }) {
    _applySettings(
      isTheater
          ? _settings.copyWith(customTheaterSummaryItems: items)
          : _settings.copyWith(customChatSummaryItems: items),
    );
  }

  List<String> _summaryDefaults({required bool isTheater}) {
    if (isTheater) {
      return context.isEnglish
          ? AppSettings.defaultTheaterSummaryItemsEn
          : AppSettings.defaultTheaterSummaryItems;
    }
    return context.isEnglish
        ? AppSettings.defaultChatSummaryItemsEn
        : AppSettings.defaultChatSummaryItems;
  }

  bool _isDefaultSummaryItems(List<String> items, {bool isTheater = false}) {
    final zh = isTheater
        ? AppSettings.defaultTheaterSummaryItems
        : AppSettings.defaultChatSummaryItems;
    final en = isTheater
        ? AppSettings.defaultTheaterSummaryItemsEn
        : AppSettings.defaultChatSummaryItemsEn;
    bool same(List<String> defaults) =>
        items.length == defaults.length &&
        Iterable<int>.generate(
          items.length,
        ).every((i) => items[i] == defaults[i]);
    return same(zh) || same(en);
  }

  Future<String?> _summaryItemDialog({
    required String title,
    String initialText = '',
  }) async {
    final controller = TextEditingController(text: initialText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t(title)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(hintText: context.t('总结项目')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(context).pop(text.isEmpty ? null : text);
            },
            child: Text(context.t('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _showSnack(String message) {
    context.showSnack(message);
  }

  @override
  Widget build(BuildContext context) {
    return _content();
  }

  Widget _content() {
    return AppBackground(
      settings: _settings,
      child: AdaptivePage(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            homeListTop(context) - kToolbarHeight,
            0,
            148,
          ),
          children: [
            _tile(
              icon: Icons.key,
              title: context.t('API 设置'),
              subtitle: context.t('模型、Base URL、API Key'),
              onTap: widget.aiService == null ? null : _openApiSettings,
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: const Icon(Icons.stream),
              title: Text(context.t('流式对话')),
              subtitle: Text(context.t('边返回边显示')),
              value: _settings.streamResponses,
              onChanged: (value) =>
                  _applySettings(_settings.copyWith(streamResponses: value)),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: const Icon(Icons.psychology_alt_outlined),
              title: Text(context.t('显示思考过程')),
              subtitle: Text(context.t('把 reasoning_content 显示在回复里')),
              value: _settings.showReasoningContent,
              onChanged: (value) => _applySettings(
                _settings.copyWith(showReasoningContent: value),
              ),
            ),
            _tile(
              icon: Icons.language,
              title: context.t('语言'),
              subtitle: languageName(context, _settings.languageCode),
              onTap: _pickLanguage,
            ),
            _tile(
              icon: Icons.checkroom_outlined,
              title: context.t('主题设置'),
              subtitle: context.t('与界面和颜色相关的一些设置'),
              onTap: _openThemeSettings,
            ),
            _tile(
              icon: Icons.summarize_outlined,
              title: context.t('聊天总结'),
              subtitle: context.t('配置角色聊天和群聊总结项目'),
              onTap: _openSummarySettings,
            ),
            _sectionTitle(context.t('隐私')),
            _tile(
              icon: Icons.lock_outline,
              title: context.t('隐私密码'),
              subtitle: _settings.hasPrivacyPassword
                  ? context.t('已设置')
                  : context.t('未设置'),
              onTap: _showPasswordSettings,
            ),
            _sectionTitle(context.t('数据')),
            _tile(
              icon: Icons.archive_outlined,
              title: context.t('批量导入角色卡'),
              subtitle: context.t('支持 Whisnya 角色包和常见角色卡文件'),
              onTap: _isBusy ? null : _importCharacterCards,
            ),
            _tile(
              icon: Icons.backup_outlined,
              title: context.t('导出全部数据'),
              subtitle: context.t('默认不包含 API Key'),
              onTap: _isBusy ? null : _exportAllData,
            ),
            _tile(
              icon: Icons.restore,
              title: context.t('导入全部数据'),
              subtitle: context.t('会覆盖当前本地数据'),
              onTap: _isBusy ? null : _importAllData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Future<void> _openThemeSettings() {
    return _openSubSettingsPage(
      title: '主题设置',
      childrenBuilder: _themeSettingsChildren,
    );
  }

  Future<void> _openSummarySettings() {
    return _openSubSettingsPage(
      title: '聊天总结',
      childrenBuilder: _summarySettingsChildren,
    );
  }

  Future<void> _openSubSettingsPage({
    required String title,
    required List<Widget> Function(VoidCallback refresh) childrenBuilder,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            void refresh() {
              if (mounted) setPageState(() {});
            }

            return ColoredBox(
              color: Colors.white,
              child: AppBackground(
                settings: _settings,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    title: Text(pageContext.t(title)),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    surfaceTintColor: Colors.transparent,
                  ),
                  body: AdaptivePage(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 80),
                      children: childrenBuilder(refresh),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _themeSettingsChildren(VoidCallback refresh) {
    void preview(AppSettings settings) {
      _previewSettings(settings);
      refresh();
    }

    void apply(AppSettings settings) {
      _applySettings(settings);
      refresh();
    }

    return [
      _tile(
        icon: Icons.dark_mode_outlined,
        title: context.t('主题模式'),
        subtitle: _themeLabel(_settings.themeMode),
        onTap: () async {
          await _pickThemeMode();
          refresh();
        },
      ),
      _tile(
        icon: Icons.format_size,
        title: context.t('全局字体大小'),
        subtitle: '${(_settings.fontScale * 100).round()}%',
        child: _compactSlider(
          value: _settings.fontScale,
          min: 0.85,
          max: 1.3,
          divisions: 45,
          onChanged: (value) {
            preview(_settings.copyWith(fontScale: value));
          },
          onChangeEnd: (value) {
            apply(_settings.copyWith(fontScale: value));
          },
        ),
      ),
      _colorTile(
        title: context.t('主界面字体颜色'),
        value: _settings.interfaceTextColor,
        onTap: () async {
          await _pickColor(
            title: context.t('主界面字体颜色'),
            value: _settings.interfaceTextColor,
            onChanged: (value) => apply(
              _settings.copyWith(
                interfaceTextColor: value,
                clearInterfaceTextColor: value == null,
              ),
            ),
          );
          refresh();
        },
      ),
      _colorTile(
        title: context.t('聊天字体颜色'),
        value: _settings.chatTextColor,
        onTap: () async {
          await _pickColor(
            title: context.t('聊天字体颜色'),
            value: _settings.chatTextColor,
            onChanged: (value) => apply(
              _settings.copyWith(
                chatTextColor: value,
                clearChatTextColor: value == null,
              ),
            ),
          );
          refresh();
        },
      ),
      _tile(
        icon: Icons.image_outlined,
        title: context.t('主页和设置背景'),
        subtitle: _settings.globalBackgroundImage.isEmpty
            ? context.t('未设置')
            : context.t('已设置'),
        onTap: () async {
          await _pickBackground();
          refresh();
        },
      ),
      _tile(
        icon: Icons.opacity,
        title: context.t('界面背景透明度'),
        subtitle: '${(_settings.globalBackgroundOpacity * 100).round()}%',
        child: _compactSlider(
          value: _settings.globalBackgroundOpacity.clamp(0, 1).toDouble(),
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: (value) {
            preview(_settings.copyWith(globalBackgroundOpacity: value));
          },
          onChangeEnd: (value) {
            apply(_settings.copyWith(globalBackgroundOpacity: value));
          },
        ),
      ),
      _tile(
        icon: Icons.blur_on,
        title: context.t('界面背景模糊度'),
        subtitle: _settings.globalBackgroundBlur.toStringAsFixed(0),
        child: _compactSlider(
          value: _settings.globalBackgroundBlur.clamp(0, 12),
          min: 0,
          max: 12,
          divisions: 12,
          onChanged: (value) {
            preview(_settings.copyWith(globalBackgroundBlur: value));
          },
          onChangeEnd: (value) {
            apply(_settings.copyWith(globalBackgroundBlur: value));
          },
        ),
      ),
      _tile(
        icon: Icons.space_bar,
        title: context.t('底部导航栏透明度'),
        subtitle: '${(_settings.navigationBarOpacity * 100).round()}%',
        child: _compactSlider(
          value: _settings.navigationBarOpacity.clamp(0, 1).toDouble(),
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: (value) {
            apply(_settings.copyWith(navigationBarOpacity: value));
          },
          onChangeEnd: (value) {
            apply(_settings.copyWith(navigationBarOpacity: value));
          },
        ),
      ),
      _tile(
        icon: Icons.clear,
        title: context.t('清空界面背景'),
        subtitle: context.t('只删除背景引用，不影响图片文件'),
        onTap: _settings.globalBackgroundImage.isEmpty
            ? null
            : () => apply(
                _settings.copyWith(
                  globalBackgroundImage: '',
                  globalBackgroundRegion: ImageCropRegion.full,
                ),
              ),
      ),
    ];
  }

  List<Widget> _summarySettingsChildren(VoidCallback refresh) {
    void refreshLater(Future<void> future) {
      unawaited(future.then((_) => refresh()));
    }

    return [
      _summaryItemsSection(
        title: '角色聊天总结',
        useCustom: _settings.useCustomChatSummaryItems,
        items: _settings.customChatSummaryItems,
        onToggle: (value) {
          _setCustomChatSummaryEnabled(value);
          refresh();
        },
        onAdd: () => refreshLater(_addSummaryItem(isTheater: false)),
        onRestore: () {
          _restoreSummaryItems(isTheater: false);
          refresh();
        },
        onEdit: (index) =>
            refreshLater(_editSummaryItem(index: index, isTheater: false)),
        onDelete: (index) {
          _deleteSummaryItem(index: index, isTheater: false);
          refresh();
        },
      ),
      _summaryItemsSection(
        title: '群聊总结',
        useCustom: _settings.useCustomTheaterSummaryItems,
        items: _settings.customTheaterSummaryItems,
        onToggle: (value) {
          _setCustomTheaterSummaryEnabled(value);
          refresh();
        },
        onAdd: () => refreshLater(_addSummaryItem(isTheater: true)),
        onRestore: () {
          _restoreSummaryItems(isTheater: true);
          refresh();
        },
        onEdit: (index) =>
            refreshLater(_editSummaryItem(index: index, isTheater: true)),
        onDelete: (index) {
          _deleteSummaryItem(index: index, isTheater: true);
          refresh();
        },
      ),
    ];
  }

  Widget _summaryItemsSection({
    required String title,
    required bool useCustom,
    required List<String> items,
    required ValueChanged<bool> onToggle,
    required VoidCallback onAdd,
    required VoidCallback onRestore,
    required ValueChanged<int> onEdit,
    required ValueChanged<int> onDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          secondary: const Icon(Icons.summarize_outlined),
          title: Text(context.t(title)),
          subtitle: Text(
            useCustom ? context.t('使用自定义总结项目，最多 20 个') : context.t('使用默认总结结构'),
          ),
          value: useCustom,
          onChanged: onToggle,
        ),
        if (useCustom) ...[
          for (var i = 0; i < items.length; i++)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.only(left: 20, right: 8),
              leading: Text('${i + 1}.'),
              title: Text(items[i]),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.t('编辑'),
                    onPressed: () => onEdit(i),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: context.t('删除'),
                    onPressed: () => onDelete(i),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(context.t('添加项目')),
                ),
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore),
                  label: Text(context.t('恢复默认')),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? child,
    VoidCallback? onTap,
  }) {
    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 4,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: child == null && onTap != null
          ? const Icon(Icons.chevron_right)
          : null,
      onTap: onTap,
    );
    return Column(
      children: [
        tile,
        if (child != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 0, 16, 2),
            child: child,
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _colorTile({
    required String title,
    required int? value,
    required VoidCallback onTap,
  }) {
    return _tile(
      icon: Icons.palette_outlined,
      title: title,
      subtitle: value == null
          ? context.t('默认')
          : '#${value.toRadixString(16).substring(2).toUpperCase()}',
      onTap: onTap,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: value == null
                ? Theme.of(context).colorScheme.onSurface
                : Color(value),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => context.t('白天'),
      ThemeMode.dark => context.t('黑夜'),
      ThemeMode.system => context.t('跟随系统'),
    };
  }
}
