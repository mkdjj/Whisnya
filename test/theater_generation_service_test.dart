import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/theater/theater_generation_event.dart';
import 'package:whisnya/services/theater/theater_generation_service.dart';

void main() {
  test('single API assigns plain text when one role is allowed', () async {
    final service = TheaterGenerationService(_FakeGateway(['普通回复']));

    final events = await service
        .generate(
          session: _session(apiMode: TheaterApiMode.singleApi),
          apiConfig: _config,
          participants: const [_first],
          messages: const [],
          novelSummary: '',
          round: 1,
        )
        .toList();

    expect(
      events.whereType<TheaterMessageFinished>().single.message.content,
      '普通回复',
    );
  });

  test('a selected participant list generates only that participant', () async {
    final service = TheaterGenerationService(_FakeGateway(['乙回复']));

    final events = await service
        .generate(
          session: _session(apiMode: TheaterApiMode.multiApi),
          apiConfig: _config,
          participants: const [_second],
          messages: const [],
          novelSummary: '',
          round: 2,
        )
        .toList();

    final message = events.whereType<TheaterMessageFinished>().single.message;
    expect(message.speakerId, 'b');
    expect(message.round, 2);
  });

  test('multi API retries one invalid role reply and sanitizes it', () async {
    final gateway = _FakeGateway(['[乙] 错误', '[甲] 正确']);
    final service = TheaterGenerationService(gateway);

    final events = await service
        .generate(
          session: _session(apiMode: TheaterApiMode.multiApi),
          apiConfig: _config,
          participants: const [_first],
          messages: const [],
          novelSummary: '',
          round: 1,
        )
        .toList();

    expect(gateway.requests, hasLength(2));
    expect(
      events.whereType<TheaterMessageFinished>().single.message.content,
      '正确',
    );
  });

  test('multi API emits a role failure after the retry', () async {
    final service = TheaterGenerationService(
      _FakeGateway(['[乙] 错误', '[乙] 仍然错误']),
    );

    final events = await service
        .generate(
          session: _session(apiMode: TheaterApiMode.multiApi),
          apiConfig: _config,
          participants: const [_first],
          messages: const [],
          novelSummary: '',
          round: 1,
        )
        .toList();

    expect(events.whereType<TheaterGenerationFailed>(), hasLength(1));
  });

  test(
    'sequential roles see earlier replies while parallel roles do not',
    () async {
      final sequentialGateway = _FakeGateway(['甲回复', '乙回复']);
      final sequential = TheaterGenerationService(sequentialGateway);
      await sequential
          .generate(
            session: _session(
              apiMode: TheaterApiMode.multiApi,
              mode: TheaterMultiApiReplyMode.randomSequential,
            ),
            apiConfig: _config,
            participants: const [_first, _second],
            messages: const [],
            novelSummary: '',
            round: 1,
          )
          .drain<void>();
      expect(sequentialGateway.requests[1].toString(), contains('甲回复'));

      final parallelGateway = _FakeGateway(['甲回复', '乙回复']);
      final parallel = TheaterGenerationService(parallelGateway);
      await parallel
          .generate(
            session: _session(
              apiMode: TheaterApiMode.multiApi,
              mode: TheaterMultiApiReplyMode.parallel,
            ),
            apiConfig: _config,
            participants: const [_first, _second],
            messages: const [],
            novelSummary: '',
            round: 1,
          )
          .drain<void>();
      expect(parallelGateway.requests[1].toString(), isNot(contains('甲回复')));
    },
  );

  test('sequential generation continues after one participant fails', () async {
    final service = TheaterGenerationService(
      _FakeGateway([AiException('甲网络失败'), '乙回复']),
    );

    final events = await service
        .generate(
          session: _session(
            apiMode: TheaterApiMode.multiApi,
            mode: TheaterMultiApiReplyMode.randomSequential,
          ),
          apiConfig: _config,
          participants: const [_first, _second],
          messages: const [],
          novelSummary: '',
          round: 3,
        )
        .toList();

    final failure = events.whereType<TheaterGenerationFailed>().single.message;
    expect(failure.speakerId, 'a');
    expect(failure.speakerName, '甲');
    expect(failure.round, 3);
    expect(failure.isError, isTrue);
    expect(failure.errorMessage, contains('甲网络失败'));
    expect(
      events.whereType<TheaterMessageFinished>().single.message.speakerId,
      'b',
    );
  });

  test('parallel participant failure is emitted instead of thrown', () async {
    final service = TheaterGenerationService(
      _FakeGateway([AiException('甲超时'), '乙回复']),
    );

    final events = await service
        .generate(
          session: _session(
            apiMode: TheaterApiMode.multiApi,
            mode: TheaterMultiApiReplyMode.parallel,
          ),
          apiConfig: _config,
          participants: const [_first, _second],
          messages: const [],
          novelSummary: '',
          round: 4,
        )
        .toList();

    expect(events.whereType<TheaterGenerationFailed>(), hasLength(1));
    expect(events.whereType<TheaterMessageFinished>(), hasLength(1));
  });
}

const _first = TheaterParticipant(
  id: 'a',
  source: TheaterRoleSource.appCharacter,
  name: '甲',
  avatar: '',
  description: '',
  personality: '',
  background: '',
  speakingStyle: '',
  endpointId: 'a',
);
const _second = TheaterParticipant(
  id: 'b',
  source: TheaterRoleSource.appCharacter,
  name: '乙',
  avatar: '',
  description: '',
  personality: '',
  background: '',
  speakingStyle: '',
  endpointId: 'b',
);

TheaterSession _session({
  required TheaterApiMode apiMode,
  TheaterMultiApiReplyMode mode = TheaterMultiApiReplyMode.randomSequential,
}) => TheaterSession(
  id: 'session',
  title: '群聊',
  apiMode: apiMode,
  multiApiReplyMode: mode,
  singleEndpointId: 'a',
  participants: const [_first, _second],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _config = ApiConfig(
  endpoints: [
    for (final id in const ['a', 'b'])
      AiEndpointConfig(
        id: id,
        name: id,
        apiKey: 'key',
        baseUrl: 'https://example.com/v1',
        model: 'model',
        enabled: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ],
);

class _FakeGateway implements AiGateway {
  _FakeGateway(this.responses);

  final List<Object> responses;
  final requests = <List<Map<String, String>>>[];
  var _index = 0;

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
  }) {
    requests.add(messages);
    final response = responses[_index++];
    return response is Exception
        ? Stream.error(response)
        : Stream.value(response as String);
  }

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
