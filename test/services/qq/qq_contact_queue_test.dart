import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/qq/qq_contact_queue.dart';

void main() {
  test('runs the same contact strictly in sequence', () async {
    final queue = QqContactQueue(maxConcurrent: 2);
    final firstGate = Completer<void>();
    final events = <String>[];
    final first = queue.run('a', () async {
      events.add('first-start');
      await firstGate.future;
      events.add('first-end');
    });
    final second = queue.run('a', () async => events.add('second'));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    firstGate.complete();
    await Future.wait([first, second]);
    expect(events, ['first-start', 'first-end', 'second']);
  });

  test(
    'allows different contacts but never exceeds global concurrency two',
    () async {
      final queue = QqContactQueue(maxConcurrent: 2);
      final gate = Completer<void>();
      var active = 0;
      var peak = 0;
      Future<void> task() async {
        active++;
        peak = active > peak ? active : peak;
        await gate.future;
        active--;
      }

      final futures = [
        queue.run('a', task),
        queue.run('b', task),
        queue.run('c', task),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(peak, 2);
      gate.complete();
      await Future.wait(futures);
    },
  );
}
