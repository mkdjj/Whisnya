import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/storage/backup_files.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_matrix_');
  });
  tearDown(() => root.delete(recursive: true));
  Future<File> zip(List<ArchiveFile> files) async {
    final file = File('${root.path}/input.zip');
    final archive = Archive();
    for (final entry in files) {
      archive.addFile(entry);
    }
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }

  Future<void> extract(List<ArchiveFile> files) async {
    final staging = await Directory('${root.path}/stage').create();
    await extractBackupFile(await zip(files), staging);
  }

  for (final names in [
    ['../escape'],
    ['/absolute'],
    ['C:/drive'],
    ['a', 'a/b'],
    ['A.json', 'a.json'],
    ['x/./a', 'x/a'],
  ]) {
    test('rejects unsafe/conflicting paths $names', () async {
      await expectLater(
        extract([for (final name in names) ArchiveFile.string(name, 'x')]),
        throwsFormatException,
      );
    });
  }
  test('detects CRC corruption independently of archive verify flag', () async {
    final file = await zip([ArchiveFile.string('a', 'payload')]);
    final bytes = await file.readAsBytes();
    for (var i = 0; i < bytes.length - 20; i++) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 1 &&
          bytes[i + 3] == 2) {
        bytes[i + 16] ^= 1;
        break;
      }
    }
    await file.writeAsBytes(bytes);
    await expectLater(
      extractBackupFile(file, await Directory('${root.path}/stage').create()),
      throwsFormatException,
    );
  });
  test('rejects typed settings errors before activation', () async {
    await File(
      '${root.path}/backup_manifest.json',
    ).writeAsString('{"format":1}');
    await File(
      '${root.path}/settings.json',
    ).writeAsString('{"showReasoningContent":"bad"}');
    await expectLater(validateBackupFiles(root), throwsFormatException);
  });
  test('rejects symbolic link entries', () async {
    await expectLater(
      extract([ArchiveFile.string('link', '../outside')..mode = 0xa1ff]),
      throwsFormatException,
    );
  });
  test(
    'hash, schema and session mappings validated before activation',
    () async {
      final manifest = File('${root.path}/backup_manifest.json');
      await manifest.writeAsString(
        jsonEncode({'format': 1, 'schemaVersion': 99}),
      );
      await expectLater(validateBackupFiles(root), throwsFormatException);
      await File('${root.path}/characters.json').writeAsString('[]');
      await manifest.writeAsString(
        jsonEncode({
          'format': 1,
          'schemaVersion': 3,
          'files': [
            {'path': 'characters.json', 'bytes': 2, 'sha256': 'bad'},
          ],
        }),
      );
      await expectLater(validateBackupFiles(root), throwsFormatException);
      await manifest.writeAsString(
        jsonEncode({'format': 1, 'schemaVersion': 2}),
      );
      await File('${root.path}/characters.json').writeAsString('[{"id":"a"}]');
      await File(
        '${root.path}/chat_sessions.json',
      ).writeAsString('[{"id":"s","characterId":"a"}]');
      await Directory('${root.path}/chats').create();
      await File(
        '${root.path}/chats/s.json',
      ).writeAsString('{"sessionId":"s","characterId":"b","messages":[]}');
      await expectLater(validateBackupFiles(root), throwsFormatException);
      await File(
        '${root.path}/chats/s.json',
      ).writeAsString('{"sessionId":"s","characterId":"a","messages":[]}');
      await validateBackupFiles(root);
    },
  );
}
