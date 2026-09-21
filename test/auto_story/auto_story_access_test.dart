import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/screens/auto_story/auto_story_access.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'auto_story_model_test.dart' show storyFixture;

void main() {
  test(
    'cached public header cannot authorize a story locked since the list opened',
    () async {
      final root = await Directory.systemTemp.createTemp('story-access-');
      addTearDown(() => root.delete(recursive: true));
      final storage = LocalStorageService(appDataDirectory: root);
      final original = await storage.autoStories.createStory(storyFixture());
      final stale = AutoStoryHeader(original);
      await storage.autoStories.mutateStory(
        original.id,
        (story) => story.copyWith(privacyRequired: true),
      );
      expect(stale.privacyRequired, isFalse);
      expect(await autoStoryNeedsUnlock(storage, stale), isTrue);
    },
  );
}
