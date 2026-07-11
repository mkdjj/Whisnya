import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/screens/chat_screen.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  test('chat screen accepts an injected fake gateway', () async {
    final directory = await Directory.systemTemp.createTemp('chat-flow-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: directory);
    final character = AppCharacter.fromJson({'id': 'c', 'name': '角色'});

    final screen = ChatScreen(
      storage: storage,
      aiService: _FakeGateway(),
      character: character,
      settings: const AppSettings(),
    );
    expect(screen.aiService, isA<_FakeGateway>());
    expect(screen.character.id, 'c');
  });
}

final class _FakeGateway implements AiGateway {
  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async => '';

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) => const Stream.empty();
}
