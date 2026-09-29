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
  testWidgets('draft updates coalesce bursts and flush final reasoning', (
    tester,
  ) async {
    final gateway = Gateway();
    final drafts = <(String, String)>[];
    final result = AutoStoryActorService(gateway).generate(
      endpoint: endpoint(),
      messages: const [],
      actorName: '糖璃',
      otherActorName: '小雨',
      includeReasoning: true,
      onDraft: (text, reasoning) => drafts.add((text, reasoning)),
    );
    for (var i = 0; i < 100; i++) {
      gateway.controller.add(
        const AiResponseDelta(contentDelta: '你', reasoningDelta: '想'),
      );
    }
    await tester.pump();
    expect(drafts, isEmpty);
    await tester.pump(const Duration(milliseconds: 40));
    expect(drafts, [('你' * 100, '想' * 100)]);
    gateway.controller.add(
      const AiResponseDelta(contentDelta: '好', reasoningDelta: '完'),
    );
    unawaited(gateway.controller.close());
    await tester.pump();
    final completed = await result;
    expect(completed.content, '${'你' * 100}好');
    expect(completed.reasoningContent, '${'想' * 100}完');
    expect(drafts.last, (completed.content, completed.reasoningContent));
    expect(drafts.length, 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(drafts.length, 2);
  });

  testWidgets('cancelled actor has no delayed draft publication', (
    tester,
  ) async {
    final gateway = Gateway();
    final token = AiCancelToken();
    final drafts = <String>[];
    final result = AutoStoryActorService(gateway).generate(
      endpoint: endpoint(),
      messages: const [],
      actorName: '糖璃',
      otherActorName: '小雨',
      cancelToken: token,
      onDraft: (text, _) => drafts.add(text),
    );
    final cancelled = expectLater(result, throwsA(isA<AiException>()));
    gateway.controller.add(const AiResponseDelta(contentDelta: '尚未显示'));
    await tester.pump();
    token.cancel();
    unawaited(gateway.controller.close());
    await tester.pump();
    await cancelled;
    await tester.pump(const Duration(milliseconds: 100));
    expect(drafts, isEmpty);
  });

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
