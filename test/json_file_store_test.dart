import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/storage/json_file_store.dart';

void main() {
  late Directory directory;
  late JsonFileStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('json_store_');
    store = JsonFileStore();
  });
  tearDown(() => directory.delete(recursive: true));

  File file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  test('serializes same-file writes and keeps valid JSON', () async {
    final target = file('same.json');
    await Future.wait([
      for (var i = 0; i < 20; i++) store.write(target, {'value': i}),
    ]);

    expect(jsonDecode(await target.readAsString()), {'value': 19});
  });

  test('a failed action does not block the next write', () async {
    final target = file('queue.json');
    await expectLater(
      store.synchronized<void>(target, () => throw StateError('failed')),
      throwsStateError,
    );

    await store.write(target, {'ok': true});
    expect(await store.read(target, null), {'ok': true});
  });

  test('recovers valid tmp when the main file is absent', () async {
    final target = file('tmp.json');
    await File('${target.path}.tmp').writeAsString('{"tmp":true}');

    expect(await store.read(target, null), {'tmp': true});
    expect(await File('${target.path}.tmp').exists(), isFalse);
  });

  test('recovers bak when the main file is absent', () async {
    final target = file('bak.json');
    await File('${target.path}.bak').writeAsString('{"bak":true}');

    expect(await store.read(target, null), {'bak': true});
  });

  test('recovers valid bak when the main file is corrupt', () async {
    final target = file('corrupt.json');
    await target.writeAsString('{broken');
    await File('${target.path}.bak').writeAsString('{"bak":true}');

    expect(await store.read(target, null), {'bak': true});
    expect(
      directory.listSync().where((item) => item.path.contains('.corrupt.')),
      isNotEmpty,
    );
  });

  test('skips recovery inspection for a normal main file', () async {
    final target = file('normal.json');
    await target.writeAsString('{"value":1}');

    expect(await store.recoveryNeeded(target), isFalse);
    await File('${target.path}.bak').writeAsString('{"value":0}');
    expect(await store.recoveryNeeded(target), isTrue);
  });

  test('supports compact and formatted JSON', () async {
    final compact = file('compact.json');
    final formatted = file('formatted.json');
    await store.write(compact, {'value': 1}, compact: true);
    await store.write(formatted, {'value': 1});

    expect(await compact.readAsString(), isNot(contains('\n')));
    expect(await formatted.readAsString(), contains('\n'));
  });
}
