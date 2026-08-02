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
        mode: QqIntegrationMode.notification,
        externalUserId: 'contact',
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
        mode: QqIntegrationMode.notification,
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
    bridge.cancelCalls = 0;
  });

  tearDown(() async {
    await runtime.stop();
    runtime.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'pause immediately cancels pending native accessibility replies',
    () async {
      await runtime.pause();

      expect(bridge.cancelCalls, 1);
      expect(bridge.nativeUpdates.last['runtimeActive'], isFalse);
    },
  );

  test('binding changes invalidate queued accessibility replies', () async {
    final settings = await storage.loadQqIntegrationSettings();

    await runtime.applySettings(settings, bindings: const []);

    expect(bridge.cancelCalls, 1);
    expect(bridge.nativeUpdates.last['enabledContacts'], 0);
  });
}

final class _TrackingNativeBridge extends QqNativeBridge {
  _TrackingNativeBridge() : super(isAndroid: false);

  int cancelCalls = 0;
  final nativeUpdates = <Map<String, dynamic>>[];

  @override
  Future<void> cancelPendingAccessibilityReply() async {
    cancelCalls++;
  }

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
