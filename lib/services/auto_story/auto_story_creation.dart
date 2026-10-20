import 'dart:io';
import 'dart:math';

import '../local_storage_service.dart';
import '../storage/media_store.dart';

String newAutoStoryId() =>
    'story_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';

Future<String?> copyAutoStoryAvatar(
  LocalStorageService storage,
  String storyId,
  String actorId,
  String sourcePath,
) async {
  if (sourcePath.trim().isEmpty) return null;
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(storyId) ||
      !RegExp(r'^[A-Z]$').hasMatch(actorId)) {
    throw const FormatException('Invalid story media identity');
  }
  final source = File(sourcePath);
  if (!await source.exists()) return null;
  if (await source.length() > 10 * 1024 * 1024) {
    throw const FormatException('Image exceeds 10 MiB');
  }
  final epoch = storage.datasetEpoch;
  final bytes = await source.readAsBytes();
  final root = await storage.appDataDirectory;
  final relative =
      'media/auto_stories/$storyId/$actorId${imageFileExtension(bytes)}';
  await storage.jsonStore.runOperation(() async {
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }, expectedEpoch: epoch);
  return relative;
}
