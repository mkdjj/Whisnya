import 'dart:async';

import '../qq_exceptions.dart';

typedef OneBotJsonSender = void Function(Map<String, dynamic> value);

class OneBotActionClient {
  OneBotActionClient({
    required this.sendJson,
    this.timeout = const Duration(seconds: 15),
  });

  final OneBotJsonSender sendJson;
  final Duration timeout;
  final _pending = <String, _PendingAction>{};
  var _nextEcho = 0;

  int get pendingCount => _pending.length;

  Future<Map<String, dynamic>> call(
    String action, {
    Map<String, dynamic> params = const {},
  }) {
    final echo = _newEcho();
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      final pending = _pending.remove(echo);
      pending?.completer.completeError(
        OneBotActionException('OneBot action $action 超时。'),
      );
    });
    _pending[echo] = _PendingAction(completer, timer);
    try {
      sendJson({'action': action, 'params': params, 'echo': echo});
    } on Object catch (error, stackTrace) {
      _pending.remove(echo)?.timer.cancel();
      completer.completeError(
        const OneBotConnectionException('OneBot 连接已关闭。'),
        stackTrace,
      );
    }
    return completer.future;
  }

  bool handleResponse(Map<String, dynamic> response) {
    final echo = response['echo'];
    if (echo is! String) return false;
    final pending = _pending.remove(echo);
    if (pending == null) return false;
    pending.timer.cancel();
    if (response['status'] == 'ok' && response['retcode'] == 0) {
      final data = response['data'];
      pending.completer.complete(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      );
    } else {
      final retcode = response['retcode'];
      pending.completer.completeError(
        OneBotActionException('OneBot action 失败，retcode=$retcode。'),
      );
    }
    return true;
  }

  void cancelAll([Object? error]) {
    final reason = error ?? const OneBotConnectionException('OneBot 连接已关闭。');
    for (final pending in _pending.values) {
      pending.timer.cancel();
      pending.completer.completeError(reason);
    }
    _pending.clear();
  }

  String _newEcho() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_nextEcho++}';
}

class _PendingAction {
  const _PendingAction(this.completer, this.timer);
  final Completer<Map<String, dynamic>> completer;
  final Timer timer;
}
