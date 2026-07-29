import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/storage/media_store.dart';

void main() {
  test('detects common image file extensions from bytes', () {
    expect(imageFileExtension([0x89, 0x50, 0x4e, 0x47]), '.png');
    expect(imageFileExtension([0xff, 0xd8, 0xff]), '.jpg');
    expect(imageFileExtension('RIFF1234WEBP'.codeUnits), '.webp');
    expect(imageFileExtension('GIF89a'.codeUnits), '.gif');
    expect(imageFileExtension([1, 2, 3]), '.jpg');
  });

  test('cleans only expired files from media temp', () async {
    final root = await Directory.systemTemp.createTemp('media_store_');
    addTearDown(() => root.delete(recursive: true));
    final temp = Directory(
      '${root.path}${Platform.pathSeparator}media${Platform.pathSeparator}temp',
    );
    final avatars = Directory(
      '${root.path}${Platform.pathSeparator}media${Platform.pathSeparator}avatars',
    );
    await temp.create(recursive: true);
    await avatars.create(recursive: true);
    final old = await File(
      '${temp.path}${Platform.pathSeparator}old.tmp',
    ).create();
    final fresh = await File(
      '${temp.path}${Platform.pathSeparator}fresh.tmp',
    ).create();
    final avatar = await File(
      '${avatars.path}${Platform.pathSeparator}old.png',
    ).create();
    final oldTime = DateTime.now().subtract(const Duration(days: 2));
    await old.setLastModified(oldTime);
    await avatar.setLastModified(oldTime);

    await cleanupTemporaryMedia(root, const Duration(hours: 24));

    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await avatar.exists(), isTrue);
  });
}
