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
}
