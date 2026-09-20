import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  for (final invalid in ['{broken', '{"wrong":"shape"}']) {
    test(
      'unreadable character file recovers mapped characters: $invalid',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'character_corrupt_',
        );
        addTearDown(() => root.delete(recursive: true));
        final storage = LocalStorageService(appDataDirectory: root);
        await storage.ensureReady();
        await File('${root.path}/characters.json').writeAsString(invalid);
        await File('${root.path}/chat_sessions.json').writeAsString(
          jsonEncode([
            {'id': 'session_a', 'characterId': 'character_a'},
            {'id': 'session_b', 'characterId': 'character_a'},
          ]),
        );
        expect((await storage.loadCharacters()).single.id, 'character_a');
        final backups = await root
            .list()
            .where((file) => file.path.contains('characters.json.broken_'))
            .toList();
        expect(backups, hasLength(1));
        expect(await File(backups.single.path).readAsString(), invalid);
        expect(storage.takeRecoveryMessages(), isNotEmpty);
        expect((await storage.loadCharacters()).single.id, 'character_a');
      },
    );
  }
}
