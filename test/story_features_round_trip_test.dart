import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/character_state.dart';
import 'package:whisnya/models/character_voice_profile.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
import 'package:whisnya/models/memento.dart';
import 'package:whisnya/models/message_anchor.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/memento_service.dart';
import 'package:whisnya/services/story/character_state_service.dart';
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
    'real full backup restores branches, orphan checkpoint, locks, protected mementos and platform voices',
    () async {
      final root = await Directory.systemTemp.createTemp('story-round-trip-');
      addTearDown(() => root.delete(recursive: true));
      final source = LocalStorageService(
        appDataDirectory: Directory('${root.path}/source/app_data'),
      );
      final targetDirectory = Directory('${root.path}/target/app_data');
      final target = LocalStorageService(appDataDirectory: targetDirectory);
      await source.saveSettings(const AppSettings());
      final png = image.encodePng(image.Image(width: 2, height: 2));
      final avatar = await source.saveMediaImage(
        folder: 'avatars',
        characterId: 'c',
        bytes: png,
      );
      final character =
          AppCharacter.fromJson({
            'id': 'c',
            'name': 'Role',
            'avatar': avatar,
          }).copyWith(
            voiceProfiles: {
              'android': const CharacterVoiceProfile(
                engineId: 'engine.local',
                voiceName: 'Android voice',
                locale: 'zh-CN',
                rate: .4,
              ),
              'windows': const CharacterVoiceProfile(
                voiceName: 'Windows voice',
                locale: 'en-US',
                identifier: 'windows-local-id',
                pitch: 1.2,
              ),
            },
          );
      await source.saveCharacter(character);
      final session = await source.createChatSession('c', title: 'Original');
      final messages = [
        ChatMessage(
          id: 'user-one',
          role: 'user',
          content: 'Stay?',
          time: DateTime.utc(2026),
        ),
        ChatMessage(
          id: 'reply-one',
          role: 'assistant',
          content: 'Stay',
          time: DateTime.utc(2026),
          variants: [
            ChatReplyVariant(
              id: 'variant-a',
              content: 'I will stay.',
              innerVoice: 'relief',
              reasoningContent: 'PRIVATE_REASONING',
              time: DateTime.utc(2026),
            ),
            ChatReplyVariant(
              id: 'variant-b',
              content: 'I will leave.',
              innerVoice: 'worry',
              time: DateTime.utc(2026),
            ),
          ],
        ),
      ];
      await source.saveChatBySession(session, messages);
      final states = CharacterStateService(source);
      await states.editState(
        session.id,
        'c',
        messages,
        const StateEdit(
          expectedRevision: 0,
          values: {'location': 'Living room'},
          locks: {'location': true, 'emotion': true},
        ),
      );
      final state = await states.loadCurrentState(session.id, 'c', messages);
      final checkpoints = StoryCheckpointService(
        source,
        authorize: (_, _) async => true,
      );
      final checkpoint = await checkpoints.create(
        source: session,
        character: character,
        anchor: MessageAnchor.capture(session.id, messages, 1),
        title: 'Decision',
        initialState: state.toJson(),
      );
      final branchA = await checkpoints.fork(checkpoint.id, title: 'Route A');
      final branchB = await checkpoints.fork(checkpoint.id, title: 'Route B');

      final orphanCharacter = AppCharacter.fromJson({
        'id': 'orphan',
        'name': 'Deleted role',
        'isLocked': true,
      });
      await source.saveCharacter(orphanCharacter);
      final orphanSession = await source.createChatSession('orphan');
      final orphanMessages = [
        ChatMessage(
          id: 'orphan-message',
          role: 'assistant',
          content: 'Remember me.',
          time: DateTime.utc(2026),
        ),
      ];
      await source.saveChatBySession(orphanSession, orphanMessages);
      final orphan = await checkpoints.create(
        source: orphanSession,
        character: orphanCharacter,
        anchor: MessageAnchor.capture(orphanSession.id, orphanMessages, 0),
        title: 'Preserved',
      );
      await source.deleteCharacter('orphan');
      expect(
        (await checkpoints.load(orphan.id)).messages.single.content,
        'Remember me.',
      );

      final collection = MementoService(
        storage: source,
        authorize: (_, _) async => true,
      );
      final asset = await collection.copyRecognizedAvatar(
        avatar,
        recognizedPaths: {avatar},
      );
      expect(asset, isNotNull);
      Future<MementoSnapshot> saveMoment(String key, bool locked) =>
          collection.createMemento(
            MementoDraft(
              idempotencyKey: key,
              title: key,
              characterId: 'c',
              characterNameSnapshot: 'Role',
              sessionTitleSnapshot: 'Original',
              sourceSessionId: session.id,
              requiresUnlock: locked,
              tags: ['decision'],
              entries: [
                MementoEntry.capture(
                  sessionId: session.id,
                  messages: messages,
                  index: 1,
                  speakerName: 'Role',
                  avatarAssetId: asset,
                ),
              ],
            ),
          );
      final publicMoment = await saveMoment('Public memory', false);
      final privateMoment = await saveMoment('Private memory', true);
      await source.saveChatBySession(session, [
        messages.first,
        messages.last.copyWith(selectedVariantIndex: 1),
      ]);

      final archive = await source.exportAllData();
      await target.importAllData(archive);
      // New service instances force assertions through the restored disk dataset.
      final reopened = LocalStorageService(appDataDirectory: targetDirectory);
      final restoredCharacters = await reopened.loadCharacters();
      expect(restoredCharacters.map((c) => c.id), ['c']);
      final restoredCharacter = restoredCharacters.single;
      expect(
        restoredCharacter.voiceProfiles['android']!.toJson(),
        character.voiceProfiles['android']!.toJson(),
      );
      expect(
        restoredCharacter.voiceProfiles['windows']!.toJson(),
        character.voiceProfiles['windows']!.toJson(),
      );
      final androidChanged = restoredCharacter.copyWith(
        voiceProfiles: {
          ...restoredCharacter.voiceProfiles,
          'android': restoredCharacter.voiceProfiles['android']!.copyWith(
            rate: .8,
          ),
        },
      );
      expect(androidChanged.voiceProfiles['windows']!.rate, .5);
      expect(restoredCharacter.voiceProfiles['android']!.rate, .4);
      expect(await File(restoredCharacter.avatar).readAsBytes(), png);
      expect(restoredCharacter.avatar, startsWith(targetDirectory.path));

      final restoredSessions = await reopened.loadChatSessions('c');
      expect(restoredSessions.map((s) => s.id).toSet(), {
        session.id,
        branchA.id,
        branchB.id,
      });
      final restoredCheckpoints = StoryCheckpointService(
        reopened,
        authorize: (_, _) async => true,
      );
      final restoredCheckpoint = await restoredCheckpoints.load(checkpoint.id);
      expect(restoredCheckpoint.contentHash, checkpoint.contentHash);
      expect(restoredCheckpoint.toJson(), checkpoint.toJson());
      expect(
        (await restoredCheckpoints.load(orphan.id)).contentHash,
        orphan.contentHash,
      );
      await expectLater(
        restoredCheckpoints.fork(orphan.id, title: 'Not allowed'),
        throwsStateError,
      );
      await expectLater(
        StoryCheckpointService(reopened).load(orphan.id),
        throwsStateError,
      );
      for (final id in [branchA.id, branchB.id]) {
        final branch = restoredSessions.singleWhere((s) => s.id == id);
        final branchMessages = await reopened.loadChatBySession(branch);
        expect(branchMessages.last.effectiveContent, 'I will stay.');
        expect(branch.sourceCheckpointId, checkpoint.id);
        expect(branch.allowSharedCharacterMemories, false);
        final branchState = await CharacterStateService(
          reopened,
        ).loadCurrentState(id, 'c', branchMessages);
        expect(branchState.values['location'], 'Living room');
        expect(branchState.locks['location'], true);
        expect(branchState.locks['emotion'], true);
      }
      final originalState = await CharacterStateService(
        reopened,
      ).loadCurrentState(session.id, 'c', messages);
      expect(originalState.values['location'], 'Living room');
      expect(originalState.locks['emotion'], true);

      final restoredCollection = MementoService(
        storage: reopened,
        authorize: (_, _) async => true,
      );
      expect(
        await restoredCollection.queryMementos(const MementoQuery()),
        hasLength(2),
      );
      expect(
        (await restoredCollection.loadMemento(publicMoment.id)).toJson(),
        publicMoment.toJson(),
      );
      final restoredPrivate = await restoredCollection.loadMemento(
        privateMoment.id,
      );
      expect(restoredPrivate.toJson(), privateMoment.toJson());
      expect(restoredPrivate.requiresUnlock, true);
      expect(restoredPrivate.entries.single.sourceVariantId, 'variant-a');
      expect(restoredPrivate.entries.single.contentSnapshot, 'I will stay.');
      expect(restoredPrivate.entries.single.innerVoiceSnapshot, 'relief');
      expect(
        await (await restoredCollection.paths).media(asset!).readAsBytes(),
        png,
      );
      await expectLater(
        MementoService(storage: reopened).loadMemento(privateMoment.id),
        throwsStateError,
      );
      final rawSnapshot = await (await restoredCollection.paths)
          .item(privateMoment.id)
          .readAsString();
      expect(rawSnapshot, isNot(contains('PRIVATE_REASONING')));
      final settings = await reopened.loadSettings();
      expect(settings.showCharacterStateCard, false);
      expect(settings.autoUpdateCharacterState, false);
      expect(settings.useCharacterStateInPrompt, false);
      expect(settings.enableCharacterSpeech, false);
      expect(settings.autoReadAssistantReplies, false);
      expect(settings.allowNetworkSpeechVoices, false);
    },
  );
}
