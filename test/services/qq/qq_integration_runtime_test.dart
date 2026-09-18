import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/qq_contact_binding.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/qq/android/qq_native_bridge.dart';
import 'package:whisnya/services/qq/qq_integration_runtime.dart';

void main() {
  late Directory directory;
  late LocalStorageService storage;
  late _TrackingNativeBridge bridge;
  late QqIntegrationRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qq_runtime_');
    storage = LocalStorageService(
      appDataDirectory: directory,
      secureStorage: _MemorySecureStorage(),
    );
    await storage.ensureReady();
    final now = DateTime.utc(2026, 8, 3);
    final character = AppCharacter(
      id: 'character',
      name: 'Role',
      avatar: '',
      backgroundImage: '',
      backgroundImageOpacity: 1,
      backgroundBlur: 0,
      inputOpacity: 0.92,
      description: 'description',
      personality: 'personality',
      background: 'background',
      speakingStyle: 'style',
      openingMessage: 'opening',
      extraPrompt: '',
      defaultEndpointId: 'endpoint',
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
    await storage.saveCharacter(character);
    await storage.saveApiConfig(
      ApiConfig(
        endpoints: [
          AiEndpointConfig(
            id: 'endpoint',
            name: 'API',
            apiKey: 'test-key',
            baseUrl: 'https://example.test/v1',
            model: 'model',
            enabled: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        defaultEndpointId: 'endpoint',
      ),
    );
    final session = await storage.createChatSession(
      character.id,
      title: 'QQ · Alice',
    );
    await storage.markOpeningMessageInitialized(
      sessionId: session.id,
      characterId: character.id,
    );
    await storage.saveQqContactBinding(
      QqContactBinding(
        id: 'binding',
        mode: QqIntegrationMode.oneBot,
        externalUserId: '10001',
        displayName: 'Alice',
        characterId: character.id,
        sessionId: session.id,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await storage.saveQqIntegrationSettings(
      const QqIntegrationSettings(
        enabled: true,
        mode: QqIntegrationMode.oneBot,
      ),
    );
    bridge = _TrackingNativeBridge();
    runtime = QqIntegrationRuntime(
      storage: storage,
      aiGateway: _UnusedGateway(),
      nativeBridge: bridge,
    );
    await runtime.initialize();
    await runtime.start();
  });

  tearDown(() async {
    await runtime.stop();
    runtime.dispose();
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  test('pause marks the native bridge runtime inactive', () async {
    await runtime.pause();

    expect(bridge.nativeUpdates.last['runtimeActive'], isFalse);
  });

  test('binding changes refresh the native contact count', () async {
    final settings = await storage.loadQqIntegrationSettings();

    await runtime.applySettings(settings, bindings: const []);

    expect(bridge.nativeUpdates.last['enabledContacts'], 0);
  });

  test('unchanged bridge heartbeat does not refresh native settings', () async {
    final updatesBeforeHeartbeat = bridge.nativeUpdates.length;
    final token = await storage.loadOrCreateLocalBridgeToken();
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${runtime.bridgePort}/v1/qq/status'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType)
        ..set('X-Whisnya-Bridge-Version', '1');
      request.write(
        jsonEncode({
          'connected': true,
          'selfId': '90001',
          'nickname': 'Bot',
          'lastMessageAt': null,
          'lastError': null,
        }),
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.noContent);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } finally {
      client.close(force: true);
    }

    expect(bridge.nativeUpdates, hasLength(updatesBeforeHeartbeat));
  });
}

final class _TrackingNativeBridge extends QqNativeBridge {
  _TrackingNativeBridge() : super(isAndroid: false);

  final nativeUpdates = <Map<String, dynamic>>[];

  @override
  Future<void> updateNativeQqSettings(Map<String, dynamic> settings) async {
    nativeUpdates.add({...settings});
  }
}

final class _UnusedGateway implements AiGateway {
  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) => throw UnimplementedError();

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) => throw UnimplementedError();
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
