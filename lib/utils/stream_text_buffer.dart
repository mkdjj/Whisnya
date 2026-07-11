import 'dart:async';

class StreamTextBuffer {
  StreamTextBuffer({
    required this.onFlush,
    this.interval = const Duration(milliseconds: 40),
  });

  final void Function(String text) onFlush;
  final Duration interval;
  final _pending = StringBuffer();
  Timer? _timer;

  void add(String text) {
    if (text.isEmpty) return;
    _pending.write(text);
    _timer ??= Timer(interval, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    onFlush(text);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
