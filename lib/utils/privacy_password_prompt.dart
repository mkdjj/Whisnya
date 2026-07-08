import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/local_storage_service.dart';
import 'app_i18n.dart';
import 'password_lock.dart';
import 'snack.dart';

Future<bool> verifyPrivacyPassword({
  required BuildContext context,
  required AppSettings settings,
  required LocalStorageService storage,
  required String title,
  Future<void> Function()? onSettingsChanged,
}) async {
  if (!settings.hasPrivacyPassword) {
    context.showSnack('请先到设置里设置隐私密码');
    return false;
  }

  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.t(title)),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: dialogContext.t('隐私密码')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.t('取消')),
        ),
        FilledButton(
          onPressed: () async {
            final password = controller.text;
            final ok = PasswordLock.verify(
              password,
              settings.privacyPasswordSalt,
              settings.privacyPasswordHash,
            );
            if (!ok) {
              dialogContext.showSnack('密码不正确');
              return;
            }
            final migrated = await storage.upgradePrivacyPasswordHashIfNeeded(
              settings,
              password,
            );
            if (migrated != null && onSettingsChanged != null) {
              await onSettingsChanged();
            }
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop(true);
          },
          child: Text(dialogContext.t('确认')),
        ),
      ],
    ),
  );
  controller.dispose();
  return ok == true;
}
