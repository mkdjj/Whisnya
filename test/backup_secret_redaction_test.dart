import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/services/local_storage_service.dart';

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
            if (call.method == 'write') secrets[key] = args['value'] as String;
            if (call.method == 'delete') secrets.remove(key);
            return null;
          },
        );
  });
  for (final changed in [false, true]) {
    test(
      'key-free restore ${changed ? 'detaches changed address' : 'keeps matching endpoint credentials'}',
      () async {
        final folder = await Directory.systemTemp.createTemp('backup_keys_');
        addTearDown(() => folder.delete(recursive: true));
        final source = LocalStorageService(
          appDataDirectory: Directory('${folder.path}/src/app_data'),
        );
        final target = LocalStorageService(
          appDataDirectory: Directory('${folder.path}/dst/app_data'),
        );
        final raw = <String, dynamic>{
          'endpoints': [
            {
              'id': 'a',
              'apiKey': 'secret',
              'baseUrl': 'https://api.example/v1',
              'model': 'test',
            },
          ],
        };
        await target.saveApiConfig(ApiConfig.fromJson(raw));
        await source.ensureReady();
        final incoming = {
          'endpoints': [
            {
              'id': 'a',
              'apiKey': '',
              'baseUrl': changed
                  ? 'https://other.example/v1'
                  : 'https://API.example/v1/',
              'model': 'test',
            },
          ],
        };
        await File(
          '${(await source.appDataDirectory).path}/api_config.json',
        ).writeAsString(jsonEncode(incoming));
        await target.importAllDataFromFile(await source.exportAllDataToFile());
        expect(
          (await target.loadApiConfig()).endpoints.single.apiKey,
          changed ? '' : 'secret',
        );
        await target.restorePreviousBackup();
        expect(
          (await target.loadApiConfig()).endpoints.single.apiKey,
          'secret',
        );
      },
    );
  }
  test('corrupt api config blocks default export', () async {
    final folder = await Directory.systemTemp.createTemp('backup_corrupt_key_');
    addTearDown(() => folder.delete(recursive: true));
    final source = LocalStorageService(
      appDataDirectory: Directory('${folder.path}/app_data'),
    );
    await source.ensureReady();
    await File(
      '${(await source.appDataDirectory).path}/api_config.json',
    ).writeAsString('{"apiKey":"secret"');
    await expectLater(source.exportAllDataToFile(), throwsFormatException);
  });
  test(
    'redacts historical and nested credential names without mutating source',
    () {
      final original = <String, dynamic>{
        'apiKey': 'secret',
        'nested': {'bridgeToken': 'secret', 'api_key': 'secret'},
        'endpoints': [
          {'apiKey': 'secret'},
        ],
      };
      final redacted = redactApiKeysForExport(original);
      expect(redacted.toString(), isNot(contains('secret')));
      expect(original['apiKey'], 'secret');
    },
  );
}
