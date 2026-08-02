import 'dart:async';

import '../../models/unified_qq_message.dart';

typedef QqDebouncedMessageCallback =
    FutureOr<void> Function(UnifiedQqMessage message);

class QqMessageDebouncer {
  QqMessageDebouncer({
    required this.mergeWindow,
    this.maximumMessages = 10,
    this.maximumCharacters = 4000,
  });

  final Duration mergeWindow;
  final int maximumMessages;
  final int maximumCharacters;
  final _pending = <String, _PendingBatch>{};

  void add(
    UnifiedQqMessage message,
    QqDebouncedMessageCallback onReady, {
    bool isCommand = false,
  }) {
    final key = message.externalUserId;
    if (isCommand || mergeWindow == Duration.zero) {
      _flush(key);
      unawaited(Future.sync(() => onReady(message)));
      return;
    }
    final batch = _pending.putIfAbsent(
      key,
      () => _PendingBatch(onReady: onReady),
    );
    batch.messages.add(message);
    if (batch.messages.length > maximumMessages) {
      batch.messages.removeAt(0);
    }
    batch.timer?.cancel();
    batch.timer = Timer(mergeWindow, () => _flush(key));
  }

  void _flush(String key) {
    final batch = _pending.remove(key);
    if (batch == null || batch.messages.isEmpty) return;
    batch.timer?.cancel();
    final latest = batch.messages.last;
    final combined = batch.messages.map((message) => message.text).join('\n');
    final runes = combined.runes.toList();
    final text = String.fromCharCodes(
      runes.length <= maximumCharacters ? runes : runes.take(maximumCharacters),
    );
    unawaited(Future.sync(() => batch.onReady(latest.copyWith(text: text))));
  }

  void flush(String externalUserId) => _flush(externalUserId);

  void dispose() {
    for (final batch in _pending.values) {
      batch.timer?.cancel();
    }
    _pending.clear();
  }
}

class _PendingBatch {
  _PendingBatch({required this.onReady});
  final QqDebouncedMessageCallback onReady;
  final messages = <UnifiedQqMessage>[];
  Timer? timer;
}
