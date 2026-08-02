import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/qq_contact_binding.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/models/unified_qq_message.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/qq/background_character_chat_service.dart';

void main() {
  late Directory directory;
  late LocalStorageService storage;
  late _FakeGateway gateway;
  late AppCharacter character;
  late QqContactBinding binding;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('background_qq_chat_');
    storage = LocalStorageService(
      appDataDirectory: directory,
      secureStorage: _MemorySecureStorage(),
    );
    await storage.ensureReady();
    gateway = _FakeGateway();
    character = _character();
    await storage.saveCharacter(character);
    await storage.saveApiConfig(_apiConfig());
    final session = await storage.createChatSession(
      character.id,
      title: 'QQ · Alice',
    );
    await storage.markOpeningMessageInitialized(
      sessionId: session.id,
      characterId: character.id,
    );
    binding = _binding(session.id);
    await storage.saveQqContactBinding(binding);
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'uses shared memory and only referenced world books then saves both messages',
    () async {
      final now = DateTime.utc(2026, 8, 3);
      await storage.saveCharacterMemory(
        CharacterMemoryEntry(
          id: 'long',
          characterId: character.id,
          scope: MemoryScope.character,
          title: 'Long',
          content: 'LONG_MEMORY',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await storage.saveCharacterMemory(
        CharacterMemoryEntry(
          id: 'session',
          characterId: character.id,
          scope: MemoryScope.session,
          sessionId: binding.sessionId,
          title: 'Session',
          content: 'SESSION_MEMORY',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await storage.saveWorldBook(
        WorldBook(
          id: 'book',
          name: 'Referenced',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await storage.saveWorldBookEntry(
        WorldBookEntry(
          id: 'entry',
          worldBookId: 'book',
          title: 'Keyword',
          content: 'WORLD_BOOK_CONTENT',
          keywords: const ['dragon'],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final reply =
          await BackgroundCharacterChatService(
            storage: storage,
            aiGateway: gateway,
          ).reply(
            binding: binding,
            message: _message('A dragon arrived'),
            settings: const QqIntegrationSettings(requestTimeoutSeconds: 15),
          );

      expect(reply.text, 'AI reply');
      final prompt = gateway.requests.single
          .map((item) => item['content'])
          .join('\n');
      expect(prompt, contains('LONG_MEMORY'));
      expect(prompt, contains('SESSION_MEMORY'));
      expect(prompt, contains('WORLD_BOOK_CONTENT'));
      final session = (await storage.loadChatSessions(
        character.id,
      )).firstWhere((item) => item.id == binding.sessionId);
      final messages = await storage.loadChatBySession(session);
      expect(messages.map((message) => message.content), [
        'A dragon arrived',
        'AI reply',
      ]);
      expect(messages, isNot(contains(character.openingMessage)));
      expect(
        (await storage.loadAiUsageRecords()).single.requestType,
        'qqCharacterChat',
      );
    },
  );

  test(
    'recreates a missing session without sending the opening message',
    () async {
      final missing = binding.copyWith(sessionId: 'missing_session');
      await storage.saveQqContactBinding(missing);

      final reply =
          await BackgroundCharacterChatService(
            storage: storage,
            aiGateway: gateway,
          ).reply(
            binding: missing,
            message: _message('hello'),
            settings: const QqIntegrationSettings(),
          );

      final updated = (await storage.loadQqContactBindings()).single;
      expect(updated.sessionId, isNot('missing_session'));
      final session = (await storage.loadChatSessions(
        character.id,
      )).firstWhere((item) => item.id == updated.sessionId);
      expect(session.openingMessageInitialized, isTrue);
      expect(
        (await storage.loadChatBySession(session)).map((item) => item.content),
        ['hello', 'AI reply'],
      );
      expect(reply.sessionId, session.id);
    },
  );
}

AppCharacter _character() {
  final now = DateTime.utc(2026, 8, 3);
  return AppCharacter(
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
    openingMessage: 'OPENING_MUST_NOT_BE_SENT',
    extraPrompt: '',
    defaultEndpointId: 'endpoint',
    worldBookIds: const ['book'],
    createdAt: now,
    updatedAt: now,
    lastUsedAt: now,
  );
}

ApiConfig _apiConfig() {
  final now = DateTime.utc(2026, 8, 3);
  return ApiConfig(
    endpoints: [
      AiEndpointConfig(
        id: 'endpoint',
        name: 'API',
        apiKey: 'secret',
        baseUrl: 'https://example.test/v1',
        model: 'model',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    defaultEndpointId: 'endpoint',
  );
}

QqContactBinding _binding(String sessionId) {
  final now = DateTime.utc(2026, 8, 3);
  return QqContactBinding(
    id: 'binding',
    mode: QqIntegrationMode.oneBot,
    externalUserId: '900719925474099312345',
    displayName: 'Alice',
    characterId: 'character',
    sessionId: sessionId,
    createdAt: now,
    updatedAt: now,
  );
}

UnifiedQqMessage _message(String text) => UnifiedQqMessage(
  source: QqIntegrationMode.oneBot,
  messageId: 'message',
  externalUserId: '900719925474099312345',
  senderDisplayName: 'Alice',
  text: text,
  timestamp: DateTime.utc(2026, 8, 3),
  rawConversationTitle: 'Alice',
);

final class _FakeGateway implements AiGateway {
  final requests = <List<Map<String, String>>>[];

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) async {
    requests.add(messages);
    onUsage?.call(
      const AiUsage(promptTokens: 3, completionTokens: 2, totalTokens: 5),
    );
    return 'AI reply';
  }

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
  }) => const Stream.empty();
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
    if (value != null) values[key] = value;
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
