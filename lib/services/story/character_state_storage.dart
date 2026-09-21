import 'dart:convert';
import 'dart:io';
import '../../models/character_state.dart';
import '../storage/json_file_store.dart';
import '../storage/storage_paths.dart';

/// Called before publishing a copied session index. No LocalStorage dependency.
Future<void> cloneStateFile(
  Directory root,
  JsonFileStore store,
  String sourceId,
  String targetId,
  String characterId,
) async {
  for (final id in [sourceId, targetId, characterId]) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid state identity');
    }
  }
  if (sourceId == targetId) {
    throw const FormatException('State copies require distinct sessions');
  }
  final paths = StoragePaths(root);
  final source = paths.characterState(sourceId);
  await store.synchronized(source, () async {
    if (await store.recoveryNeeded(source)) await store.recover(source);
    if (!await source.exists()) return;
    final data = jsonDecode(await source.readAsString());
    if (data is! Map<String, dynamic> ||
        data['schemaVersion'] != 1 ||
        data['sessionId'] != sourceId ||
        data['characterId'] != characterId ||
        data['history'] is! List<dynamic>) {
      throw const FormatException('Invalid source state');
    }
    final history = <Map<String, dynamic>>[];
    for (final value in data['history'] as List<dynamic>) {
      final state = CharacterStateView.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      if (state.sessionId != sourceId || state.characterId != characterId) {
        throw const FormatException('Invalid state ownership');
      }
      history.add({
        ...state.toJson(),
        'sessionId': targetId,
        'anchor': state.anchor?.inSession(targetId).toJson(),
      });
    }
    await store.write(paths.characterState(targetId), {
      ...data,
      'sessionId': targetId,
      'history': history,
    });
  });
}
