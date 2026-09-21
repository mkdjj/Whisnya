import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_response.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/auto_story/auto_story_actor_service.dart';
import 'package:whisnya/services/auto_story/auto_story_validator.dart';

class Gateway implements AiGateway, StructuredAiGateway {
  // Closed by each owning test after the scripted response.
  // ignore: close_sinks
  final controller = StreamController<AiResponseDelta>();
  @override
  Stream<AiResponseDelta> streamResponse(
    AiRequest request, {
    AiCancelToken? cancelToken,
  }) => controller.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'actor validation strips only own leading label and rejects multi actor scripts',
    () {
      expect(
        AutoStoryValidator.actorContent(
          '糖璃：你好，糖璃。',
          actorName: '糖璃',
          otherActorName: '小雨',
        ),
        '你好，糖璃。',
      );
      for (final value in [
        '糖璃：你好\n小雨：好的',
        'A:hello B:hi',
        '["你好"]',
        '{"content":"你好"}',
        '导演分析：应该推进',
        '  ',
        '😀' * 4001,
      ]) {
        expect(
          () => AutoStoryValidator.actorContent(
            value,
            actorName: '糖璃',
            otherActorName: '小雨',
          ),
          throwsFormatException,
        );
      }
      expect(
        AutoStoryValidator.actorContent(
          '😀' * 4000,
          actorName: '糖璃',
          otherActorName: '小雨',
        ).runes.length,
        4000,
      );
    },
  );
  test(
    'structured stream keeps reasoning out of content and reports missing usage as unknown',
    () async {
      final gateway = Gateway();
      final drafts = <String>[];
      final result = AutoStoryActorService(gateway).generate(
        endpoint: endpoint(),
        messages: const [],
        actorName: '糖璃',
        otherActorName: '小雨',
        includeReasoning: true,
        onDraft: (content, reasoning) => drafts.add(content),
      );
      gateway.controller.add(const AiResponseDelta(reasoningDelta: 'secret'));
      gateway.controller.add(const AiResponseDelta(contentDelta: '糖璃：你好'));
      await gateway.controller.close();
      final actual = await result;
      expect(actual.content, '你好');
      expect(actual.reasoningContent, 'secret');
      expect(actual.usage, isNull);
      expect(drafts.every((value) => !value.contains('secret')), isTrue);
    },
  );
  test('timeout cancels even a provider that never completes', () async {
    final gateway = Gateway();
    final token = AiCancelToken();
    final result =
        AutoStoryActorService(
          gateway,
          timeout: const Duration(milliseconds: 10),
        ).generate(
          endpoint: endpoint(),
          messages: const [],
          actorName: 'A',
          otherActorName: 'B',
          cancelToken: token,
        );
    await expectLater(result, throwsA(isA<TimeoutException>()));
    expect(token.isCancelled, isTrue);
    unawaited(gateway.controller.close());
  });
}

AiEndpointConfig endpoint() => AiEndpointConfig(
  id: 'endpoint',
  name: 'test',
  apiKey: 'test',
  baseUrl: 'https://example.invalid',
  model: 'test',
  enabled: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
