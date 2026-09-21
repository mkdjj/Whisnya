import 'dart:io';
import 'dart:math';

import '../../models/api_config.dart';
import '../../models/app_character.dart';
import '../../models/auto_story.dart';
import '../../models/user_profile.dart';
import '../local_storage_service.dart';
import '../storage/media_store.dart';

String newAutoStoryId() =>
    'story_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';

AutoStoryDocument buildAutoStoryDraft({
  required String id,
  required AppCharacter character,
  required UserProfile user,
  required String publicA,
  required String publicB,
  required String opening,
  required String targetEnding,
  required AiEndpointConfig endpointA,
  required AiEndpointConfig endpointB,
  String title = '',
  String style = '',
  int plannedRounds = 80,
  String replyLengthPreset = 'standard',
  int interTurnDelayMs = 1000,
  int? maxRequests,
  int? tokenLimit,
  String? avatarA,
  String? avatarB,
  List<Map<String, dynamic>> worldBooks = const [],
  List<Map<String, dynamic>> memories = const [],
}) => AutoStoryDocument(
  id: id,
  config: StoryConfig(
    title: title.trim().isEmpty
        ? '${character.name} · ${user.name} · 故事演绎'
        : title.trim(),
    opening: opening.trim(),
    targetEnding: targetEnding.trim(),
    style: style.trim(),
    plannedRounds: plannedRounds,
    replyLengthPreset: replyLengthPreset,
    interTurnDelayMs: interTurnDelayMs,
    maxRequests: maxRequests,
    tokenLimit: tokenLimit,
  ),
  actors: [
    StoryActorSnapshot(
      actorId: 'A',
      sourceId: character.id,
      name: character.name,
      avatarRelativePath: avatarA,
      publicProfile: publicA.trim(),
      persona: [
        character.name,
        character.description,
        character.personality,
        character.background,
        character.speakingStyle,
        character.extraPrompt,
      ].where((s) => s.trim().isNotEmpty).join('\n\n'),
      endpointId: endpointA.id,
      model: endpointA.model,
      lockedSource: character.isLocked,
    ),
    StoryActorSnapshot(
      actorId: 'B',
      sourceId: 'userProfile',
      name: user.name.trim(),
      avatarRelativePath: avatarB,
      publicProfile: publicB.trim(),
      persona: [
        user.name,
        user.description,
        user.personality,
        user.speakingStyle,
        user.extraPrompt,
      ].where((s) => s.trim().isNotEmpty).join('\n\n'),
      endpointId: endpointB.id,
      model: endpointB.model,
    ),
  ],
  worldBookSnapshots: worldBooks,
  importedMemorySnapshots: memories,
  privacyRequired: character.isLocked,
);

Future<String?> copyAutoStoryAvatar(
  LocalStorageService storage,
  String storyId,
  String actorId,
  String sourcePath,
) async {
  if (sourcePath.trim().isEmpty) return null;
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(storyId) ||
      !['A', 'B'].contains(actorId)) {
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
