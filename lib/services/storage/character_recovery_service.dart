import 'dart:convert';
import 'dart:io';
import '../../models/chat_session.dart';

class CharacterRecoveryResult {
  const CharacterRecoveryResult(
    this.characterIds,
    this.warnings,
    this.sessions,
  );
  final Set<String> characterIds;
  final List<String> warnings;
  final List<ChatSession> sessions;
}

/// Resolves identities without modifying source documents or inventing sessions.
class CharacterRecoveryService {
  Future<CharacterRecoveryResult> resolveRecoveryCandidates(
    Directory root,
  ) async {
    final warnings = <String>[];
    final mapping = <String, String>{};
    final conflicts = <String>{};
    final legacy = <String>{};
    final explicitSessions = <String>{};
    bool validId(Object? value) =>
        value is String && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
    Future<Object?> decode(File file) async {
      try {
        return jsonDecode(await file.readAsString());
      } on FormatException {
        warnings.add('恢复时发现损坏 JSON：${file.uri.pathSegments.last}');
      } on FileSystemException {
        warnings.add('恢复时无法读取：${file.uri.pathSegments.last}');
      }
      return null;
    }

    final index = File('${root.path}/chat_sessions.json');
    if (await index.exists()) {
      final rows = await decode(index);
      if (rows is List) {
        for (var i = 0; i < rows.length; i++) {
          final row = rows[i];
          if (row is! Map ||
              !validId(row['id']) ||
              !validId(row['characterId'])) {
            warnings.add('chat_sessions.json 第 $i 项无法恢复');
            continue;
          }
          final id = row['id'] as String;
          final character = row['characterId'] as String;
          if (mapping.containsKey(id) && mapping[id] != character) {
            conflicts.add(id);
            warnings.add('会话 $id 的角色映射冲突');
          } else {
            mapping[id] = character;
          }
        }
      }
    }
    for (final folder in ['chats', 'summaries']) {
      final directory = Directory('${root.path}/$folder');
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        final fileId = name.substring(0, name.length - 5);
        final data = await decode(entity);
        if (data == null) continue;
        if (data is Map) {
          final sessionId = data['sessionId'];
          final characterId = data['characterId'];
          if (sessionId != null && sessionId != '' && sessionId != fileId) {
            conflicts.add(fileId);
            warnings.add('$folder/$name 的文件名和 sessionId 冲突');
            continue;
          }
          if (validId(characterId)) {
            if (mapping.containsKey(fileId) && mapping[fileId] != characterId) {
              conflicts.add(fileId);
              warnings.add('$folder/$name 的角色元数据与索引冲突');
            } else {
              mapping[fileId] = characterId as String;
              if (sessionId == fileId) explicitSessions.add(fileId);
            }
            continue;
          }
          if (mapping.containsKey(fileId)) continue;
          if (sessionId != null && sessionId != '') {
            warnings.add('$folder/$name 缺少角色关联，原文件已保留');
            continue;
          }
        }
        if (mapping.containsKey(fileId)) continue;
        final oldShape =
            data is List ||
            (data is Map &&
                ((folder == 'summaries' && data['summary'] is String) ||
                    (folder == 'chats' && data['messages'] is List)));
        if (oldShape && RegExp(r'^character_\d+$').hasMatch(fileId)) {
          legacy.add(fileId);
        } else {
          warnings.add('$folder/$name 无法关联角色，原文件已保留');
        }
      }
    }
    return CharacterRecoveryResult(
      {
        ...legacy,
        for (final entry in mapping.entries)
          if (!conflicts.contains(entry.key)) entry.value,
      },
      warnings,
      [
        for (final id in explicitSessions)
          if (!conflicts.contains(id))
            ChatSession(
              id: id,
              characterId: mapping[id]!,
              title: '恢复的对话',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              lastUsedAt: DateTime.now(),
              openingMessageInitialized: true,
            ),
      ],
    );
  }
}
