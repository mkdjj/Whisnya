import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../models/memento.dart';
import '../models/message_anchor.dart';
import '../models/chat_message.dart';
import '../models/auto_story.dart' as auto_story;
import 'local_storage_service.dart';

String _autoStoryPrefix(auto_story.AutoStoryDocument story, int ordinal) =>
    sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final turn in story.turns.take(ordinal + 1))
                {
                  'turnId': turn.turnId,
                  'speakerId': turn.speakerId,
                  'content': turn.content,
                  'source': turn.source.name,
                },
            ]),
          ),
        )
        .toString();

/// Captures only formal visible text; never persona, reasoning or future goals.
MementoEntry autoStoryMementoEntry(
  auto_story.AutoStoryDocument story,
  auto_story.StoryTurn turn,
) {
  final current = story.turns.where((t) => t.turnId == turn.turnId).firstOrNull;
  if (current == null || current.content != turn.content) {
    throw StateError('Story turn changed');
  }
  final actor = story.actors.firstWhere((a) => a.actorId == current.speakerId);
  final label = current.speakerId == 'B'
      ? '${actor.name} (${current.source == auto_story.StoryTurnSource.ai ? 'AI' : 'Manual'})'
      : actor.name;
  return MementoEntry(
    sourceMessageId: current.turnId,
    sourcePrefixDigest: _autoStoryPrefix(story, current.ordinal),
    role: current.speakerId == 'B' ? 'user' : 'assistant',
    speakerNameSnapshot: label,
    time: current.createdAt,
    contentSnapshot: current.content,
  );
}

class MementoPaths {
  const MementoPaths(this.root);
  final Directory root;
  File get index => File('${root.path}/collection/index.json');
  File item(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid collection ID');
    }
    return File('${root.path}/collection/items/$id.json');
  }

  File media(String asset) {
    if (!RegExp(r'^[a-f0-9]{64}\.(png|jpg|jpeg|webp)$').hasMatch(asset)) {
      throw const FormatException('Invalid asset');
    }
    return File('${root.path}/collection/media/$asset');
  }
}

class MementoService {
  MementoService({required this.storage, this.authorize});
  final LocalStorageService storage;
  final Future<bool> Function(String characterId, bool requiresUnlock)?
  authorize;
  Future<MementoPaths> get paths async =>
      MementoPaths(await storage.appDataDirectory);
  Future<auto_story.AutoStoryDocument> _storySource(MementoDraft draft) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(draft.sourceSessionId)) {
      throw ArgumentError('Invalid story ID');
    }
    final root = await storage.appDataDirectory;
    final raw = await storage.jsonStore.read(
      File('${root.path}/auto_stories/${draft.sourceSessionId}.json'),
      null,
    );
    if (raw is! Map<String, dynamic>) throw StateError('Story source missing');
    final story = auto_story.AutoStoryDocument.fromJson(raw);
    if ((story.actors.first.sourceId ?? '') != draft.characterId) {
      throw StateError('Story source character mismatch');
    }
    return story;
  }

  Future<bool> _draftPrivacy(MementoDraft draft) async {
    if (draft.sourceType != 'autoStory') return draft.requiresUnlock;
    final story = await _storySource(draft);
    if (story.privacyRequired) return true;
    for (final actor in story.actors) {
      if (await _protected(actor.sourceId ?? '', actor.lockedSource)) {
        return true;
      }
    }
    return draft.requiresUnlock;
  }

  Future<bool> _protected(String id, bool captured) async {
    final root = await storage.appDataDirectory;
    final chars = await storage.jsonStore.read(
      File('${root.path}/characters.json'),
      <dynamic>[],
    );
    return captured ||
        (chars as List).whereType<Map<dynamic, dynamic>>().any(
          (c) => c['id'] == id && c['isLocked'] == true,
        );
  }

  Future<void> _check(String id, bool captured) async {
    final locked = await _protected(id, captured);
    if (locked && !(await authorize?.call(id, true) ?? false)) {
      throw StateError('Collection is locked');
    }
  }

  Future<List<Map<String, dynamic>>> _index(MementoPaths p) async {
    if (await storage.jsonStore.recoveryNeeded(p.index)) {
      await storage.jsonStore.recover(p.index);
    }
    if (!await p.index.exists()) return [];
    return (jsonDecode(await p.index.readAsString()) as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  Map<String, dynamic> _summary(MementoSnapshot s) => {
    'id': s.id,
    'idempotencyKey': s.idempotencyKey,
    'characterId': s.characterId,
    'title': s.title,
    'tags': s.tags,
    'createdAt': s.createdAt.toIso8601String(),
    'requiresUnlock': s.requiresUnlock,
    'sourceType': s.sourceType,
    'sourceSessionId': s.sourceSessionId,
  };
  Future<T> _write<T>(
    Future<T> Function(MementoPaths p, List<Map<String, dynamic>> rows) action,
  ) async {
    final epoch = storage.datasetEpoch;
    final p = await paths;
    return storage.jsonStore.runOperation(
      () => storage.jsonStore.synchronized(
        p.index,
        () async => action(p, await _index(p)),
      ),
      expectedEpoch: epoch,
    );
  }

  Future<MementoSnapshot> createMemento(MementoDraft draft) async {
    draft.validate();
    final epoch = storage.datasetEpoch;
    final initialPaths = await paths;
    await storage.jsonStore.waitFor(initialPaths.index);
    for (final row in await _index(initialPaths)) {
      if (row['idempotencyKey'] == draft.idempotencyKey) {
        if (row['characterId'] != draft.characterId) {
          throw StateError('Submission identity conflict');
        }
        return loadMemento(row['id'] as String);
      }
    }
    final capturedPrivacy = await _draftPrivacy(draft);
    final protectedBefore = await _protected(
      draft.characterId,
      capturedPrivacy,
    );
    await _check(draft.characterId, capturedPrivacy);
    if (epoch != storage.datasetEpoch) throw StateError('Dataset changed');
    return storage.jsonStore.maintain(
      () => _write((p, rows) async {
        if (epoch != storage.datasetEpoch) throw StateError('Dataset changed');
        for (final row in rows) {
          if (row['idempotencyKey'] == draft.idempotencyKey) {
            if (row['characterId'] != draft.characterId) {
              throw StateError('Submission identity conflict');
            }
            if (row['requiresUnlock'] == true && !protectedBefore) {
              throw StateError('Privacy changed; authorize again');
            }
            return MementoSnapshot.fromJson(
              Map<String, dynamic>.from(
                await storage.jsonStore.read(p.item(row['id'] as String), null)
                    as Map,
              ),
            );
          }
        }
        var entries = draft.entries;
        if (draft.sourceType == 'autoStory') {
          final story = await _storySource(draft);
          final captured = <MementoEntry>[];
          var prior = -1;
          for (final entry in draft.entries) {
            final turn = story.turns
                .where((t) => t.turnId == entry.sourceMessageId)
                .firstOrNull;
            if (turn == null || turn.ordinal <= prior) {
              throw StateError('Story turns changed');
            }
            final canonical = autoStoryMementoEntry(story, turn);
            if (entry.sourceVariantId != null ||
                entry.sourcePrefixDigest != canonical.sourcePrefixDigest ||
                entry.contentSnapshot != canonical.contentSnapshot ||
                entry.role != canonical.role) {
              throw StateError('Story snapshot mismatch');
            }
            captured.add(canonical);
            prior = turn.ordinal;
          }
          entries = List.unmodifiable(captured);
        } else {
          final sessions = await storage.jsonStore.read(
            File('${p.root.path}/chat_sessions.json'),
            <dynamic>[],
          );
          if (!(sessions as List).whereType<Map<dynamic, dynamic>>().any(
            (s) =>
                s['id'] == draft.sourceSessionId &&
                s['characterId'] == draft.characterId,
          )) {
            throw StateError('Source session changed');
          }
          if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(draft.sourceSessionId)) {
            throw ArgumentError('Invalid session ID');
          }
          final raw = await storage.jsonStore.read(
            File('${p.root.path}/chats/${draft.sourceSessionId}.json'),
            <dynamic>[],
          );
          final messages = ((raw is Map ? raw['messages'] : raw) as List)
              .map(
                (m) =>
                    ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)),
              )
              .toList();
          var prior = -1;
          for (final entry in draft.entries) {
            final at = messages.indexWhere(
              (m) => m.id == entry.sourceMessageId,
            );
            if (at <= prior ||
                !MessageAnchor(
                  sessionId: draft.sourceSessionId,
                  messageId: entry.sourceMessageId,
                  variantId: entry.sourceVariantId,
                  prefixDigest: entry.sourcePrefixDigest,
                ).matches(messages)) {
              throw StateError('Source messages changed; select again');
            }
            final message = messages[at];
            if (message.effectiveContent != entry.contentSnapshot ||
                message.role != entry.role) {
              throw StateError('Snapshot mismatch');
            }
            prior = at;
          }
        }
        final now = DateTime.now();
        final locked = await _protected(
          draft.characterId,
          await _draftPrivacy(draft),
        );
        if (locked && !protectedBefore) {
          throw StateError('Privacy changed; authorize again');
        }
        final s = MementoSnapshot(
          id: newStoryId(),
          createdAt: now,
          updatedAt: now,
          idempotencyKey: draft.idempotencyKey,
          title: draft.title.trim(),
          characterId: draft.characterId,
          characterNameSnapshot: draft.characterNameSnapshot,
          sessionTitleSnapshot: draft.sessionTitleSnapshot,
          sourceSessionId: draft.sourceSessionId,
          sourceType: draft.sourceType,
          entries: entries,
          requiresUnlock: locked,
          tags: draft.tags,
          note: draft.note,
        );
        for (final e in s.entries) {
          if (e.avatarAssetId != null &&
              !await p.media(e.avatarAssetId!).exists()) {
            throw ArgumentError('Unrecognized collection avatar');
          }
        }
        await storage.jsonStore.write(p.item(s.id), s.toJson());
        try {
          await storage.jsonStore.writeNow(p.index, [...rows, _summary(s)]);
        } catch (_) {
          if (await p.item(s.id).exists()) await p.item(s.id).delete();
          rethrow;
        }
        return s;
      }),
    );
  }

  /// Checks immutable source identity, never the editable title or notes.
  Future<bool> hasEquivalentCapture(MementoDraft draft) async {
    draft.validate();
    final epoch = storage.datasetEpoch;
    await _check(draft.characterId, draft.requiresUnlock);
    final p = await paths;
    await storage.jsonStore.waitFor(p.index);
    final rows = await _index(p);
    for (final row in rows) {
      if (row['characterId'] != draft.characterId) continue;
      final existing = await loadMemento(row['id'] as String);
      if (epoch != storage.datasetEpoch) throw StateError('Dataset changed');
      if (existing.sourceType != draft.sourceType ||
          existing.sourceSessionId != draft.sourceSessionId ||
          existing.entries.length != draft.entries.length) {
        continue;
      }
      var equal = true;
      for (var i = 0; i < draft.entries.length; i++) {
        final a = existing.entries[i], b = draft.entries[i];
        if (a.sourceMessageId != b.sourceMessageId ||
            a.sourceVariantId != b.sourceVariantId ||
            a.sourcePrefixDigest != b.sourcePrefixDigest ||
            a.contentSnapshot != b.contentSnapshot) {
          equal = false;
          break;
        }
      }
      if (equal) return true;
    }
    return false;
  }

  Future<MementoSnapshot> loadMemento(String id) async {
    final epoch = storage.datasetEpoch;
    final p = await paths;
    final raw = await storage.jsonStore.read(p.item(id), null);
    if (raw == null) throw StateError('Collection not found');
    final s = MementoSnapshot.fromJson(Map<String, dynamic>.from(raw as Map));
    await _check(s.characterId, s.requiresUnlock);
    if (epoch != storage.datasetEpoch) throw StateError('Dataset changed');
    return s;
  }

  /// A non-content token for an already authorized preview; never grants access.
  Future<bool> protectionState(String id) async {
    final p = await paths;
    final raw = await storage.jsonStore.read(p.item(id), null);
    if (raw is! Map) throw StateError('Collection not found');
    return _protected(
      raw['characterId'] as String,
      raw['requiresUnlock'] == true,
    );
  }

  Future<List<MementoIndex>> queryMementos(
    MementoQuery query,
  ) => storage.jsonStore.runOperation(() async {
    final p = await paths;
    await storage.jsonStore.waitFor(p.index);
    final rows = await _index(p);
    final out = <MementoIndex>[];
    for (final r in rows) {
      if (query.characterId != null && r['characterId'] != query.characterId) {
        continue;
      }
      final locked = await _protected(
        r['characterId'] as String,
        r['requiresUnlock'] == true,
      );
      if (locked && (query.keyword.isNotEmpty || query.tag != null)) continue;
      final tags = (r['tags'] as List).cast<String>();
      if (query.tag != null && !tags.contains(query.tag)) continue;
      if (query.keyword.isNotEmpty) {
        final raw = await storage.jsonStore.read(
          p.item(r['id'] as String),
          null,
        );
        if (raw == null) continue;
        final s = MementoSnapshot.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        if (s.requiresUnlock) continue;
        final haystack =
            '${s.title}\n${s.note}\n${s.entries.map((e) => e.contentSnapshot).join('\n')}'
                .toLowerCase();
        if (!haystack.contains(query.keyword.toLowerCase())) continue;
      }
      out.add(
        MementoIndex(
          id: r['id'] as String,
          characterId: r['characterId'] as String,
          title: locked ? '🔒' : r['title'] as String,
          tags: locked ? const [] : List.unmodifiable(tags),
          createdAt: DateTime.parse(r['createdAt'] as String),
          requiresUnlock: locked,
        ),
      );
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  });

  Future<void> updateMementoMetadata(MementoMetadataPatch patch) async {
    validateMetadata(patch.title, patch.tags, patch.note);
    final authorized = await loadMemento(patch.id);
    final epoch = storage.datasetEpoch;
    await _write((p, rows) async {
      if (epoch != storage.datasetEpoch) throw StateError('Dataset changed');
      final raw = await storage.jsonStore.read(p.item(authorized.id), null);
      if (raw == null || !rows.any((r) => r['id'] == patch.id)) {
        throw StateError('Collection not found');
      }
      final updated = MementoSnapshot.fromJson({
        ...Map<String, dynamic>.from(raw as Map),
        'title': patch.title.trim(),
        'tags': patch.tags,
        'note': patch.note,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await storage.jsonStore.write(p.item(patch.id), updated.toJson());
      try {
        await storage.jsonStore.writeNow(p.index, [
          for (final r in rows)
            if (r['id'] == patch.id) _summary(updated) else r,
        ]);
      } catch (_) {
        await storage.jsonStore.write(p.item(patch.id), raw);
        rethrow;
      }
    });
  }

  Future<void> deleteMemento(String id) async {
    final removed = await loadMemento(id);
    final epoch = storage.datasetEpoch;
    await _write((p, rows) async {
      if (epoch != storage.datasetEpoch) throw StateError('Dataset changed');
      await storage.jsonStore.writeNow(
        p.index,
        rows.where((r) => r['id'] != id).toList(),
      );
      if (await p.item(id).exists()) await p.item(id).delete();
      final candidates = removed.entries
          .map((e) => e.avatarAssetId)
          .whereType<String>()
          .toSet();
      for (final row in rows.where((r) => r['id'] != id)) {
        final raw = await storage.jsonStore.read(
          p.item(row['id'] as String),
          null,
        );
        if (raw == null) continue;
        final kept = MementoSnapshot.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        candidates.removeAll(
          kept.entries.map((e) => e.avatarAssetId).whereType<String>(),
        );
      }
      for (final asset in candidates) {
        final f = p.media(asset);
        if (await f.exists()) await f.delete();
      }
    });
  }

  Future<SourceNavigationResult> locateMementoSource(
    String id,
    int entryIndex,
  ) async {
    final s = await loadMemento(id);
    final e = s.entries[entryIndex];
    final p = await paths;
    if (s.sourceType == 'autoStory') {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s.sourceSessionId)) {
        return SourceNavigationResult.sourceMissing;
      }
      final file = File(
        '${p.root.path}/auto_stories/${s.sourceSessionId}.json',
      );
      final raw = await storage.jsonStore.read(file, null);
      if (raw is! Map<String, dynamic>) {
        return SourceNavigationResult.sourceMissing;
      }
      final story = auto_story.AutoStoryDocument.fromJson(raw);
      final turn = story.turns
          .where((t) => t.turnId == e.sourceMessageId)
          .firstOrNull;
      if (turn == null) return SourceNavigationResult.messageMissing;
      return _autoStoryPrefix(story, turn.ordinal) == e.sourcePrefixDigest
          ? SourceNavigationResult.found
          : SourceNavigationResult.contentChanged;
    }
    final sessions = await storage.jsonStore.read(
      File('${p.root.path}/chat_sessions.json'),
      <dynamic>[],
    );
    final matches = (sessions as List).whereType<Map<dynamic, dynamic>>().where(
      (v) => v['id'] == s.sourceSessionId && v['characterId'] == s.characterId,
    );
    if (matches.isEmpty) return SourceNavigationResult.sourceMissing;
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s.sourceSessionId)) {
      return SourceNavigationResult.sourceMissing;
    }
    final raw = await storage.jsonStore.read(
      File('${p.root.path}/chats/${s.sourceSessionId}.json'),
      <dynamic>[],
    );
    final messages = ((raw is Map ? raw['messages'] : raw) as List)
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
    final i = messages.indexWhere((m) => m.id == e.sourceMessageId);
    if (i < 0) return SourceNavigationResult.messageMissing;
    final a = MessageAnchor.capture(s.sourceSessionId, messages, i);
    if (a.variantId != e.sourceVariantId) {
      return SourceNavigationResult.variantChanged;
    }
    return a.prefixDigest == e.sourcePrefixDigest
        ? SourceNavigationResult.found
        : SourceNavigationResult.contentChanged;
  }

  /// Only invoke with a path from the character model or explicit file picker.
  Future<String?> copyRecognizedAvatar(
    String path, {
    required Set<String> recognizedPaths,
  }) async {
    final epoch = storage.datasetEpoch;
    if (!recognizedPaths.contains(path)) {
      throw ArgumentError('Avatar source is not authorized');
    }
    try {
      final f = File(path);
      if (await f.length() > 10 * 1024 * 1024) return null;
      final ext = path.split('.').last.toLowerCase();
      if (!['png', 'jpg', 'jpeg', 'webp'].contains(ext)) return null;
      final bytes = await f.readAsBytes();
      final asset = '${sha256.convert(bytes)}.$ext';
      final p = await paths;
      await storage.jsonStore.runOperation(() async {
        final target = p.media(asset);
        if (!await target.exists()) {
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes, flush: true);
        }
      }, expectedEpoch: epoch);
      return asset;
    } on FileSystemException {
      return null;
    }
  }
}

Future<void> validateMementoBackup(Directory root) async {
  final p = MementoPaths(root);
  if (!await p.index.exists()) return;
  final rows = jsonDecode(await p.index.readAsString()) as List;
  final ids = <String>{};
  for (final r in rows) {
    final id = (r as Map)['id'] as String;
    if (!ids.add(id)) throw const FormatException('Duplicate collection');
    final s = MementoSnapshot.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await p.item(id).readAsString()) as Map,
      ),
    );
    if (s.id != id ||
        s.requiresUnlock != r['requiresUnlock'] ||
        s.characterId != r['characterId']) {
      throw const FormatException('Collection index mismatch');
    }
    for (final e in s.entries) {
      final asset = e.avatarAssetId;
      if (asset != null) {
        final f = p.media(asset);
        if (!await f.exists() ||
            await f.length() > 10 * 1024 * 1024 ||
            sha256.convert(await f.readAsBytes()).toString() !=
                asset.split('.').first) {
          throw const FormatException('Invalid collection media');
        }
      }
    }
  }
}
