import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:whisnya/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streams chat completion deltas', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.first.then((request) async {
        final body = await utf8.decoder.bind(request).join();
        expect(body, contains('"stream":true'));
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: {"choices":[{"delta":{"content":"hel"}}]}\n\n')
          ..write('data: {"choices":[{"delta":{"content":"lo"}}]}\n\n')
          ..write('data: [DONE]\n\n');
        await request.response.close();
      }),
    );

    final text = await AiService()
        .streamMessage(
          apiKey: 'key',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'model',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        )
        .join();

    expect(text, 'hello');
  });

  test('ignores reasoning deltas by default', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.first.then((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(
            'data: {"choices":[{"delta":{"reasoning_content":"think"}}]}\n\n',
          )
          ..write('data: {"choices":[{"delta":{"content":"answer"}}]}\n\n')
          ..write('data: [DONE]\n\n');
        await request.response.close();
      }),
    );

    final text = await AiService()
        .streamMessage(
          apiKey: 'key',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'model',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        )
        .join();

    expect(text, 'answer');
  });

  test('streams reasoning deltas when requested', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.first.then((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(
            'data: {"choices":[{"delta":{"reasoning_content":"think"}}]}\n\n',
          )
          ..write('data: {"choices":[{"delta":{"content":"answer"}}]}\n\n')
          ..write('data: [DONE]\n\n');
        await request.response.close();
      }),
    );

    final text = await AiService()
        .streamMessage(
          apiKey: 'key',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'model',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          includeReasoning: true,
        )
        .join();

    expect(text, 'thinkanswer');
  });

  test('parses final stream usage and sends optional max tokens', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.first.then((request) async {
        final body = await utf8.decoder.bind(request).join();
        expect(body, contains('"max_tokens":800'));
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n')
          ..write(
            'data: {"choices":[],"usage":{"prompt_tokens":100,'
            '"completion_tokens":20,"total_tokens":120,'
            '"prompt_cache_hit_tokens":75,'
            '"prompt_cache_miss_tokens":25}}\n\n',
          )
          ..write('data: [DONE]\n\n');
        await request.response.close();
      }),
    );
    AiUsage? usage;

    final text = await AiService()
        .streamMessage(
          apiKey: 'key',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'model',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          maxTokens: 800,
          onUsage: (value) => usage = value,
        )
        .join();

    expect(text, 'ok');
    expect(usage?.cacheHitTokens, 75);
    expect(usage?.cacheMissTokens, 25);
  });
}
