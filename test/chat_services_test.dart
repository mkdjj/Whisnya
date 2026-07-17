import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/chat/character_chat_service.dart';
import 'package:whisnya/services/chat/chat_request_factory.dart';
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

  test('character chat streams through the gateway', () async {
    final gateway = _FakeGateway(stream: const ['a', 'b']);
    final result = await CharacterChatService(gateway)
        .stream(
          endpoint: endpoint,
          messages: const [],
          cancelToken: AiCancelToken(),
          includeReasoning: false,
        )
        .join();
    expect(result, 'ab');
    expect(gateway.lastMessages, isEmpty);
  });

  test('request factory preserves PromptBuilder message construction', () {
    final character = AppCharacter.fromJson({'id': 'c', 'name': '猫'});
    final messages = [ChatMessage(role: 'user', content: '你好', time: now)];
    final result = const ChatRequestFactory().build(
      character: character,
      historySummary: '',
      summarizedMessageCount: 0,
      messages: messages,
    );
    expect(result.last, {'role': 'user', 'content': '你好'});
  });

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
  _FakeGateway({this.reply = '', this.stream = const []});

  final String reply;
  final List<String> stream;
  List<Map<String, String>>? lastMessages;

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async {
    lastMessages = messages;
    return reply;
  }

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
  }) {
    lastMessages = messages;
    return Stream.fromIterable(stream);
  }
}
