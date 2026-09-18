import '../../models/unified_qq_message.dart';

class QqMessageDeduplicator {
  QqMessageDeduplicator({
    this.maximumIds = 500,
    this.ttl = const Duration(minutes: 30),
  });

  final int maximumIds;
  final Duration ttl;
  final _ids = <String, DateTime>{};

  int get size => _ids.length;

  bool isDuplicate(UnifiedQqMessage message, {DateTime? now}) {
    final current = now ?? DateTime.now();
    _prune(current);
    final previous = _ids[message.messageId];
    if (previous != null && current.difference(previous) <= ttl) return true;

    _remember(message.messageId, current);
    return false;
  }

  void _remember(String id, DateTime now) {
    _ids.remove(id);
    _ids[id] = now;
    while (_ids.length > maximumIds) {
      _ids.remove(_ids.keys.first);
    }
  }

  void _prune(DateTime now) {
    _ids.removeWhere((_, time) => now.difference(time) > ttl);
  }
}
