import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/services/bubble_import/bubble_import_models.dart';
import 'package:whisnya/services/bubble_import/bubble_package_import_service.dart';
import 'package:whisnya/services/bubble_import/bubble_package_scanner.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scanner = BubblePackageScanner();

  test('imports PNG pair into canonical preset directory', () async {
    final root = await Directory.systemTemp.createTemp('bubble-import-');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: root);
    final role = img.Image(width: 36, height: 28, numChannels: 4);
    role.setPixelRgba(0, 0, 0, 0, 0, 0);
    final png = img.encodePng(role);
    final scan = await _scan(scanner, {'role.png': png, 'user.png': png});
    addTearDown(scan.dispose);

    final preset = await BubblePackageImportService(storage: storage).import(
      _mapping(scan, rolePath: 'role.png', userPath: 'user.png'),
      presetId: 'stars',
    );

    final directory = Directory(
      '${root.path}${Platform.pathSeparator}media${Platform.pathSeparator}'
      'bubble_skins${Platform.pathSeparator}stars',
    );
    expect(
      await File('${directory.path}${Platform.pathSeparator}role.png').exists(),
      isTrue,
    );
    expect(
      await File('${directory.path}${Platform.pathSeparator}user.png').exists(),
      isTrue,
    );
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}preview.png',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}manifest.json',
      ).exists(),
      isTrue,
    );
    final source =
        jsonDecode(
              await File(
                '${directory.path}${Platform.pathSeparator}source_info.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(source['originalFileName'], 'resource.zip');
    expect(source['originalFiles'], ['role.png', 'user.png']);
    expect(jsonEncode(source), isNot(contains(root.path)));
    expect(
      preset.appearance.imageSkin!.imagePath,
      endsWith('stars${Platform.pathSeparator}role.png'),
    );
    expect(
      preset.userAppearance!.imageSkin!.imagePath,
      endsWith('stars${Platform.pathSeparator}user.png'),
    );
    expect((await storage.loadChatBubblePresets()).presets.single.id, 'stars');
  });

  test('strips nine-patch border and can mirror the user side', () async {
    final root = await Directory.systemTemp.createTemp('bubble-nine-');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: root);
    final scan = await _scan(scanner, {'role.9.png': _ninePatch()});
    addTearDown(scan.dispose);

    final preset = await BubblePackageImportService(storage: storage).import(
      _mapping(
        scan,
        rolePath: 'role.9.png',
        userMode: BubblePackageUserImageMode.mirrorRole,
      ),
      presetId: 'nine',
    );

    expect(preset.appearance.imageSkin!.imageWidth, 10);
    expect(preset.appearance.imageSkin!.imageHeight, 8);
    expect(preset.userAppearance!.imageSkin!.imageWidth, 10);
    expect(preset.appearance.imageSkin!.stretchRegion.left, .2);
  });

  test('converts static WebP and SVG to PNG', () async {
    final root = await Directory.systemTemp.createTemp('bubble-formats-');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: root);
    final raster = img.Image(width: 32, height: 24, numChannels: 4);
    final svg = utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="30">'
      '<rect width="40" height="30" rx="8" fill="#4488ff"/></svg>',
    );
    final scan = await _scan(scanner, {
      'role.webp': img.encodeWebP(raster),
      'user.svg': svg,
    });
    addTearDown(scan.dispose);

    await BubblePackageImportService(storage: storage).import(
      _mapping(scan, rolePath: 'role.webp', userPath: 'user.svg'),
      presetId: 'formats',
    );

    final directory =
        '${root.path}${Platform.pathSeparator}media${Platform.pathSeparator}'
        'bubble_skins${Platform.pathSeparator}formats';
    expect(
      img.decodePng(
        await File('$directory${Platform.pathSeparator}role.png').readAsBytes(),
      ),
      isNotNull,
    );
    final user = img.decodePng(
      await File('$directory${Platform.pathSeparator}user.png').readAsBytes(),
    );
    expect((user!.width, user.height), (40, 30));
  });

  test('failed conversion leaves no preset or partial directory', () async {
    final root = await Directory.systemTemp.createTemp('bubble-failed-');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: root);
    final scan = await _scan(scanner, {
      'role.png': img.encodePng(img.Image(width: 32, height: 32)),
    });
    addTearDown(scan.dispose);

    await expectLater(
      BubblePackageImportService(
        storage: storage,
      ).import(_mapping(scan, rolePath: 'missing.png'), presetId: 'broken'),
      throwsA(isA<BubblePackageException>()),
    );

    expect((await storage.loadChatBubblePresets()).presets, isEmpty);
    final skins = Directory(
      '${root.path}${Platform.pathSeparator}media${Platform.pathSeparator}bubble_skins',
    );
    expect(
      await skins.exists()
          ? await skins.list().toList()
          : const <FileSystemEntity>[],
      isEmpty,
    );
  });
}

BubblePackageMapping _mapping(
  BubblePackageScanResult scan, {
  required String rolePath,
  String? userPath,
  BubblePackageUserImageMode userMode = BubblePackageUserImageMode.manual,
}) => BubblePackageMapping(
  scan: scan,
  candidate: const BubblePackageCandidate(
    level: BubblePackageRecognitionLevel.probable,
    detectedFormat: 'test-format',
  ),
  name: '测试气泡',
  rolePath: rolePath,
  userMode: userPath == null && userMode == BubblePackageUserImageMode.manual
      ? BubblePackageUserImageMode.shareRole
      : userMode,
  userPath: userPath,
  stretchRegion: const BubbleNormalizedRect(
    left: .2,
    top: .2,
    right: .8,
    bottom: .8,
  ),
  fillRegion: const BubbleNormalizedRect(
    left: .1,
    top: .1,
    right: .9,
    bottom: .9,
  ),
  textPadding: const BubbleContentInsets(
    left: 12,
    top: 8,
    right: 12,
    bottom: 8,
  ),
  fillColor: 0xffffffff,
  textColor: 0xff000000,
  opacity: .85,
);

Future<BubblePackageScanResult> _scan(
  BubblePackageScanner scanner,
  Map<String, List<int>> files,
) => scanner.scan(bytes: _zip(files), originalFileName: 'resource.zip');

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _ninePatch() {
  final source = img.Image(width: 12, height: 10, numChannels: 4);
  for (var x = 3; x <= 8; x++) {
    source.setPixelRgba(x, 0, 0, 0, 0, 255);
  }
  for (var y = 2; y <= 6; y++) {
    source.setPixelRgba(0, y, 0, 0, 0, 255);
  }
  return Uint8List.fromList(img.encodePng(source));
}
