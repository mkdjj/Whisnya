import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/storage/json_file_store.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/services/storage/backup_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secrets = <String, String>{};
  setUp(() {
    secrets.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final key = args['key'] as String;
            if (call.method == 'read') return secrets[key];
            if (call.method == 'write') {
              secrets[key] = args['value'] as String;
            }
            if (call.method == 'delete') secrets.remove(key);
            return null;
          },
        );
  });
  test(
    'schema2 bare-message legacy backup migrates envelope without losing fields',
    () async {
      final folder = await Directory.systemTemp.createTemp('backup_legacy_');
      addTearDown(() => folder.delete(recursive: true));
      final source = await Directory('${folder.path}/source').create();
      await Directory('${source.path}/chats').create();
      await File(
        '${source.path}/backup_manifest.json',
      ).writeAsString('{"format":1,"schemaVersion":2}');
      await File(
        '${source.path}/characters.json',
      ).writeAsString('[{"id":"character_1","name":"旧角色"}]');
      final messages = [
        {'role': 'assistant', 'content': '旧文本', 'futureField': 42},
      ];
      await File(
        '${source.path}/chats/character_1.json',
      ).writeAsString(jsonEncode(messages));
      final zip = File('${folder.path}/input.zip');
      await zipBackupDirectory(source, zip);
      final target = LocalStorageService(
        appDataDirectory: Directory('${folder.path}/target/app_data'),
      );
      await target.importAllDataFromFile(zip);
      expect((await target.loadChat('character_1')).single.content, '旧文本');
      final restored =
          jsonDecode(
                await File(
                  '${(await target.appDataDirectory).path}/chats/character_1.json',
                ).readAsString(),
              )
              as Map;
      expect(restored['messages'], messages);
    },
  );
  test(
    'file backup preserves multi-session channels, memories, worldbooks and unknown fields',
    () async {
      final folder = await Directory.systemTemp.createTemp('backup_roundtrip_');
      addTearDown(() => folder.delete(recursive: true));
      final source = LocalStorageService(
        appDataDirectory: Directory('${folder.path}/src/app_data'),
      );
      final target = LocalStorageService(
        appDataDirectory: Directory('${folder.path}/dst/app_data'),
      );
      final sourceRoot = await source.appDataDirectory;
      final records = <String, Object>{
        'characters.json': [
          {'id': 'c', 'name': '角色'},
        ],
        'chat_sessions.json': [
          {'id': 's1', 'characterId': 'c'},
          {'id': 's2', 'characterId': 'c'},
        ],
        'chats/s1.json': {
          'sessionId': 's1',
          'characterId': 'c',
          'messages': [
            {
              'role': 'assistant',
              'content': '正文',
              'reasoningContent': '接口思考',
              'innerVoice': '心声',
              'variants': [
                {
                  'content': '正文',
                  'reasoningContent': '接口思考',
                  'innerVoice': '心声',
                  'futureField': 42,
                },
              ],
              'selectedVariantIndex': 0,
            },
          ],
        },
        'chats/s2.json': {
          'sessionId': 's2',
          'characterId': 'c',
          'messages': [
            {'role': 'user', 'content': '其他会话'},
          ],
        },
        'worldbooks.json': [
          {'id': 'b', 'name': '世界书'},
        ],
        'worldbook_entries/b.json': [
          {
            'id': 'e',
            'worldBookId': 'b',
            'title': '设定',
            'content': '设定',
            'keywords': ['设定'],
          },
        ],
        'memories/c.json': [
          {
            'id': 'm',
            'characterId': 'c',
            'scope': 'session',
            'sessionId': 's1',
            'title': '记忆',
            'content': '记忆',
          },
        ],
      };
      for (final entry in records.entries) {
        await File(
          '${sourceRoot.path}/${entry.key}',
        ).writeAsString(jsonEncode(entry.value));
      }
      await target.importAllDataFromFile(await source.exportAllDataToFile());
      final targetRoot = await target.appDataDirectory;
      for (final entry in records.entries.where(
        (e) => e.key != 'characters.json',
      )) {
        expect(
          jsonDecode(
            await File('${targetRoot.path}/${entry.key}').readAsString(),
          ),
          entry.value,
        );
      }
    },
  );
  test(
    'failure after imported credential writes restores old secrets and removes new IDs',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'backup_key_failure_',
      );
      addTearDown(() => folder.delete(recursive: true));
      final source = await Directory('${folder.path}/source').create();
      await File(
        '${source.path}/backup_manifest.json',
      ).writeAsString('{"format":1,"schemaVersion":3,"includesApiKeys":true}');
      await File('${source.path}/api_config.json').writeAsString(
        '{"endpoints":[{"id":"b","apiKey":"imported-secret","baseUrl":"https://b.example","model":"b"}]}',
      );
      final zip = File('${folder.path}/input.zip');
      await zipBackupDirectory(source, zip);
      final target = LocalStorageService(
        appDataDirectory: Directory('${folder.path}/target/app_data'),
      );
      await target.saveApiConfig(
        ApiConfig.fromJson({
          'endpoints': [
            {
              'id': 'a',
              'apiKey': 'old-secret',
              'baseUrl': 'https://a.example',
              'model': 'a',
            },
          ],
        }),
      );
      target.backupFailureHook = (stage) async {
        if (stage == 'afterCredentials') throw StateError('injected');
      };
      await expectLater(
        target.importAllDataFromFile(zip, allowApiKeys: true),
        throwsStateError,
      );
      expect(
        (await target.loadApiConfig()).endpoints.single.apiKey,
        'old-secret',
      );
      expect(
        secrets['whisnya_api_key_${base64UrlEncode(utf8.encode('b'))}'],
        isNull,
      );
    },
  );
  test(
    'maintenance drains operations and rejects stale epoch',
    () async {
      final store = JsonFileStore();
      final release = Completer<void>();
      final events = <String>[];
      final write = store.runOperation(() async {
        events.add('write');
        await release.future;
      });
      final maintenance = store.maintain(() {
        events.add('snapshot');
      }, advanceEpoch: true);
      final stale = store.runOperation(() {
        events.add('stale');
      }, expectedEpoch: 0);
      final assertion = expectLater(stale, throwsStateError);
      release.complete();
      await Future.wait([write, maintenance, assertion]);
      expect(events, ['write', 'snapshot']);
      expect(store.datasetEpoch, 1);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
  test(
    'ordinary writes queued before dataset switch are also invalidated',
    () async {
      final store = JsonFileStore();
      final release = Completer<void>();
      final active = store.runOperation(() => release.future);
      final maintenance = store.maintain(() {}, advanceEpoch: true);
      final stale = store.runOperation(() {});
      final assertion = expectLater(stale, throwsStateError);
      release.complete();
      await Future.wait([active, maintenance, assertion]);
    },
  );
  test('startup retries credentials after files already restored', () async {
    final folder = await Directory.systemTemp.createTemp('backup_key_restart_');
    addTearDown(() => folder.delete(recursive: true));
    final root = await Directory('${folder.path}/app_data').create();
    await File(
      '${root.path}/settings.json',
    ).writeAsString('{"languageCode":"zh"}');
    secrets['whisnya_api_endpoint_ids'] = '["a"]';
    final key = 'whisnya_api_key_${base64UrlEncode(utf8.encode('a'))}';
    secrets[key] = 'wrong-new-key';
    secrets['whisnya_backup_credentials_backup_rollback_123'] = jsonEncode({
      'whisnya_api_endpoint_ids': '["a"]',
      key: 'old-key',
    });
    await File('${folder.path}/backup_transaction.json').writeAsString(
      jsonEncode({
        'phase': 'restoring',
        'rollback': 'backup_rollback_123',
        'touchedIds': ['a'],
      }),
    );
    await LocalStorageService(appDataDirectory: root).ensureReady();
    expect(secrets[key], 'old-key');
    expect(
      await File('${folder.path}/backup_transaction.json').exists(),
      false,
    );
  });

  for (final stage in ['prepared', 'oldMoved', 'newActive', 'credentials']) {
    test(
      'restore failure at $stage preserves original and can restart',
      () async {
        final folder = await Directory.systemTemp.createTemp('backup_failure_');
        addTearDown(() => folder.delete(recursive: true));
        final source = LocalStorageService(
          appDataDirectory: Directory('${folder.path}/source/app_data'),
        );
        final target = LocalStorageService(
          appDataDirectory: Directory('${folder.path}/target/app_data'),
        );
        await source.saveSettings(const AppSettings(languageCode: 'en'));
        await target.saveSettings(const AppSettings(languageCode: 'zh'));
        final zip = await source.exportAllDataToFile();
        target.backupFailureHook = (current) async {
          if (current == stage) throw StateError('injected');
        };
        await expectLater(target.importAllDataFromFile(zip), throwsStateError);
        expect((await target.loadSettings()).languageCode, 'zh');
        final restarted = LocalStorageService(
          appDataDirectory: Directory('${folder.path}/target/app_data'),
        );
        expect((await restarted.loadSettings()).languageCode, 'zh');
        expect(target.datasetEpoch, 1);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  }
  test('retained rollback protects new data and can be toggled', () async {
    final folder = await Directory.systemTemp.createTemp('backup_rollback_');
    addTearDown(() => folder.delete(recursive: true));
    final source = LocalStorageService(
      appDataDirectory: Directory('${folder.path}/source/app_data'),
    );
    final target = LocalStorageService(
      appDataDirectory: Directory('${folder.path}/target/app_data'),
    );
    await source.saveSettings(const AppSettings(languageCode: 'en'));
    await target.saveSettings(const AppSettings(languageCode: 'zh'));
    await target.importAllDataFromFile(await source.exportAllDataToFile());
    expect((await target.loadSettings()).languageCode, 'en');
    expect(await target.hasBackupRollback(), true);
    await target.restorePreviousBackup();
    expect((await target.loadSettings()).languageCode, 'zh');
    await target.restorePreviousBackup();
    expect((await target.loadSettings()).languageCode, 'en');
  });
  test('startup repairs interruption after old directory rename', () async {
    final folder = await Directory.systemTemp.createTemp('backup_crash_');
    addTearDown(() => folder.delete(recursive: true));
    final old = await Directory('${folder.path}/backup_rollback_123').create();
    await File(
      '${old.path}/settings.json',
    ).writeAsString('{"languageCode":"en"}');
    await File('${folder.path}/backup_transaction.json').writeAsString(
      jsonEncode({'phase': 'oldMoved', 'rollback': 'backup_rollback_123'}),
    );
    final restarted = LocalStorageService(
      appDataDirectory: Directory('${folder.path}/app_data'),
    );
    expect((await restarted.loadSettings()).languageCode, 'en');
    expect(
      await File('${folder.path}/backup_transaction.json').exists(),
      false,
    );
  });
}
