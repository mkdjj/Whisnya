import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
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
      });
      await source.saveCharacter(character);
      await source.saveChat('c', [
        ChatMessage(role: 'user', content: '你好', time: now),
      ]);
      await source.importNovelText(title: '小说', content: '第一章\n正文');
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
      expect(await File(restoredCharacter.avatar).readAsBytes(), [1, 2, 3, 4]);
      expect((await target.loadChat('c')).single.content, '你好');
      final restoredNovel = (await target.loadNovels()).single;
      expect(await target.loadNovelText(restoredNovel), contains('正文'));
      final restoredTheater = (await target.loadTheaterSessions()).single;
      expect(restoredTheater.title, '群聊');
      expect((await target.loadTheaterMessages('t')).single.content, '开场');
    },
  );

  test('backup excludes recovery artifacts and temporary media', () async {
    final root = await Directory.systemTemp.createTemp('backup-filter-');
    addTearDown(() => root.delete(recursive: true));
    final appData = Directory('${root.path}${Platform.pathSeparator}app_data');
    final storage = LocalStorageService(appDataDirectory: appData);
    await storage.saveSettings(const AppSettings());

    const secret = 'sk-recovery-copy-must-not-export';
    for (final name in const [
      'api_config.json.broken_1',
      'api_config.json.bak',
      'api_config.json.tmp',
      'api_config.json.corrupt.1',
    ]) {
      await File(
        '${appData.path}${Platform.pathSeparator}$name',
      ).writeAsString(secret);
    }
    final temporary = File(
      '${appData.path}${Platform.pathSeparator}media'
      '${Platform.pathSeparator}temp${Platform.pathSeparator}picked.png',
    );
    await temporary.parent.create(recursive: true);
    await temporary.writeAsString(secret);

    final archive = ZipDecoder().decodeBytes(await storage.exportAllData());
    final names = archive.files.map((file) => file.name).toList();
    final text = archive.files
        .where((file) => file.isFile)
        .map(
          (file) =>
              utf8.decode(file.content as List<int>, allowMalformed: true),
        )
        .join();

    for (final name in const [
      'api_config.json.broken_1',
      'api_config.json.bak',
      'api_config.json.tmp',
      'api_config.json.corrupt.1',
      'media/temp/picked.png',
    ]) {
      expect(names, isNot(contains(name)));
    }
    expect(text, isNot(contains(secret)));
  });
}
