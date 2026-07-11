import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/stream_text_buffer.dart';

void main() {
  test('coalesces chunks and flushes the final pending text', () async {
    final flushed = <String>[];
    final buffer = StreamTextBuffer(
      interval: const Duration(milliseconds: 30),
      onFlush: flushed.add,
    );

    buffer.add('a');
    buffer.add('b');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(flushed, ['ab']);

    buffer.add('c');
    buffer.flush();
    expect(flushed, ['ab', 'c']);
    buffer.dispose();
  });
}
