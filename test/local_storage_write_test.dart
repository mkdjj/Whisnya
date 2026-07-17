import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';

void main() {
  test('shares one app data directory preparation future', () async {
    final directory = await Directory.systemTemp.createTemp(
      'whisnya_storage_ready_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: directory);

    final first = storage.appDataDirectory;
    final second = storage.appDataDirectory;

    expect(identical(first, second), isTrue);
    expect(await first, same(await second));
  });

  test('normal local storage reads skip recovery inspection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'whisnya_storage_read_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = _TrackingJsonFileStore();
    final storage = LocalStorageService(
      appDataDirectory: directory,
      jsonStore: store,
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}${Platform.pathSeparator}settings.json',
    ).writeAsString('{}');

    await storage.loadSettings();

    expect(store.recoverCalls, 0);
  });

  test(
    'writes chat files compactly while independent files can save together',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'whisnya_storage_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = LocalStorageService(appDataDirectory: directory);
      final message = ChatMessage(
        role: 'user',
        content: 'hello',
        time: DateTime(2026),
      );

      await Future.wait([
        storage.saveChat('a', [message]),
        storage.saveChat('b', [message]),
        storage.saveSettings(const AppSettings()),
      ]);

      final chat = await File(
        '${directory.path}${Platform.pathSeparator}chats'
        '${Platform.pathSeparator}a.json',
      ).readAsString();
      final settings = await File(
        '${directory.path}${Platform.pathSeparator}settings.json',
      ).readAsString();
      expect(chat, isNot(contains('\n')));
      expect(settings, contains('\n'));
      expect((await storage.loadChat('b')).messages.single.content, 'hello');
    },
  );
}

final class _TrackingJsonFileStore extends JsonFileStore {
  var recoverCalls = 0;

  @override
  Future<void> recover(File file) {
    recoverCalls++;
    return super.recover(file);
  }
}
