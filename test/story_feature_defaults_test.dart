import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/memento.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/memento_service.dart';
import 'package:whisnya/services/share_card_service.dart';
import 'package:whisnya/services/story/story_checkpoint_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secure,
          (call) async => call.method == 'read' ? null : true,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
  });
  test(
    'importing a real legacy archive resets new settings off without inventing voices or snapshots',
    () async {
      final root = await Directory.systemTemp.createTemp('story-defaults-');
      addTearDown(() => root.delete(recursive: true));
      final oldDirectory = Directory('${root.path}/old/app_data');
      final source = LocalStorageService(appDataDirectory: oldDirectory);
      final target = LocalStorageService(
        appDataDirectory: Directory('${root.path}/target/app_data'),
      );
      await source.jsonStore.write(File('${oldDirectory.path}/settings.json'), {
        'languageCode': 'en',
      });
      await source.jsonStore.write(
        File('${oldDirectory.path}/characters.json'),
        [
          {'id': 'legacy', 'name': 'Old role'},
        ],
      );
      await target.saveSettings(
        const AppSettings(
          showCharacterStateCard: true,
          autoUpdateCharacterState: true,
          useCharacterStateInPrompt: true,
          enableCharacterSpeech: true,
          autoReadAssistantReplies: true,
          allowNetworkSpeechVoices: true,
        ),
      );
      await target.importAllData(await source.exportAllData());
      final settings = await target.loadSettings();
      expect(settings.languageCode, 'en');
      expect(settings.showCharacterStateCard, false);
      expect(settings.autoUpdateCharacterState, false);
      expect(settings.useCharacterStateInPrompt, false);
      expect(settings.enableCharacterSpeech, false);
      expect(settings.autoReadAssistantReplies, false);
      expect(settings.allowNetworkSpeechVoices, false);
      expect((await target.loadCharacters()).single.voiceProfiles, isEmpty);
      expect(await StoryCheckpointService(target).list(), isEmpty);
      expect(
        await MementoService(
          storage: target,
        ).queryMementos(const MementoQuery()),
        isEmpty,
      );
    },
  );

  test(
    'fresh share plans omit private channels and display identifiers by default',
    () {
      final time = DateTime.utc(2026);
      final messages = [
        ChatMessage(
          id: 'm',
          role: 'user',
          content: 'Public dialogue',
          innerVoice: 'PRIVATE_INNER',
          reasoningContent: 'PRIVATE_REASONING',
          time: time,
        ),
      ];
      final snapshot = MementoSnapshot(
        id: 'moment',
        createdAt: time,
        updatedAt: time,
        idempotencyKey: 'key',
        title: 'Title',
        characterId: 'c',
        characterNameSnapshot: 'Role',
        sessionTitleSnapshot: 'Chat',
        sourceSessionId: 's',
        entries: [
          MementoEntry.capture(
            sessionId: 's',
            messages: messages,
            index: 0,
            speakerName: 'PRIVATE_USERNAME',
            avatarAssetId: 'private.png',
          ),
        ],
      );
      final plan = ShareCardPlan.prepare(snapshot, const ShareCardOptions());
      final block = plan.pages.single.blocks.single;
      expect(block.text, 'Public dialogue');
      expect(block.speaker, isNot('PRIVATE_USERNAME'));
      expect(block.avatarAssetId, isNull);
      expect(block.time, isNull);
      expect(
        plan.pages.expand((page) => page.blocks).map((b) => b.text).join(),
        isNot(contains('PRIVATE_')),
      );
    },
  );
}
