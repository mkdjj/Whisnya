import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/local_storage_service.dart';
import '../utils/app_i18n.dart';
import '../utils/page_layout.dart';
import '../utils/snack.dart';
import 'image_crop_screen.dart';

class UserProfileEditScreen extends StatefulWidget {
  const UserProfileEditScreen({
    required this.storage,
    required this.profile,
    required this.title,
    super.key,
  });

  final LocalStorageService storage;
  final UserProfile profile;
  final String title;

  @override
  State<UserProfileEditScreen> createState() => _UserProfileEditScreenState();
}

class _UserProfileEditScreenState extends State<UserProfileEditScreen> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _description = TextEditingController(
    text: widget.profile.description,
  );
  late final _personality = TextEditingController(
    text: widget.profile.personality,
  );
  late final _speakingStyle = TextEditingController(
    text: widget.profile.speakingStyle,
  );
  late final _extraPrompt = TextEditingController(
    text: widget.profile.extraPrompt,
  );
  late String _avatar = widget.profile.avatar;
  var _isPicking = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _personality.dispose();
    _speakingStyle.dispose();
    _extraPrompt.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      var sourcePath = picked.path;
      if (sourcePath == null && picked.bytes != null) {
        sourcePath = (await widget.storage.saveTemporaryImage(
          picked.bytes!,
        )).path;
      }
      if (!mounted || sourcePath == null) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(
            imagePath: sourcePath!,
            title: context.t('裁剪头像'),
            aspectRatio: 1,
            outputWidth: 512,
            outputHeight: 512,
          ),
        ),
      );
      if (cropped == null) return;
      final path = await widget.storage.saveMediaImage(
        folder: 'user_avatars',
        characterId: 'user_${DateTime.now().microsecondsSinceEpoch}',
        bytes: cropped,
      );
      if (mounted) setState(() => _avatar = path);
    } catch (error) {
      if (mounted) context.showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _save() {
    Navigator.of(context).pop(
      UserProfile(
        name: _name.text.trim().isEmpty ? '用户' : _name.text.trim(),
        avatar: _avatar,
        description: _description.text.trim(),
        personality: _personality.text.trim(),
        speakingStyle: _speakingStyle.text.trim(),
        extraPrompt: _extraPrompt.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarFile = File(_avatar);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(widget.title)),
        actions: [
          IconButton(
            tooltip: context.t('保存'),
            onPressed: _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: AdaptivePage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Center(
              child: CircleAvatar(
                radius: 44,
                foregroundImage: _avatar.isNotEmpty && avatarFile.existsSync()
                    ? FileImage(avatarFile)
                    : null,
                child: const Icon(Icons.person_outline, size: 36),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isPicking ? null : _pickAvatar,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(context.t('更换头像')),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const ValueKey('user-profile-clear-avatar'),
                  onPressed: _avatar.isEmpty
                      ? null
                      : () => setState(() => _avatar = ''),
                  icon: const Icon(Icons.clear),
                  label: Text(context.t('清除头像')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('user-profile-name'),
              controller: _name,
              decoration: InputDecoration(labelText: context.t('用户昵称')),
              textInputAction: TextInputAction.next,
            ),
            _field(_description, '身份简介', 'user-profile-description'),
            _field(_personality, '性格', 'user-profile-personality'),
            _field(_speakingStyle, '说话方式', 'user-profile-speaking-style'),
            _field(_extraPrompt, '补充设定', 'user-profile-extra-prompt'),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(labelText: context.t(label)),
      ),
    );
  }
}
