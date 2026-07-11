import 'package:flutter_test/flutter_test.dart';
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
      maxTokens: 800,
    );

    expect(
      adapter.buildUri(request),
      Uri.parse('https://example.com/v1/chat/completions'),
    );
    expect(adapter.buildHeaders(request)['Authorization'], 'Bearer key');
    expect(adapter.buildBody(request), containsPair('stream', true));
    expect(adapter.buildBody(request), containsPair('max_tokens', 800));
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
}
