import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/safe_zip.dart';

void main() {
  test('validates archive paths and size limits before extraction', () {
    expect(
      decodeSafeZip(
        _zip({
          'folder/data.json': [1, 2],
        }),
      ).files,
      hasLength(1),
    );

    for (final name in ['../escape', '/absolute', r'C:\absolute']) {
      expect(
        () => decodeSafeZip(
          _zip({
            name: [1],
          }),
        ),
        throwsA(isA<SafeZipException>()),
      );
    }
    expect(
      () => decodeSafeZip(
        _zip({
          'large': [1, 2, 3],
        }),
        maxFileBytes: 2,
      ),
      throwsA(isA<SafeZipException>()),
    );
    expect(
      () => decodeSafeZip(
        _zip({
          'one': [1, 2],
          'two': [3, 4],
        }),
        maxExpandedBytes: 3,
      ),
      throwsA(isA<SafeZipException>()),
    );
  });
}

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
