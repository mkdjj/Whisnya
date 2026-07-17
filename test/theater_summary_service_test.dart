import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/theater/theater_summary_service.dart';

void main() {
  test('message deletion adjusts the absolute theater summary prefix', () {
    final messages = [
      _message('0', TheaterSpeakerType.user),
      _message('error', TheaterSpeakerType.system, isError: true),
      _message('2', TheaterSpeakerType.role),
      _message('3', TheaterSpeakerType.user),
    ];

    final cleared = theaterSummaryAfterMessageDeletion(
      summary: 'summary',
      summarizedMessageCount: 3,
      messages: messages,
      index: 0,
    );
    expect(cleared.summary, isEmpty);
    expect(cleared.summarizedMessageCount, 0);

    final shifted = theaterSummaryAfterMessageDeletion(
      summary: 'summary',
      summarizedMessageCount: 3,
      messages: messages,
      index: 1,
    );
    expect(shifted.summary, 'summary');
    expect(shifted.summarizedMessageCount, 2);

    final unchanged = theaterSummaryAfterMessageDeletion(
      summary: 'summary',
      summarizedMessageCount: 3,
      messages: messages,
      index: 3,
    );
    expect(unchanged.summary, 'summary');
    expect(unchanged.summarizedMessageCount, 3);
  });

  test('summarizes eligible history while preserving recent context', () async {
    final gateway = _FakeGateway();
    final service = TheaterSummaryService(gateway);
    final messages = [
      for (var i = 0; i < 20; i++)
        TheaterMessage(
          id: '$i',
          sessionId: 'session',
          round: i ~/ 2,
          speakerType: i.isEven
              ? TheaterSpeakerType.user
              : TheaterSpeakerType.role,
          speakerId: i.isEven ? '' : 'role',
          speakerName: i.isEven ? '我' : '角色',
          content: '消息 $i',
          time: DateTime(2026),
        ),
    ];
    final session = TheaterSession(
      id: 'session',
      title: '群聊',
      keepRoundCount: 5,
      participants: const [
        TheaterParticipant(
          id: 'role',
          source: TheaterRoleSource.appCharacter,
          name: '角色',
          avatar: '',
          description: '',
          personality: '',
          background: '',
          speakingStyle: '',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final result = await service.summarize(
      session: session,
      messages: messages,
      endpoint: _endpoint,
    );

    expect(result?.summary, '新总结');
    expect(result?.summarizedMessageCount, greaterThan(0));
    expect(result?.summarizedMessageCount, lessThanOrEqualTo(14));
    expect(result?.usage.totalTokens, 3);
    expect(gateway.lastMessages.last['content'], contains('消息 0'));
    expect(gateway.lastTemperature, 0.2);
  });
}

TheaterMessage _message(
  String id,
  TheaterSpeakerType speakerType, {
  bool isError = false,
}) {
  return TheaterMessage(
    id: id,
    sessionId: 'session',
    round: 0,
    speakerType: speakerType,
    speakerId: id,
    speakerName: id,
    content: isError ? 'error' : id,
    isError: isError,
    errorMessage: isError ? 'error' : '',
    time: DateTime(2026),
  );
}

final _endpoint = AiEndpointConfig(
  id: 'endpoint',
  name: 'Endpoint',
  apiKey: 'key',
  baseUrl: 'https://example.com/v1',
  model: 'model',
  enabled: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeGateway implements AiGateway {
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
    int? maxTokens,
    void Function(AiUsage usage)? onUsage,
  }) async {
    lastMessages = messages;
    lastTemperature = temperature;
    onUsage?.call(
      const AiUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3),
    );
    return '新总结';
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
  }) => const Stream.empty();
}
