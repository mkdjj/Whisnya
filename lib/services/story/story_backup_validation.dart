import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../models/character_state.dart';
import '../../models/chat_message.dart';
import 'character_state_service.dart';

/// Fields and order are the v1 immutable checkpoint hash contract.
String checkpointContentHash(Map<String, dynamic> value) => sha256
    .convert(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          for (final key in [
            'schemaVersion',
            'characterId',
            'characterNameSnapshot',
            'sourceSessionId',
            'sourceSessionTitle',
            'branchRootSessionId',
            'anchor',
            'messages',
            'initialState',
            'contextPolicy',
          ])
            key: value[key],
        }),
      ),
    )
    .toString();

void validateStoryMessageIds(List<dynamic> messages) {
  void unique(List<dynamic> rows) {
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid story message');
      }
      if (!row.containsKey('id')) continue; // Legacy backups migrate on load.
      final id = row['id'];
      if (id is! String || id.trim().isEmpty || !seen.add(id)) {
        throw const FormatException('Invalid or duplicate message identity');
      }
    }
  }

  unique(messages);
  for (final row in messages.cast<Map<String, dynamic>>()) {
    final variants = row['variants'];
    if (variants is List<dynamic>) unique(variants);
  }
}

Future<List<String>> validateStoryBackup(Directory root) async {
  final warnings = <String>[];
  Future<dynamic> read(File file) async =>
      jsonDecode(await file.readAsString());
  bool safe(dynamic id) =>
      id is String && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);
  final chatDir = Directory('${root.path}/chats');
  if (await chatDir.exists()) {
    await for (final file in chatDir.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final data = await read(file);
      final rows = data is List<dynamic>
          ? data
          : data is Map<String, dynamic>
          ? data['messages']
          : null;
      if (rows is List<dynamic>) validateStoryMessageIds(rows);
    }
  }
  final checkpoints = Directory('${root.path}/story/checkpoints');
  final payloads = <String, Map<String, dynamic>>{};
  if (await checkpoints.exists()) {
    await for (final file in checkpoints.list(followLinks: false)) {
      if (file is! File ||
          !file.path.endsWith('.json') ||
          file.uri.pathSegments.last == 'index.json') {
        continue;
      }
      final data = await read(file);
      final filename = file.uri.pathSegments.last;
      if (data is! Map<String, dynamic> ||
          data['schemaVersion'] != 1 ||
          !safe(data['id']) ||
          filename != '${data['id']}.json' ||
          !safe(data['characterId']) ||
          data['messages'] is! List<dynamic> ||
          data['anchor'] is! Map<String, dynamic> ||
          data['requiresUnlock'] is! bool) {
        throw const FormatException('Invalid checkpoint identity or schema');
      }
      if (data['contentHash'] != checkpointContentHash(data)) {
        throw const FormatException('Checkpoint hash mismatch');
      }
      final messages = data['messages'] as List<dynamic>;
      validateStoryMessageIds(messages);
      if (messages.isEmpty ||
          messages.any((r) => !(r as Map<String, dynamic>).containsKey('id'))) {
        throw const FormatException('Checkpoint messages require identities');
      }
      final anchor = data['anchor'] as Map<String, dynamic>;
      final target = messages.last as Map<String, dynamic>;
      if (anchor['sessionId'] != data['sourceSessionId'] ||
          anchor['messageId'] != target['id'] ||
          anchor['prefixDigest'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(anchor['prefixDigest'] as String)) {
        throw const FormatException('Invalid checkpoint anchor');
      }
      if (target['role'] == 'assistant' &&
          target['sourceVariantId'] != anchor['variantId']) {
        throw const FormatException('Invalid checkpoint variant');
      }
      if (data['initialState'] != null) {
        final state = CharacterStateView.fromJson(
          Map<String, dynamic>.from(data['initialState'] as Map),
        );
        if (state.characterId != data['characterId'] ||
            state.sessionId != data['sourceSessionId']) {
          throw const FormatException('Checkpoint state ownership mismatch');
        }
      }
      payloads[data['id'] as String] = data;
    }
  }
  final indexFile = File('${checkpoints.path}/index.json');
  if (await indexFile.exists()) {
    final rows = await read(indexFile);
    if (rows is! List<dynamic>) {
      throw const FormatException('Invalid checkpoint index');
    }
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          row['id'] is! String ||
          !seen.add(row['id'] as String)) {
        throw const FormatException('Invalid checkpoint index identity');
      }
      final data = payloads[row['id']];
      if (data == null ||
          data['characterId'] != row['characterId'] ||
          data['requiresUnlock'] != row['requiresUnlock']) {
        throw const FormatException('Checkpoint index mismatch');
      }
    }
  }
  final stateDir = Directory('${root.path}/story/states');
  if (await stateDir.exists()) {
    final index = File('${root.path}/chat_sessions.json');
    final sessions = await index.exists() ? await read(index) : <dynamic>[];
    if (sessions is! List<dynamic>) {
      throw const FormatException('Invalid session index');
    }
    await for (final file in stateDir.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final data = await read(file);
      validateCharacterStateFile(data);
      final state = data as Map<String, dynamic>;
      if (!safe(state['sessionId']) ||
          file.uri.pathSegments.last != '${state['sessionId']}.json' ||
          !sessions.whereType<Map<String, dynamic>>().any(
            (s) =>
                s['id'] == state['sessionId'] &&
                s['characterId'] == state['characterId'],
          )) {
        throw const FormatException('State session ownership mismatch');
      }
      final history = state['history'] as List<dynamic>;
      if (history.isEmpty) continue;
      final current = CharacterStateView.fromJson(
        Map<String, dynamic>.from(history.last as Map),
      );
      final chat = File('${root.path}/chats/${current.sessionId}.json');
      final raw = await chat.exists() ? await read(chat) : null;
      final rows = raw is Map<String, dynamic> ? raw['messages'] : null;
      final messages = rows is List<dynamic>
          ? rows
                .whereType<Map<String, dynamic>>()
                .map(ChatMessage.fromJson)
                .toList()
          : <ChatMessage>[];
      if (current.anchor != null && !current.anchor!.matches(messages)) {
        warnings.add(
          'State anchor no longer matches ${current.sessionId}; only valid historical state or unknown will be shown.',
        );
      }
    }
  }
  return warnings;
}
