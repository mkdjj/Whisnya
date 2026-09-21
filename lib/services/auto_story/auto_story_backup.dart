import 'dart:convert';
import 'dart:io';

import '../../models/auto_story.dart';
import '../storage/backup_files.dart';
import '../storage/json_file_store.dart';

bool _safeId(dynamic value) =>
    value is String && RegExp(r'^[a-zA-Z0-9_-]{1,160}$').hasMatch(value);

/// Only authoritative documents and the rebuildable index belong to this
/// namespace. Recovery files are never accepted as active backup documents.
Future<List<String>> validateAutoStoryBackup(Directory root) async {
  final warnings = <String>[];
  final directory = Directory('${root.path}/auto_stories');
  if (await directory.exists()) {
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Directory) continue;
      final relative = entity.path
          .substring(directory.path.length + 1)
          .replaceAll('\\', '/');
      if (entity is! File ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,160}\.json$').hasMatch(relative)) {
        throw const FormatException('Invalid automatic story backup path');
      }
      if (await entity.length() > 16 * 1024 * 1024) {
        throw const FormatException('Automatic story exceeds size limit');
      }
      final data = jsonDecode(await entity.readAsString());
      if (data is! Map<String, dynamic> ||
          data['schemaVersion'] != 1 ||
          !_safeId(data['id']) ||
          relative != '${data['id']}.json' ||
          data['actors'] is! List ||
          (data['actors'] as List).length != 2) {
        throw const FormatException('Invalid automatic story schema');
      }
      AutoStoryDocument.fromJson(data);
      for (final actor in data['actors'] as List) {
        if (actor is! Map) throw const FormatException('Invalid story actor');
        final path = actor['avatarRelativePath'];
        if (path == null || path == '') continue;
        if (path is! String ||
            backupPath(path) != path ||
            !path.startsWith('media/auto_stories/${data['id']}/')) {
          throw const FormatException(
            'Automatic story media must be relative and owned',
          );
        }
        if (!await File('${root.path}/$path').exists()) {
          warnings.add('Missing optional automatic story image: $path');
        }
      }
    }
  }
  final index = File('${root.path}/auto_story_index.json');
  if (await index.exists()) {
    final data = jsonDecode(await index.readAsString());
    if (data is! List || data.length > 20000) {
      throw const FormatException('Invalid automatic story index');
    }
    final ids = <String>{};
    for (final row in data) {
      if (row is! Map || !_safeId(row['id']) || !ids.add(row['id'] as String)) {
        throw const FormatException('Invalid automatic story index identity');
      }
    }
  }
  return warnings;
}

/// This runs only under the caller's shared maintenance gate. It intentionally
/// patches raw JSON: a later schema field or damaged optional field must not
/// erase a previously inherited privacy requirement.
Future<void> protectAutoStorySource(
  Directory root,
  JsonFileStore store,
  String characterId,
) async {
  final directory = Directory('${root.path}/auto_stories');
  if (!await directory.exists()) return;
  final protectedIds = <String>{};
  await for (final file in directory.list(followLinks: false)) {
    if (file is! File || !file.path.endsWith('.json')) continue;
    final raw = await store.read(file, null);
    if (raw is! Map<String, dynamic> || raw['actors'] is! List) continue;
    final actors = raw['actors'] as List;
    if (!actors.any((a) => a is Map && a['sourceId'] == characterId)) continue;
    if (raw['id'] is String) protectedIds.add(raw['id'] as String);
    await store.write(file, {
      ...raw,
      'privacyRequired': true,
      'actors': [
        for (final actor in actors)
          if (actor is Map && actor['sourceId'] == characterId)
            {...actor, 'lockedSource': true}
          else
            actor,
      ],
    });
  }
  final index = File('${root.path}/auto_story_index.json');
  final rows = await store.read(index, null);
  if (rows is List) {
    await store.write(index, [
      for (final row in rows)
        if (row is Map && protectedIds.contains(row['id']))
          {...row, 'privacyRequired': true}
        else
          row,
    ]);
  }
}

/// Keep all owned copies for extant documents, including quarantined documents.
/// This avoids turning a repairable metadata failure into permanent media loss.
Future<Set<String>> autoStoryReferencedMedia(Directory root) async {
  final result = <String>{};
  final stories = Directory('${root.path}/auto_stories');
  if (!await stories.exists()) return result;
  await for (final story in stories.list(followLinks: false)) {
    if (story is! File) continue;
    final name = story.uri.pathSegments.last;
    final match = RegExp(
      r'^([a-zA-Z0-9_-]{1,160})\.json(?:\..*)?$',
    ).firstMatch(name);
    if (match == null) continue;
    final media = Directory(
      [
        root.path,
        'media',
        'auto_stories',
        match.group(1)!,
      ].join(Platform.pathSeparator),
    );
    if (!await media.exists()) continue;
    await for (final file in media.list(recursive: true, followLinks: false)) {
      if (file is File) result.add(file.path);
    }
  }
  return result;
}

/// Imported and rolled-back documents never resume an old machine's runner.
Future<void> pauseRestoredAutoStories(
  Directory root,
  JsonFileStore store,
) async {
  final directory = Directory('${root.path}/auto_stories');
  if (!await directory.exists()) return;
  await for (final file in directory.list(followLinks: false)) {
    if (file is! File || !file.path.endsWith('.json')) continue;
    final raw = await store.read(file, null);
    if (raw is! Map<String, dynamic>) continue;
    await store.write(file, {
      ...raw,
      'status': 'paused',
      'pauseReason': 'datasetChanged',
      'pauseAfterCurrent': false,
      'runGeneration': (raw['runGeneration'] as int? ?? 0) + 1,
      'revision': (raw['revision'] as int? ?? 0) + 1,
      if (raw['requestLedger'] is List)
        'requestLedger': [
          for (final row in raw['requestLedger'] as List)
            if (row is Map && row['status'] == 'pending')
              {...row, 'status': 'unknown'}
            else
              row,
        ],
    });
  }
}
