import 'dart:async';
import 'dart:io';

class SessionOperationToken {
  const SessionOperationToken(this.sessionId, this.epoch, this.revision);
  final String sessionId;
  final int epoch;
  final int revision;
}

/// Business ordering, above individual JSON file locks. Never hold this over AI IO.
class SessionOperationCoordinator {
  SessionOperationCoordinator._();
  static final _roots = <String, SessionOperationCoordinator>{};
  factory SessionOperationCoordinator.forRoot(Directory root) =>
      _roots.putIfAbsent(root.absolute.path, SessionOperationCoordinator._);
  final _queues = <String, Future<void>>{};
  final _revisions = <String, int>{};
  int revision(String id) => _revisions[id] ?? 0;
  void invalidate(String id) => _revisions[id] = revision(id) + 1;
  Future<T> run<T>(String id, Future<T> Function() action) async {
    final future = (_queues[id] ?? Future<void>.value()).then((_) => action());
    final tail = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[id] = tail;
    try {
      return await future;
    } finally {
      if (identical(_queues[id], tail)) unawaited(_queues.remove(id));
    }
  }
}
