import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class JsonFileStore {
  final _queues = <String, Future<void>>{};
  final Object _operationZone = Object();
  final Object _maintenanceZone = Object();
  Future<void> _admission = Future<void>.value();
  final Set<Future<void>> _active = {};
  final ValueNotifier<int> datasetEpochNotifier = ValueNotifier(0);
  int get datasetEpoch => datasetEpochNotifier.value;

  Future<T> runOperation<T>(
    FutureOr<T> Function() action, {
    int? expectedEpoch,
  }) async {
    if (Zone.current[_operationZone] == true) return Future<T>.sync(action);
    final capturedEpoch = expectedEpoch ?? datasetEpoch;
    final admission = _admission;
    final done = Completer<void>();
    _active.add(done.future);
    try {
      await admission;
      if (capturedEpoch != datasetEpoch) {
        throw StateError('数据集已更新，旧操作已取消');
      }
      return await runZoned(
        () => Future<T>.sync(action),
        zoneValues: {_operationZone: true},
      );
    } finally {
      _active.remove(done.future);
      done.complete();
    }
  }

  Future<T> maintain<T>(
    FutureOr<T> Function() action, {
    bool advanceEpoch = false,
  }) async {
    if (Zone.current[_maintenanceZone] == true) {
      if (advanceEpoch) datasetEpochNotifier.value++;
      return Future<T>.sync(action);
    }
    if (Zone.current[_operationZone] == true) throw StateError('维护不能嵌套在写入操作内');
    final prior = _admission;
    final pending = List<Future<void>>.of(_active);
    final gate = Completer<void>();
    _admission = gate.future;
    try {
      await prior;
      await Future.wait(pending);
      if (advanceEpoch) datasetEpochNotifier.value++;
      return await runZoned(
        () => Future<T>.sync(action),
        zoneValues: {_operationZone: true, _maintenanceZone: true},
      );
    } finally {
      gate.complete();
    }
  }

  Future<dynamic> read(
    File file,
    dynamic fallback, {
    bool recoverOnInvalid = false,
  }) => runOperation(
    () => _read(file, fallback, recoverOnInvalid: recoverOnInvalid),
  );

  Future<dynamic> _read(
    File file,
    dynamic fallback, {
    bool recoverOnInvalid = false,
  }) async {
    await waitFor(file);
    if (await recoveryNeeded(file)) await recover(file);
    if (!await file.exists()) return fallback;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      if (recoverOnInvalid) return fallback;
      rethrow;
    }
  }

  Future<void> write(File file, dynamic data, {bool compact = false}) =>
      synchronized(file, () => writeNow(file, data, compact: compact));

  Future<T> synchronized<T>(File file, FutureOr<T> Function() action) =>
      runOperation(() => _synchronized(file, action));

  Future<T> _synchronized<T>(File file, FutureOr<T> Function() action) async {
    final path = file.path;
    final future = (_queues[path] ?? Future<void>.value()).then(
      (_) => Future<T>.sync(action),
    );
    final tail = future.then<void>((_) {}, onError: (_, _) {});
    _queues[path] = tail;
    try {
      return await future;
    } finally {
      if (identical(_queues[path], tail)) unawaited(_queues.remove(path));
    }
  }

  Future<void> waitFor(File file) => _queues[file.path] ?? Future<void>.value();

  Future<void> writeNow(File file, dynamic data, {bool compact = false}) =>
      runOperation(() => _writeNow(file, data, compact: compact));

  Future<void> _writeNow(
    File file,
    dynamic data, {
    bool compact = false,
  }) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temp.writeAsString(
      compact
          ? jsonEncode(data)
          : const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<void> recover(File file) async {
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    if (!await file.exists()) {
      if (await backup.exists() && await _isValidJson(backup)) {
        await backup.rename(file.path);
        if (await temp.exists()) await temp.delete();
        return;
      }
      if (await temp.exists() && await _isValidJson(temp)) {
        await temp.rename(file.path);
      }
      return;
    }
    if (await _isValidJson(file)) {
      if (await backup.exists()) await backup.delete();
      if (await temp.exists()) await temp.delete();
      return;
    }
    if (!await backup.exists() || !await _isValidJson(backup)) return;
    final corrupt = File(
      '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}',
    );
    await file.rename(corrupt.path);
    await backup.rename(file.path);
    if (await temp.exists()) await temp.delete();
  }

  Future<bool> recoveryNeeded(File file) async {
    if (!await file.exists()) return true;
    return await File('${file.path}.tmp').exists() ||
        await File('${file.path}.bak').exists();
  }

  Future<bool> _isValidJson(File file) async {
    try {
      jsonDecode(await file.readAsString());
      return true;
    } on FormatException {
      return false;
    }
  }
}
