import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whisnya/services/bubble_import/bubble_import_models.dart';
import 'package:whisnya/services/bubble_import/bubble_package_scanner.dart';

void main() {
  final scanner = BubblePackageScanner();

  test('scans supported files in nested ZIP directories', () async {
    final png = img.encodePng(img.Image(width: 40, height: 32, numChannels: 4));
    final scan = await scanner.scan(
      bytes: _zip({
        'pack/manifest.json': Uint8List.fromList('{}'.codeUnits),
        'pack/images/chat_left.png': png,
        'pack/readme.txt': Uint8List.fromList('ignored'.codeUnits),
      }),
      originalFileName: r'C:\Downloads\stars.zip',
    );
    addTearDown(scan.dispose);

    expect(scan.originalFileName, 'stars.zip');
    expect(scan.files.map((file) => file.relativePath), [
      'pack/manifest.json',
      'pack/images/chat_left.png',
    ]);
    expect(scan.imageCount, 1);
    expect(scan.configCount, 1);
    expect(scan.files.last.width, 40);
    expect(scan.files.last.height, 32);
    expect(await scan.files.last.file.exists(), isTrue);
    expect(scan.warnings.single, contains('readme.txt'));
  });

  for (final unsafe in ['../evil.png', '/absolute.png', r'C:\escape.png']) {
    test('rejects unsafe ZIP path $unsafe', () async {
      await expectLater(
        scanner.scan(
          bytes: _zip({
            unsafe: Uint8List.fromList([1]),
          }),
          originalFileName: 'unsafe.zip',
        ),
        throwsA(isA<BubblePackageException>()),
      );
    });
  }

  test('rejects ZIP symbolic links', () async {
    await expectLater(
      scanner.scan(
        bytes: base64Decode(
          'UEsDBBQAAAAAAAAAIQATwYhIDgAAAA4AAAAIAAAAcm9sZS5wbmcuLi9vdXRzaWRlLnBuZ1BLAQIUAxQAAAAAAAAAIQATwYhIDgAAAA4AAAAIAAAAAAAAAAAAAAD/oQAAAAByb2xlLnBuZ1BLBQYAAAAAAQABADYAAAA0AAAAAAA=',
        ),
        originalFileName: 'link.zip',
      ),
      throwsA(isA<BubblePackageException>()),
    );
  });

  test(
    'rejects a file larger than twenty MiB',
    () async {
      final bytes = Uint8List(BubblePackageScanner.maxFileBytes + 1);

      await expectLater(
        scanner.scan(
          bytes: _zip({'huge.png': bytes}),
          originalFileName: 'huge.zip',
        ),
        throwsA(isA<BubblePackageException>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('rejects packages without supported resources', () async {
    await expectLater(
      scanner.scan(
        bytes: _zip({
          'readme.txt': Uint8List.fromList('nothing'.codeUnits),
          'script.js': Uint8List.fromList('never run'.codeUnits),
        }),
        originalFileName: 'empty.zip',
      ),
      throwsA(isA<BubblePackageException>()),
    );
  });

  test('reports a corrupt supported image as a visible warning', () async {
    final scan = await scanner.scan(
      bytes: _zip({
        'broken.png': Uint8List.fromList([1, 2, 3]),
        'manifest.json': Uint8List.fromList('{}'.codeUnits),
      }),
      originalFileName: 'broken.zip',
    );
    addTearDown(scan.dispose);

    expect(scan.warnings, contains(contains('broken.png')));
  });
}

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
