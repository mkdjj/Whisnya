import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/chat/chat_summary_service.dart';

void main() {
  final now = DateTime(2026);
  final endpoint = AiEndpointConfig(
    id: 'test',
    name: 'Test',
    apiKey: 'key',
    baseUrl: 'https://example.test',
    model: 'model',
    enabled: true,
    createdAt: now,
    updatedAt: now,
  );

  test(
    'summary service skips below the limit and summarizes old messages',
    () async {
      final gateway = _FakeGateway(reply: '摘要');
      final service = ChatSummaryService(gateway);
      final messages = List.generate(
        32,
        (index) => ChatMessage(
          role: index.isEven ? 'user' : 'assistant',
          content: '$index',
          time: now,
        ),
      );
      expect(
        await service.update(
          characterId: 'c',
          current: ChatSummary.empty('c'),
          messages: messages.take(30).toList(),
          summaryLimit: 30,
          settings: const AppSettings(),
          endpoint: endpoint,
          cancelToken: AiCancelToken(),
        ),
        isNull,
      );
      final result = await service.update(
        characterId: 'c',
        current: ChatSummary.empty('c'),
        messages: messages,
        summaryLimit: 30,
        settings: const AppSettings(),
        endpoint: endpoint,
        cancelToken: AiCancelToken(),
      );
      expect(result?.summary, '摘要');
      expect(result?.summarizedMessageCount, greaterThan(0));
      expect(gateway.lastTemperature, 0.2);
    },
  );

  test('message deletion invalidates only the summarized chat prefix', () {
    final messages = [
      ChatMessage(role: 'user', content: '0', time: now),
      ChatMessage(role: 'system', content: 'ignored', time: now),
      ChatMessage(role: 'assistant', content: '1', time: now),
      ChatMessage(role: 'user', content: '2', time: now),
    ];
    final summary = ChatSummary(
      characterId: 'c',
      summary: 'summary',
      updatedAt: now,
      summarizedMessageCount: 2,
    );

    for (final index in [0, 2]) {
      final next = chatSummaryAfterMessageDeletion(
        summary: summary,
        messages: messages,
        index: index,
      );
      expect(next.summary, isEmpty);
      expect(next.summarizedMessageCount, 0);
      expect(next.characterId, 'c');
    }
    expect(
      chatSummaryAfterMessageDeletion(
        summary: summary,
        messages: messages,
        index: 1,
      ),
      same(summary),
    );
    expect(
      chatSummaryAfterMessageDeletion(
        summary: summary,
        messages: messages,
        index: 3,
      ),
      same(summary),
    );
  });
}

final class _FakeGateway implements AiGateway {
  _FakeGateway({this.reply = ''});

  final String reply;
  List<Map<String, String>>? lastMessages;
  double? lastTemperature;

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    int? maxTokens,
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
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) {
    lastMessages = messages;
    return const Stream.empty();
  }
}
