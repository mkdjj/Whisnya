import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';

void main() {
  test('OpenAI adapter builds requests and parses stream events', () {
    const adapter = OpenAiCompatibleAdapter();
    const request = AiRequest(
      apiKey: 'key',
      baseUrl: 'https://example.com/v1/',
      model: 'model',
      messages: [
        {'role': 'user', 'content': 'hi'},
      ],
      stream: true,
      temperature: 0.2,
    );

    expect(
      adapter.buildUri(request),
      Uri.parse('https://example.com/v1/chat/completions'),
    );
    expect(adapter.buildHeaders(request)['Authorization'], 'Bearer key');
    expect(adapter.buildBody(request), containsPair('stream', true));
    expect(adapter.buildBody(request), isNot(contains('max_tokens')));
    expect(adapter.buildBody(request), containsPair('temperature', 0.2));
    expect(
      adapter
          .parseStream(
            'data: {"choices":[{"delta":{"content":"hello"}}]}',
            includeReasoning: false,
          )
          ?.text,
      'hello',
    );
    expect(
      adapter.parseStream(
        'data: {"choices":[{"delta":{"reasoning_content":"think"}}]}',
        includeReasoning: false,
      ),
      isNull,
    );
    expect(
      adapter.parseResponse({
        'choices': [
          {'message': <String, dynamic>{}, 'text': 'fallback'},
        ],
      }).text,
      'fallback',
    );
  });

  test('discovers models and prefers a general chat model', () {
    const adapter = OpenAiCompatibleAdapter();

    expect(
      adapter.buildModelsUri('https://example.com/v1/chat/completions/'),
      Uri.parse('https://example.com/v1/models'),
    );
    expect(
      adapter.parseModels({
        'data': [
          {'id': 'text-embedding-3-small'},
          {'id': 'general-model'},
          {'id': 'alpha-chat'},
          {'id': 'alpha-chat'},
        ],
      }),
      ['text-embedding-3-small', 'general-model', 'alpha-chat'],
    );
    expect(
      selectAutomaticModel([
        'text-embedding-3-small',
        'general-model',
        'alpha-chat',
      ]),
      'alpha-chat',
    );
    expect(
      selectAutomaticModel(['only-embedding-model']),
      'only-embedding-model',
    );
  });

  test('runner loads models with bearer authentication', () async {
    late http.Request captured;
    final runner = AiConversationRunner(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"data":[{"id":"model-a"},{"id":"model-b"}]}',
          200,
        );
      }),
    );

    final models = await runner.listModels(
      apiKey: ' secret ',
      baseUrl: 'https://example.com/v1',
    );

    expect(models, ['model-a', 'model-b']);
    expect(captured.method, 'GET');
    expect(captured.url, Uri.parse('https://example.com/v1/models'));
    expect(captured.headers['Authorization'], 'Bearer secret');
  });

  test('stream times out when the server stops sending data', () async {
    final runner = AiConversationRunner(
      client: _StalledStreamClient(),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      runner
          .run(
            const AiRequest(
              apiKey: 'key',
              baseUrl: 'https://example.com/v1',
              model: 'model',
              messages: [],
              stream: true,
            ),
          )
          .drain<void>(),
      throwsA(isA<TimeoutException>()),
    );
  });
}

final class _StalledStreamClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.periodic(const Duration(seconds: 1), (_) => const []),
      200,
    );
  }
}
