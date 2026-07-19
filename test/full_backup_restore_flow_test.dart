import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          (call) async => call.method == 'read' ? null : true,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test(
    'full backup restores settings, chats, novel, theater, and media',
    () async {
      final sourceRoot = await Directory.systemTemp.createTemp('backup-src-');
      final targetRoot = await Directory.systemTemp.createTemp('backup-dst-');
      final sourceDirectory = Directory(
        '${sourceRoot.path}${Platform.pathSeparator}app_data',
      );
      final targetDirectory = Directory(
        '${targetRoot.path}${Platform.pathSeparator}app_data',
      );
      addTearDown(() => sourceRoot.delete(recursive: true));
      addTearDown(() => targetRoot.delete(recursive: true));
      final source = LocalStorageService(appDataDirectory: sourceDirectory);
      final target = LocalStorageService(appDataDirectory: targetDirectory);
      final now = DateTime(2026);
      final skinBytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 32, height: 32, numChannels: 4)),
      );
      final skinDirectory = Directory(
        '${sourceDirectory.path}${Platform.pathSeparator}media'
        '${Platform.pathSeparator}bubble_skins${Platform.pathSeparator}skin',
      );
      await skinDirectory.create(recursive: true);
      final skinFile = File(
        '${skinDirectory.path}${Platform.pathSeparator}role.png',
      );
      await skinFile.writeAsBytes(skinBytes);
      final skin = ChatBubbleImageSkin(
        imagePath: skinFile.path,
        imageWidth: 32,
        imageHeight: 32,
      );
      await source.saveChatBubblePresets(
        ChatBubblePresetSettings(
          presets: [
            ChatBubblePreset(
              id: 'skin',
              name: '皮肤',
              appearance: ChatBubbleAppearance(imageSkin: skin),
            ),
          ],
        ),
      );

      final avatar = await source.saveMediaImage(
        folder: 'avatars',
        characterId: 'c',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      final userAvatar = await source.saveMediaImage(
        folder: 'user_avatars',
        characterId: 'global_user',
        bytes: Uint8List.fromList([5, 6, 7, 8]),
      );
      await source.saveSettings(
        AppSettings(
          languageCode: 'en',
          userProfile: UserProfile(name: '小明', avatar: userAvatar),
        ),
      );
      final character = AppCharacter.fromJson({
        'id': 'c',
        'name': '角色',
        'avatar': avatar,
        'defaultEndpointId': 'custom-endpoint',
        'roleBubblePresetId': 'skin',
      });
      await source.saveCharacter(character);
      await source.saveChat('c', [
        ChatMessage(role: 'user', content: '你好', time: now),
      ]);
      await source.importNovelText(title: '小说', content: '第一章\n正文');
      final theater = TheaterSession.fromJson({
        'id': 't',
        'title': '群聊',
        'userBubblePresetId': 'skin',
      });
      await source.saveTheaterSession(theater);
      await source.saveTheaterMessages('t', [
        TheaterMessage(
          id: 'm',
          sessionId: 't',
          round: 1,
          speakerType: TheaterSpeakerType.user,
          speakerId: 'user',
          speakerName: '用户',
          content: '开场',
          time: now,
        ),
      ]);

      final archive = await source.exportAllData();
      await target.importAllData(archive);

      final restoredSettings = await target.loadSettings();
      expect(restoredSettings.languageCode, 'en');
      expect(restoredSettings.userProfile.name, '小明');
      expect(
        restoredSettings.userProfile.avatar,
        startsWith(targetDirectory.path),
      );
      expect(await File(restoredSettings.userProfile.avatar).readAsBytes(), [
        5,
        6,
        7,
        8,
      ]);
      final restoredCharacter = (await target.loadCharacters()).single;
      expect(restoredCharacter.name, '角色');
      expect(restoredCharacter.defaultEndpointId, 'custom-endpoint');
      expect(restoredCharacter.roleBubblePresetId, 'skin');
      expect(await File(restoredCharacter.avatar).readAsBytes(), [1, 2, 3, 4]);
      expect((await target.loadChat('c')).single.content, '你好');
      final restoredNovel = (await target.loadNovels()).single;
      expect(await target.loadNovelText(restoredNovel), contains('正文'));
      final restoredTheater = (await target.loadTheaterSessions()).single;
      expect(restoredTheater.title, '群聊');
      expect(restoredTheater.userBubblePresetId, 'skin');
      expect((await target.loadTheaterMessages('t')).single.content, '开场');
      final restoredPresets = await target.loadChatBubblePresets();
      final restoredSkin = restoredPresets.presets.single.appearance.imageSkin!;
      expect(restoredPresets.presets.single.id, 'skin');
      expect(restoredSkin.imagePath, startsWith(targetDirectory.path));
      expect(await File(restoredSkin.imagePath).readAsBytes(), skinBytes);
    },
  );
}
