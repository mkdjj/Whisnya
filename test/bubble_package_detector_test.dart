import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whisnya/services/bubble_import/bubble_import_models.dart';
import 'package:whisnya/services/bubble_import/bubble_package_detector.dart';
import 'package:whisnya/services/bubble_import/bubble_package_scanner.dart';

void main() {
  final scanner = BubblePackageScanner();
  final detector = BubblePackageDetector();
  final png = img.encodePng(img.Image(width: 24, height: 18, numChannels: 4));

  test('valid Whisnya manifest is exact', () async {
    final scan = await _scan(scanner, {
      'pack/manifest.json': _json({
        'format': 'whisnya-bubble',
        'formatVersion': 1,
        'name': '星星',
        'roleImage': 'images/role.png',
        'userImage': 'images/user.png',
        'stretchRegion': {'left': .2, 'top': .3, 'right': .8, 'bottom': .7},
        'textPadding': {'left': 10, 'top': 8, 'right': 10, 'bottom': 8},
      }),
      'pack/images/role.png': png,
      'pack/images/user.png': png,
    });
    addTearDown(scan.dispose);

    final result = await detector.detect(scan);

    expect(result.level, BubblePackageRecognitionLevel.exact);
    expect(result.detectedFormat, 'whisnya-manifest-v1');
    expect(result.rolePath, 'pack/images/role.png');
    expect(result.userPath, 'pack/images/user.png');
    expect(result.stretchRegion!.left, .2);
    expect(result.reasons, contains('识别到 Whisnya 标准 manifest v1'));
  });

  test('invalid Whisnya manifest version fails', () async {
    final scan = await _scan(scanner, {
      'manifest.json': _json({
        'format': 'whisnya-bubble',
        'formatVersion': 2,
        'roleImage': 'role.png',
      }),
      'role.png': png,
    });
    addTearDown(scan.dispose);

    final result = await detector.detect(scan);

    expect(result.level, BubblePackageRecognitionLevel.failed);
    expect(result.reasons.join(), contains('版本'));
  });

  test('manifest missing role image fails', () async {
    final scan = await _scan(scanner, {
      'manifest.json': _json({
        'format': 'whisnya-bubble',
        'formatVersion': 1,
        'roleImage': 'missing.png',
      }),
    });
    addTearDown(scan.dispose);

    final result = await detector.detect(scan);

    expect(result.level, BubblePackageRecognitionLevel.failed);
    expect(result.reasons.join(), contains('roleImage'));
  });

  test('manifest without user image is partial', () async {
    final scan = await _scan(scanner, {
      'manifest.json': _json({
        'format': 'whisnya-bubble',
        'formatVersion': 1,
        'roleImage': 'role.png',
      }),
      'role.png': png,
    });
    addTearDown(scan.dispose);

    final result = await detector.detect(scan);

    expect(result.level, BubblePackageRecognitionLevel.partial);
    expect(result.rolePath, 'role.png');
    expect(result.userPath, isNull);
  });

  for (final names in [
    ('chat_left.png', 'chat_right.png'),
    ('incoming.png', 'outgoing.png'),
    ('receive.png', 'send.png'),
    ('对方.png', '我的.png'),
  ]) {
    test('pairs role and user filename keywords ${names.$1}', () async {
      final scan = await _scan(scanner, {names.$1: png, names.$2: png});
      addTearDown(scan.dispose);

      final result = await detector.detect(scan);

      expect(result.level, BubblePackageRecognitionLevel.probable);
      expect(result.rolePath, names.$1);
      expect(result.userPath, names.$2);
      expect(result.reasons.join(), contains('文件名'));
    });
  }

  test('mirror similarity is high for a true pair and low otherwise', () {
    final first = img.Image(width: 20, height: 16, numChannels: 4);
    img.fillRect(
      first,
      x1: 1,
      y1: 2,
      x2: 13,
      y2: 12,
      color: img.ColorRgba8(20, 80, 220, 255),
    );
    first.setPixelRgba(2, 3, 255, 0, 0, 255);
    final mirrored = img.flipHorizontal(first.clone());
    final unrelated = img.Image(width: 20, height: 16, numChannels: 4);
    img.fill(unrelated, color: img.ColorRgba8(255, 220, 10, 255));

    expect(
      detector.mirrorSimilarity(
        Uint8List.fromList(img.encodePng(first)),
        Uint8List.fromList(img.encodePng(mirrored)),
      ),
      greaterThan(.92),
    );
    expect(
      detector.mirrorSimilarity(
        Uint8List.fromList(img.encodePng(first)),
        Uint8List.fromList(img.encodePng(unrelated)),
      ),
      lessThan(.8),
    );
  });

  test('detector warnings do not repeat scanner warnings', () async {
    final scan = await _scan(scanner, {
      'role.png': png,
      'readme.txt': utf8.encode('ignored'),
    });
    addTearDown(scan.dispose);

    final result = await detector.detect(scan);

    expect(scan.warnings, isNotEmpty);
    expect(result.warnings, isNot(contains(scan.warnings.single)));
  });
}

Future<BubblePackageScanResult> _scan(
  BubblePackageScanner scanner,
  Map<String, List<int>> files,
) => scanner.scan(bytes: _zip(files), originalFileName: 'bubble.zip');

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _json(Map<String, Object?> value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
