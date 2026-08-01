import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/chat/memory_extraction_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 31);
  final endpoint = AiEndpointConfig(
    id: 'endpoint',
    name: 'Endpoint',
    apiKey: 'key',
    baseUrl: 'https://example.test/v1',
    model: 'model',
    enabled: true,
    createdAt: now,
    updatedAt: now,
  );

  test(
    'extracts at most ten cleaned candidates from surrounding text',
    () async {
      final items = [
        {
          'title': ' Preferred name ',
          'content': ' Call the user Star. ',
          'scope': 'invalid',
          'keywords': [' Name ', 'name', ''],
          'priority': 130,
        },
        for (var index = 1; index < 12; index++)
          {
            'title': 'Title $index',
            'content': 'Content $index',
            'scope': 'character',
            'keywords': <String>[],
            'priority': index,
          },
        {'title': '', 'content': 'invalid empty title'},
      ];
      final gateway = _FakeGateway('prefix\n${jsonEncode(items)}\nsuffix');
      final messages = [
        ChatMessage(role: 'user', content: 'too old', time: now),
        for (var index = 0; index < 51; index++)
          ChatMessage(
            role: index.isEven ? 'user' : 'assistant',
            content: 'line $index',
            time: now,
          ),
        ChatMessage(role: 'system', content: 'ignore system', time: now),
      ];

      final result = await MemoryExtractionService(gateway).extract(
        characterId: 'character',
        sessionId: 'session',
        messages: messages,
        endpoint: endpoint,
        now: now,
      );

      expect(result, hasLength(10));
      expect(result.first.scope, MemoryScope.session);
      expect(result.first.sessionId, 'session');
      expect(result.first.keywords, isEmpty);
      expect(result.first.priority, 100);
      expect(
        result.skip(1),
        everyElement(
          predicate<CharacterMemoryEntry>(
            (entry) =>
                entry.scope == MemoryScope.character && entry.sessionId == null,
          ),
        ),
      );
      expect(gateway.lastTemperature, 0.2);
      expect(gateway.lastMessages, hasLength(2));
      final transcript = gateway.lastMessages.last['content']!;
      expect(transcript, isNot(contains('too old')));
      expect(transcript, isNot(contains('line 0')));
      expect(transcript, contains('line 1'));
      expect(transcript, contains('line 50'));
      expect(transcript, isNot(contains('ignore system')));
      expect(gateway.lastMessages.first['content'], contains('最多 10 条'));
    },
  );

  test('reports malformed model output without saving anything', () async {
    final gateway = _FakeGateway('not json');

    expect(
      () => MemoryExtractionService(gateway).extract(
        characterId: 'character',
        sessionId: 'session',
        messages: const [],
        endpoint: endpoint,
      ),
      throwsA(
        isA<MemoryExtractionException>().having(
          (error) => error.message,
          'message',
          contains('JSON'),
        ),
      ),
    );
  });
}

final class _FakeGateway implements AiGateway {
  _FakeGateway(this.reply);

  final String reply;
  List<Map<String, String>> lastMessages = const [];
  double? lastTemperature;

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
    lastMessages = messages;
    lastTemperature = temperature;
    return reply;
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
