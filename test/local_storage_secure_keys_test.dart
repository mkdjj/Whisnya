import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('secure_keys_');
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'loads endpoint keys concurrently without changing endpoint order',
    () async {
      final secureStorage = _BlockingSecureStorage(blockReads: true);
      final storage = LocalStorageService(
        appDataDirectory: directory,
        secureStorage: secureStorage,
      );
      await storage.ensureReady();
      await File(
        '${directory.path}${Platform.pathSeparator}api_config.json',
      ).writeAsString(jsonEncode(_config().toJson()));

      final load = storage.loadApiConfig();
      var overlapped = false;
      try {
        await secureStorage.twoEndpointOperationsStarted.future.timeout(
          const Duration(milliseconds: 250),
        );
        overlapped = true;
      } finally {
        secureStorage.release();
      }
      final loaded = await load;

      expect(overlapped, isTrue);
      expect(loaded.endpoints.map((endpoint) => endpoint.apiKey), [
        'secret-0',
        'secret-1',
      ]);
    },
  );

  test(
    'writes endpoint keys concurrently before updating the key index',
    () async {
      final secureStorage = _BlockingSecureStorage(blockWrites: true);
      final storage = LocalStorageService(
        appDataDirectory: directory,
        secureStorage: secureStorage,
      );

      final save = storage.saveApiConfig(_config(withKeys: true));
      var overlapped = false;
      try {
        await secureStorage.twoEndpointOperationsStarted.future.timeout(
          const Duration(milliseconds: 250),
        );
        overlapped = true;
      } finally {
        secureStorage.release();
      }
      await save;

      expect(overlapped, isTrue);
      expect(secureStorage.endpointValues.values.toSet(), {'key-a', 'key-b'});
      expect(secureStorage.indexWrittenAfterEndpointOperations, isTrue);
    },
  );
}

ApiConfig _config({bool withKeys = false}) {
  final now = DateTime(2026);
  return ApiConfig(
    endpoints: [
      AiEndpointConfig(
        id: 'a',
        name: 'A',
        apiKey: withKeys ? 'key-a' : '',
        baseUrl: 'https://a.test/v1',
        model: 'a',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ),
      AiEndpointConfig(
        id: 'b',
        name: 'B',
        apiKey: withKeys ? 'key-b' : '',
        baseUrl: 'https://b.test/v1',
        model: 'b',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    defaultEndpointId: 'a',
  );
}

final class _BlockingSecureStorage extends FlutterSecureStorage {
  _BlockingSecureStorage({this.blockReads = false, this.blockWrites = false});

  final bool blockReads;
  final bool blockWrites;
  final twoEndpointOperationsStarted = Completer<void>();
  final _release = Completer<void>();
  final endpointValues = <String, String>{};
  var _endpointOperationCount = 0;
  var indexWrittenAfterEndpointOperations = false;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  Future<int> _blockEndpointOperation() async {
    final index = _endpointOperationCount++;
    if (_endpointOperationCount == 2 &&
        !twoEndpointOperationsStarted.isCompleted) {
      twoEndpointOperationsStarted.complete();
    }
    await _release.future;
    return index;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!key.startsWith('whisnya_api_key_')) return null;
    if (!blockReads) return endpointValues[key];
    final index = await _blockEndpointOperation();
    return 'secret-$index';
  }

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
    if (!key.startsWith('whisnya_api_key_')) {
      indexWrittenAfterEndpointOperations = _endpointOperationCount == 2;
      return;
    }
    if (value != null) endpointValues[key] = value;
    if (blockWrites) await _blockEndpointOperation();
  }
}
