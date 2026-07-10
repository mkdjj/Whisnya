sealed class TheaterStreamEvent {
  const TheaterStreamEvent();
}

class TheaterSpeakerStarted extends TheaterStreamEvent {
  const TheaterSpeakerStarted(this.speaker);

  final String speaker;
}

class TheaterContentDelta extends TheaterStreamEvent {
  const TheaterContentDelta(this.speaker, this.delta);

  final String speaker;
  final String delta;
}

class TheaterMessageCompleted extends TheaterStreamEvent {
  const TheaterMessageCompleted(this.speaker, this.content);

  final String speaker;
  final String content;
}

class TheaterStreamingParser {
  static const markerPrefix = '<<<WhisnyaSpeaker:';
  static const markerSuffix = '>>>';

  var _buffer = '';
  String? _speaker;
  var _content = '';

  List<TheaterStreamEvent> addChunk(String chunk) {
    _buffer += chunk;
    return _drain(finishing: false);
  }

  List<TheaterStreamEvent> finish() {
    return _drain(finishing: true);
  }

  List<TheaterStreamEvent> _drain({required bool finishing}) {
    final events = <TheaterStreamEvent>[];
    while (_buffer.isNotEmpty) {
      final markerStart = _buffer.indexOf(markerPrefix);
      if (markerStart >= 0) {
        final markerEnd = _buffer.indexOf(
          markerSuffix,
          markerStart + markerPrefix.length,
        );
        if (markerStart > 0) {
          _emitDelta(_buffer.substring(0, markerStart), events);
          _buffer = _buffer.substring(markerStart);
          continue;
        }
        if (markerEnd < 0) break;

        _complete(events);
        final speaker = _buffer
            .substring(markerPrefix.length, markerEnd)
            .trim();
        _speaker = speaker;
        _content = '';
        events.add(TheaterSpeakerStarted(speaker));
        _buffer = _buffer.substring(markerEnd + markerSuffix.length);
        if (_buffer.startsWith('\r\n')) {
          _buffer = _buffer.substring(2);
        } else if (_buffer.startsWith('\n')) {
          _buffer = _buffer.substring(1);
        }
        continue;
      }

      final safeLength = finishing
          ? _buffer.length
          : _buffer.length - _partialMarkerLength(_buffer);
      if (safeLength > 0) {
        _emitDelta(_buffer.substring(0, safeLength), events);
        _buffer = _buffer.substring(safeLength);
      }
      break;
    }

    if (finishing) {
      if (_buffer.isNotEmpty) {
        _emitDelta(_buffer, events);
        _buffer = '';
      }
      _complete(events);
    }
    return events;
  }

  void _emitDelta(String text, List<TheaterStreamEvent> events) {
    final speaker = _speaker;
    if (speaker == null || text.isEmpty) return;
    _content += text;
    events.add(TheaterContentDelta(speaker, text));
  }

  void _complete(List<TheaterStreamEvent> events) {
    final speaker = _speaker;
    if (speaker == null) return;
    events.add(TheaterMessageCompleted(speaker, _content));
    _speaker = null;
    _content = '';
  }

  int _partialMarkerLength(String text) {
    final max = text.length < markerPrefix.length
        ? text.length
        : markerPrefix.length - 1;
    for (var length = max; length > 0; length--) {
      if (text.endsWith(markerPrefix.substring(0, length))) return length;
    }
    return 0;
  }
}
