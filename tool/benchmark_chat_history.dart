import 'dart:io';

/// Runs the actual ChatScreen widget rebuild-count probe, not a list simulation.
/// History sizes are 1,000 and 10,000; each receives 100 buffered stream updates.
Future<void> main() async {
  final flutter = Platform.isWindows
      ? '.toolcache/flutter/bin/flutter.bat'
      : '.toolcache/flutter/bin/flutter';
  final watch = Stopwatch()..start();
  final result = await Process.run(File(flutter).absolute.path, [
    'test',
    '--no-pub',
    'test/chat_reasoning_widget_test.dart',
    '--plain-name',
    'message history does not rebuild during draft chunks',
  ], runInShell: Platform.isWindows);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  stdout.writeln('Widget probe wall time: ${watch.elapsedMilliseconds} ms');
  stdout.writeln(
    'This is host Flutter-test measurement, not Android device FPS or peak memory.',
  );
  exitCode = result.exitCode;
}
