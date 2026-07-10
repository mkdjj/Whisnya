import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/theater_streaming_parser.dart';

void main() {
  test('parses speakers and content across chunk boundaries', () {
    final parser = TheaterStreamingParser();
    final events = <TheaterStreamEvent>[
      ...parser.addChunk('<<<WhisnyaSpea'),
      ...parser.addChunk('ker:阿璃>>>\n你好 <普通内容>'),
      ...parser.addChunk('\n<<<WhisnyaSpeaker:Bob>>>\nHello'),
      ...parser.finish(),
    ];

    expect(events.whereType<TheaterSpeakerStarted>().map((e) => e.speaker), [
      '阿璃',
      'Bob',
    ]);
    expect(
      events.whereType<TheaterMessageCompleted>().map((e) => e.content.trim()),
      ['你好 <普通内容>', 'Hello'],
    );
  });

  test('produces no messages when the speaker marker is missing', () {
    final parser = TheaterStreamingParser();
    final events = [...parser.addChunk('plain text only'), ...parser.finish()];

    expect(events.whereType<TheaterSpeakerStarted>(), isEmpty);
    expect(events.whereType<TheaterMessageCompleted>(), isEmpty);
  });

  test('completes an empty reply before starting the next speaker', () {
    final parser = TheaterStreamingParser();
    final events = [
      ...parser.addChunk('<<<WhisnyaSpeaker:A>>>\n<<<WhisnyaSpeaker:B>>>\n内容'),
      ...parser.finish(),
    ];

    expect(
      events.whereType<TheaterMessageCompleted>().map((e) => e.content.trim()),
      ['', '内容'],
    );
  });

  test('keeps exact speaker names for caller-side validation', () {
    final parser = TheaterStreamingParser();
    final events = [
      ...parser.addChunk('<<<WhisnyaSpeaker:“A-1”>>>\nHi'),
      ...parser.finish(),
    ];

    expect(events.whereType<TheaterSpeakerStarted>().single.speaker, '“A-1”');
  });

  test('does not expose a partial marker as content', () {
    final parser = TheaterStreamingParser();
    final first = parser.addChunk(
      '<<<WhisnyaSpeaker:A>>>\nhello<<<WhisnyaSpea',
    );
    final second = parser.addChunk('ker:B>>>\nworld');
    final completed = [...first, ...second, ...parser.finish()]
        .whereType<TheaterMessageCompleted>()
        .map((e) => e.content.trim())
        .toList();

    expect(completed, ['hello', 'world']);
  });
}
