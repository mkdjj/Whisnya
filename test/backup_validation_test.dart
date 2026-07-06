import 'dart:convert';
import 'dart:io';

import 'package:whisnya/services/local_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a valid backup directory', () async {
    final directory = await Directory.systemTemp.createTemp('whisnya_backup_');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    await File(
      '${directory.path}${Platform.pathSeparator}backup_manifest.json',
    ).writeAsString(jsonEncode({'format': 1}));
    await File(
      '${directory.path}${Platform.pathSeparator}characters.json',
    ).writeAsString(jsonEncode([]));

    await validateBackupDirectory(directory);
  });

  test('rejects a backup directory with invalid json', () async {
    final directory = await Directory.systemTemp.createTemp('whisnya_backup_');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    await File(
      '${directory.path}${Platform.pathSeparator}backup_manifest.json',
    ).writeAsString(jsonEncode({'format': 1}));
    await File(
      '${directory.path}${Platform.pathSeparator}characters.json',
    ).writeAsString('{');

    await expectLater(
      validateBackupDirectory(directory),
      throwsA(isA<StorageException>()),
    );
  });
}
