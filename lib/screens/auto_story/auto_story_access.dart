import 'package:flutter/material.dart';
import '../../models/auto_story.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/privacy_password_prompt.dart';

Future<bool> autoStoryNeedsUnlock(
  LocalStorageService storage,
  AutoStoryHeader header,
) async {
  // A list tile can outlive a source lock/deletion. Never authorize its cache.
  final fresh = (await storage.autoStories.listStories())
      .where((story) => story.id == header.id)
      .firstOrNull;
  if (fresh == null) return true;
  if (header.privacyRequired || fresh.privacyRequired) return true;
  final sources = fresh.actors
      .map((a) => a.sourceId)
      .whereType<String>()
      .toSet();
  return (await storage.loadCharacters()).any(
    (c) => sources.contains(c.id) && c.isLocked,
  );
}

Future<bool> unlockAutoStory(
  BuildContext context,
  LocalStorageService storage,
  AutoStoryHeader header,
) async {
  if (!await autoStoryNeedsUnlock(storage, header)) return true;
  final settings = await storage.loadSettings();
  if (!context.mounted) return false;
  return verifyPrivacyPassword(
    context: context,
    settings: settings,
    storage: storage,
    title: context.t('解锁故事'),
  );
}
