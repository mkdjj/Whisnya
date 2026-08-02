import 'dart:async';
import 'dart:collection';

class QqContactQueue {
  QqContactQueue({this.maxConcurrent = 2}) : assert(maxConcurrent > 0);

  final int maxConcurrent;
  final _contactTails = <String, Future<void>>{};
  final _waiting = Queue<Completer<void>>();
  var _active = 0;

  int get active => _active;
  int get waiting => _waiting.length;

  Future<T> run<T>(String contactId, FutureOr<T> Function() action) {
    final previous = _contactTails[contactId] ?? Future<void>.value();
    final result = previous.then((_) async {
      await _acquire();
      try {
        return await Future<T>.sync(action);
      } finally {
        _release();
      }
    });
    final tail = result.then<void>((_) {}, onError: (_, _) {});
    _contactTails[contactId] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_contactTails[contactId], tail)) {
          unawaited(_contactTails.remove(contactId));
        }
      }),
    );
    return result;
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
      return;
    }
    _active--;
  }
}
