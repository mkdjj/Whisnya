import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_contact_binding.dart';
import 'package:whisnya/models/qq_diagnostic_event.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/qq/qq_exceptions.dart';

void main() {
  late Directory directory;
  late _MemorySecureStorage secureStorage;
  late LocalStorageService storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qq_storage_');
    secureStorage = _MemorySecureStorage();
    storage = LocalStorageService(
      appDataDirectory: directory,
      secureStorage: secureStorage,
    );
    await storage.ensureReady();
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'stores settings under config and token only in secure storage',
    () async {
      await storage.saveQqIntegrationSettings(
        const QqIntegrationSettings(
          enabled: true,
          mode: QqIntegrationMode.oneBot,
        ),
      );
      await storage.saveOneBotAccessToken('top-secret');

      final file = File(
        '${directory.path}${Platform.pathSeparator}config'
        '${Platform.pathSeparator}qq_integration.json',
      );
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), isNot(contains('top-secret')));
      expect(await storage.loadOneBotAccessToken(), 'top-secret');

      await storage.clearOneBotAccessToken();
      expect(await storage.loadOneBotAccessToken(), isEmpty);
    },
  );

  test(
    'creates and reuses a 32-byte local bridge token in secure storage',
    () async {
      final first = await storage.loadOrCreateLocalBridgeToken();
      final second = await storage.loadOrCreateLocalBridgeToken();

      expect(first, second);
      expect(base64Url.decode(base64Url.normalize(first)), hasLength(32));
      expect(secureStorage.values['whisnya.qq.local_bridge_token'], first);
    },
  );

  test('binding CRUD is atomic and rejects duplicate sessions', () async {
    final first = _binding(id: 'b1', externalUserId: '10001', sessionId: 's1');
    await storage.saveQqContactBinding(first);
    await expectLater(
      storage.saveQqContactBinding(
        _binding(id: 'b2', externalUserId: '10002', sessionId: 's1'),
      ),
      throwsA(isA<QqBindingException>()),
    );
    await Future.wait([
      storage.saveQqContactBinding(first.copyWith(displayName: 'Updated')),
      storage.saveQqContactBinding(
        _binding(id: 'b2', externalUserId: '10002', sessionId: 's2'),
      ),
    ]);
    final values = await storage.loadQqContactBindings();
    expect(values, hasLength(2));
    expect(values.firstWhere((item) => item.id == 'b1').displayName, 'Updated');

    await storage.deleteQqContactBinding('b1');
    expect((await storage.loadQqContactBindings()).map((item) => item.id), [
      'b2',
    ]);
  });

  test('diagnostics retain only the newest two hundred entries', () async {
    for (var index = 0; index < 205; index++) {
      await storage.appendQqDiagnosticEvent(
        QqDiagnosticEvent(
          time: DateTime.utc(2026, 8, 3).add(Duration(seconds: index)),
          mode: QqIntegrationMode.oneBot,
          eventType: QqDiagnosticEventType.received,
          success: true,
          messageIdSuffix: 'message-$index',
        ),
      );
    }
    final values = await storage.loadQqDiagnostics();
    expect(values, hasLength(200));
    expect(values.first.time, DateTime.utc(2026, 8, 3, 0, 0, 5));
    await storage.clearQqDiagnostics();
    expect(await storage.loadQqDiagnostics(), isEmpty);
  });

  test(
    'backup includes qq settings and bindings but never secure token',
    () async {
      await storage.saveQqIntegrationSettings(
        const QqIntegrationSettings(mode: QqIntegrationMode.notification),
      );
      await storage.saveQqContactBinding(
        _binding(id: 'b1', externalUserId: 'key', sessionId: 's1'),
      );
      await storage.saveOneBotAccessToken('never-export-this');

      final archive = ZipDecoder().decodeBytes(await storage.exportAllData());
      final names = archive.files.map((file) => file.name).toSet();
      expect(names, contains('config/qq_integration.json'));
      expect(names, contains('config/qq_contact_bindings.json'));
      final allBytes = archive.files
          .where((file) => file.isFile)
          .expand((file) => file.content as List<int>)
          .toList();
      expect(
        String.fromCharCodes(allBytes),
        isNot(contains('never-export-this')),
      );
    },
  );
}

QqContactBinding _binding({
  required String id,
  required String externalUserId,
  required String sessionId,
}) {
  final now = DateTime.utc(2026, 8, 3);
  return QqContactBinding(
    id: id,
    mode: QqIntegrationMode.oneBot,
    externalUserId: externalUserId,
    displayName: 'Contact $id',
    characterId: 'character',
    sessionId: sessionId,
    createdAt: now,
    updatedAt: now,
  );
}

final class _MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}
