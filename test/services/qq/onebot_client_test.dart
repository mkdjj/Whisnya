import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/qq/onebot/onebot_action_client.dart';
import 'package:whisnya/services/qq/onebot/onebot_client.dart';
import 'package:whisnya/services/qq/onebot/onebot_reconnect_policy.dart';
import 'package:whisnya/services/qq/qq_exceptions.dart';

void main() {
  test(
    'action client maps echo responses and times out unanswered actions',
    () async {
      final sent = <Map<String, dynamic>>[];
      final actions = OneBotActionClient(
        sendJson: sent.add,
        timeout: const Duration(milliseconds: 20),
      );
      final future = actions.call('get_login_info');
      expect(sent.single['echo'], isNotEmpty);
      actions.handleResponse({
        'status': 'ok',
        'retcode': 0,
        'echo': sent.single['echo'],
        'data': {'user_id': '123'},
      });
      expect((await future)['user_id'], '123');

      await expectLater(
        actions.call('never_returns'),
        throwsA(isA<OneBotActionException>()),
      );
    },
  );

  test('reconnect policy follows 1 2 5 10 30 seconds and resets', () {
    final policy = OneBotReconnectPolicy();
    expect(
      [for (var i = 0; i < 7; i++) policy.nextDelay().inSeconds],
      [1, 2, 5, 10, 30, 30, 30],
    );
    policy.reset();
    expect(policy.nextDelay(), const Duration(seconds: 1));
  });

  test(
    'websocket client authenticates, reads login and sends string qq id',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      final authorization = Completer<String?>();
      final serverDone = Completer<void>();
      unawaited(() async {
        final request = await server.first;
        authorization.complete(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final raw in socket) {
          final value = jsonDecode(raw as String) as Map<String, dynamic>;
          requests.add(value);
          final action = value['action'];
          if (action == 'get_login_info') {
            socket.add(
              jsonEncode({
                'status': 'ok',
                'retcode': 0,
                'echo': value['echo'],
                'data': {'user_id': '900719925474099312345', 'nickname': 'Bot'},
              }),
            );
          } else if (action == 'send_private_msg') {
            socket.add(
              jsonEncode({
                'status': 'ok',
                'retcode': 0,
                'echo': value['echo'],
                'data': {'message_id': 'm1'},
              }),
            );
          }
        }
        await socket.close();
        serverDone.complete();
      }());

      final client = OneBotClient(actionTimeout: const Duration(seconds: 1));
      final login = await client.connect(
        Uri.parse('ws://127.0.0.1:${server.port}'),
        accessToken: 'token-value',
      );
      expect(login.accountId, '900719925474099312345');
      expect(login.nickname, 'Bot');
      expect(await authorization.future, 'Bearer token-value');

      await client.sendPrivateMessage('900719925474099399999', 'hello');
      final send = requests.firstWhere(
        (request) => request['action'] == 'send_private_msg',
      );
      final params = send['params'] as Map<String, dynamic>;
      expect(params['user_id'], '900719925474099399999');
      await client.dispose();
      await server.close(force: true);
      await serverDone.future.timeout(const Duration(seconds: 1));
    },
  );

  test('closing a socket cancels all pending actions', () async {
    final sent = <Map<String, dynamic>>[];
    final actions = OneBotActionClient(sendJson: sent.add);
    final pending = actions.call('get_login_info');
    actions.cancelAll(const OneBotConnectionException('closed'));
    await expectLater(pending, throwsA(isA<OneBotConnectionException>()));
    expect(actions.pendingCount, 0);
  });
}
