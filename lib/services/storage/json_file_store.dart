import 'dart:async';
import 'dart:convert';
import 'dart:io';

class JsonFileStore {
  final _queues = <String, Future<void>>{};

  Future<dynamic> read(
    File file,
    dynamic fallback, {
    bool recoverOnInvalid = false,
  }) async {
    await waitFor(file);
    await recover(file);
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

  Future<T> synchronized<T>(File file, FutureOr<T> Function() action) async {
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

  Future<T> update<T>(
    File file,
    FutureOr<T> Function(dynamic current) action,
  ) => synchronized(file, () async {
    await recover(file);
    final current = await file.exists()
        ? jsonDecode(await file.readAsString())
        : null;
    return action(current);
  });

  Future<void> waitFor(File file) => _queues[file.path] ?? Future<void>.value();

  Future<void> writeNow(File file, dynamic data, {bool compact = false}) async {
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

  Future<bool> _isValidJson(File file) async {
    try {
      jsonDecode(await file.readAsString());
      return true;
    } on FormatException {
      return false;
    }
  }
}
