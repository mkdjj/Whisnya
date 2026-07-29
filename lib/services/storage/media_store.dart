import 'dart:io';

String imageFileExtension(List<int> bytes) => switch (bytes) {
  [0x89, 0x50, 0x4e, 0x47, ...] => '.png',
  [0xff, 0xd8, ...] => '.jpg',
  [0x47, 0x49, 0x46, ...] => '.gif',
  [0x52, 0x49, 0x46, 0x46, _, _, _, _, 0x57, 0x45, 0x42, 0x50, ...] => '.webp',
  _ => '.jpg',
};

Future<void> cleanupTemporaryMedia(
  Directory root, [
  Duration maxAge = const Duration(hours: 24),
]) async {
  final temp = Directory(
    [root.path, 'media', 'temp'].join(Platform.pathSeparator),
  );
  if (!await temp.exists()) return;
  final cutoff = DateTime.now().subtract(maxAge);
  await for (final entity in temp.list(followLinks: false)) {
    if (entity is! File) continue;
    try {
      if ((await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
      }
    } on FileSystemException {
      // Cleanup is best effort and must never block app startup.
    }
  }
}
