import 'dart:io';

Stream<File> chatImageJsonFiles(Directory root) async* {
  for (final name in [
    'chats',
    'theater_messages',
    'story/checkpoints',
    'collection/items',
  ]) {
    final directory = Directory('${root.path}/$name');
    if (!await directory.exists()) continue;
    await for (final file in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (file is File && file.path.endsWith('.json')) yield file;
    }
  }
}

/// Reuse the same traversal for media cleanup and cross-platform restoration.
bool visitChatImages(dynamic value, String Function(String) visit) {
  var changed = false;
  if (value is List) {
    for (final item in value) {
      if (visitChatImages(item, visit)) changed = true;
    }
  } else if (value is Map) {
    for (final key in value.keys) {
      final item = value[key];
      if (key == 'imagePaths' && item is List) {
        value[key] = [for (final path in item.cast<String>()) visit(path)];
        if (item.join('\n') != (value[key] as List).join('\n')) changed = true;
      } else if (visitChatImages(item, visit)) {
        changed = true;
      }
    }
  }
  return changed;
}

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

Future<int> cleanupUnusedMedia(
  Directory root,
  Set<String> referencedPaths,
) async {
  final media = Directory([root.path, 'media'].join(Platform.pathSeparator));
  if (!await media.exists()) return 0;
  final referenced = referencedPaths
      .where((path) => path.trim().isNotEmpty)
      .map(_normalizedPath)
      .toSet();
  final tempPrefix =
      '${_normalizedPath([media.path, 'temp'].join(Platform.pathSeparator))}'
      '${Platform.pathSeparator}';
  var deleted = 0;
  await for (final entity in media.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = _normalizedPath(entity.path);
    if (path.startsWith(tempPrefix) || referenced.contains(path)) continue;
    // A selected, unsent attachment has no message reference yet.
    if (path.replaceAll('\\', '/').contains('/media/chat_images/') &&
        (await entity.lastModified()).isAfter(
          DateTime.now().subtract(const Duration(hours: 24)),
        )) {
      continue;
    }
    try {
      await entity.delete();
      deleted++;
    } on FileSystemException {
      // Cleanup is best effort and must never block normal app use.
    }
  }
  return deleted;
}

String _normalizedPath(String path) {
  final absolute = File(path).absolute.path;
  return Platform.isWindows ? absolute.toLowerCase() : absolute;
}
