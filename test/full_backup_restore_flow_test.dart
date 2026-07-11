import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/theater.dart';
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
      final sourceDirectory = await Directory.systemTemp.createTemp(
        'backup-src-',
      );
      final targetDirectory = await Directory.systemTemp.createTemp(
        'backup-dst-',
      );
      addTearDown(() => sourceDirectory.delete(recursive: true));
      addTearDown(() => targetDirectory.delete(recursive: true));
      final source = LocalStorageService(appDataDirectory: sourceDirectory);
      final target = LocalStorageService(appDataDirectory: targetDirectory);
      final now = DateTime(2026);

      await source.saveSettings(const AppSettings(languageCode: 'en'));
      final avatar = await source.saveMediaImage(
        folder: 'avatars',
        characterId: 'c',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      final character = AppCharacter.fromJson({
        'id': 'c',
        'name': '角色',
        'avatar': avatar,
        'defaultEndpointId': 'custom-endpoint',
      });
      await source.saveCharacter(character);
      await source.saveChat('c', [
        ChatMessage(role: 'user', content: '你好', time: now),
      ]);
      final novel = await source.importNovelText(
        title: '小说',
        content: '第一章\n正文',
      );
      await source.saveNovelChat(novel.id, [
        ChatMessage(role: 'assistant', content: '回复', time: now),
      ]);
      final theater = TheaterSession.fromJson({'id': 't', 'title': '群聊'});
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

      expect((await target.loadSettings()).languageCode, 'en');
      final restoredCharacter = (await target.loadCharacters()).single;
      expect(restoredCharacter.name, '角色');
      expect(restoredCharacter.defaultEndpointId, 'custom-endpoint');
      expect(await File(restoredCharacter.avatar).readAsBytes(), [1, 2, 3, 4]);
      expect((await target.loadChat('c')).messages.single.content, '你好');
      final restoredNovel = (await target.loadNovels()).single;
      expect(await target.loadNovelText(restoredNovel), contains('正文'));
      expect(
        (await target.loadNovelChat(restoredNovel.id)).messages.single.content,
        '回复',
      );
      expect((await target.loadTheaterSessions()).single.title, '群聊');
      expect((await target.loadTheaterMessages('t')).single.content, '开场');
    },
  );
}
