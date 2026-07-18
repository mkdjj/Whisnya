import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/novel/novel_chat_service.dart';

void main() {
  test('streams a non-empty novel role reply', () async {
    final service = NovelChatService(_FakeGateway('回复'));
    final role = NovelRoleCandidate(
      name: '角色',
      description: '',
      personality: '',
      speakingStyle: '',
      background: '',
    );
    final book = NovelBook(
      id: 'book',
      title: 'Book',
      textPath: 'book.txt',
      roles: [role],
      selectedRoleIndex: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final reply = await service
        .streamReply(
          book: book,
          aiRole: role,
          historySummary: '',
          summarizedMessageCount: 0,
          messages: const [],
          apiKey: 'key',
          baseUrl: 'https://example.com/v1',
          model: 'model',
        )
        .join();

    expect(reply, '回复');
  });
}

class _FakeGateway implements AiGateway {
  _FakeGateway(this.reply);
  final String reply;

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
  }) => Stream.value(reply);

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
}
