import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/storage/backup_files.dart';

void main() {
  test(
    'file stream ZIP roundtrip with chunked source',
    () async {
      final root = await Directory.systemTemp.createTemp('backup_stream_');
      addTearDown(() => root.delete(recursive: true));
      final source = await Directory('${root.path}/source').create();
      final file = File('${source.path}/novel.txt');
      final sink = file.openWrite();
      final chunk = Uint8List(64 * 1024);
      for (var i = 0; i < chunk.length; i++) {
        chunk[i] = i % 251;
      }
      const megabytes = int.fromEnvironment('BACKUP_TEST_MB', defaultValue: 8);
      for (var i = 0; i < megabytes * 16; i++) {
        sink.add(chunk);
        await sink.flush();
      }
      await sink.close();
      final before = ProcessInfo.currentRss;
      final zip = File('${root.path}/backup.zip');
      await zipBackupDirectory(source, zip);
      final target = await Directory('${root.path}/target').create();
      await extractBackupFile(zip, target);
      expect(
        await backupHash(File('${target.path}/novel.txt')),
        await backupHash(file),
      );
      // Diagnostic only: process peak includes Flutter test engine and prior tests.
      // ignore: avoid_print
      print(
        'backup sample=${megabytes}MiB beforeRss=$before currentRss=${ProcessInfo.currentRss} maxRss=${ProcessInfo.maxRss} zipBytes=${await zip.length()}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
