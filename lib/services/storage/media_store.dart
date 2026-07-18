import 'dart:io';

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
