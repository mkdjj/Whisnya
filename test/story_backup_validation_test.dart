import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/story/story_backup_validation.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('story_backup_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<void> write(String path, Object value) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
  }

  test('old backups without story files or IDs remain valid', () async {
    await write('chats/old.json', {
      'messages': [
        {'role': 'user', 'content': 'old'},
      ],
    });
    expect(await validateStoryBackup(root), isEmpty);
  });
  test(
    'present duplicate message and candidate identities reject backup',
    () async {
      await write('chats/s.json', {
        'messages': [
          {'id': 'x'},
          {'id': 'x'},
        ],
      });
      await expectLater(validateStoryBackup(root), throwsFormatException);
      await write('chats/s.json', {
        'messages': [
          {
            'id': 'x',
            'variants': [
              {'id': 'v'},
              {'id': 'v'},
            ],
          },
        ],
      });
      await expectLater(validateStoryBackup(root), throwsFormatException);
    },
  );
  test(
    'checkpoint hash rejects changed body but accepts deleted source',
    () async {
      final payload = <String, dynamic>{
        'schemaVersion': 1,
        'id': 'cp',
        'title': 'node',
        'characterId': 'c',
        'characterNameSnapshot': 'Role',
        'sourceSessionId': 'deleted',
        'sourceSessionTitle': 'old',
        'branchRootSessionId': 'deleted',
        'anchor': {
          'sessionId': 'deleted',
          'messageId': 'm',
          'variantId': null,
          'prefixDigest': 'a' * 64,
        },
        'messages': [
          {
            'id': 'm',
            'role': 'user',
            'content': 'hello',
            'sourceVariantId': '',
          },
        ],
        'initialState': null,
        'contextPolicy': 'isolated',
        'requiresUnlock': false,
      };
      payload['contentHash'] = checkpointContentHash(payload);
      await write('story/checkpoints/index.json', [
        {'id': 'cp', 'characterId': 'c', 'requiresUnlock': false},
      ]);
      await write('story/checkpoints/cp.json', payload);
      expect(await validateStoryBackup(root), isEmpty);
      (payload['messages'] as List<dynamic>).add({
        'id': 'tampered',
        'content': 'new',
      });
      await write('story/checkpoints/cp.json', payload);
      await expectLater(validateStoryBackup(root), throwsFormatException);
    },
  );
}
