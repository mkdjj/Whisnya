import 'dart:convert';
import '../../models/app_character.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/chat_summary.dart';
import '../../models/message_anchor.dart';
import '../local_storage_service.dart';
import '../storage/storage_paths.dart';
import '../../models/character_state.dart';
import 'character_state_service.dart';
import 'story_backup_validation.dart';

class StoryCheckpoint {
  StoryCheckpoint(Map<String, dynamic> data)
    : _data = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  final Map<String, dynamic> _data;
  String get id => _data['id'] as String;
  String get title => _data['title'] as String;
  String get characterId => _data['characterId'] as String;
  String get characterName => _data['characterNameSnapshot'] as String;
  bool get requiresUnlock => _data['requiresUnlock'] == true;
  String get contentHash => _data['contentHash'] as String;
  MessageAnchor get anchor =>
      MessageAnchor.fromJson(Map<String, dynamic>.from(_data['anchor'] as Map));
  List<ChatMessage> get messages => (_data['messages'] as List)
      .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
      .toList();
  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;
}

/// Immutable checkpoint publication and journaled, index-last branch creation.
class StoryCheckpointService {
  StoryCheckpointService(this.storage, {this.authorize});
  final LocalStorageService storage;
  final Future<bool> Function(String characterId, bool requiresUnlock)?
  authorize;
  Future<StoragePaths> get _paths async =>
      StoragePaths(await storage.appDataDirectory);
  void _safe(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Unsafe story identity');
    }
  }

  Future<bool> _access(String id, bool locked) async {
    final characters = await storage.loadCharacters();
    final required = locked || characters.any((c) => c.id == id && c.isLocked);
    if (required && (authorize == null || !await authorize!(id, true))) {
      throw StateError('需要解锁 / Unlock required');
    }
    return required;
  }

  Future<List<Map<String, dynamic>>> list({String? characterId}) async {
    final paths = await _paths;
    final rows = await storage.jsonStore.read(
      paths.checkpointsIndex,
      <dynamic>[],
    );
    final characters = await storage.loadCharacters();
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .where((r) => characterId == null || r['characterId'] == characterId)
        .map((r) {
          final locked =
              r['requiresUnlock'] == true ||
              characters.any((c) => c.id == r['characterId'] && c.isLocked);
          return {
            ...r,
            if (locked) 'title': '已锁定的剧情存档',
            'requiresUnlock': locked,
          };
        })
        .toList();
  }

  Future<StoryCheckpoint> load(String id) async {
    final epoch = storage.datasetEpoch;
    _safe(id);
    final raw = await storage.jsonStore.read(
      (await _paths).checkpoint(id),
      null,
    );
    if (raw is! Map<String, dynamic>) throw StateError('剧情存档不存在');
    await _access(raw['characterId'] as String, raw['requiresUnlock'] == true);
    if (epoch != storage.datasetEpoch) throw StateError('数据已更新');
    return StoryCheckpoint(raw);
  }

  Future<StoryCheckpoint> create({
    required ChatSession source,
    required AppCharacter character,
    required MessageAnchor anchor,
    required String title,
    Map<String, dynamic>? initialState,
  }) async {
    final epoch = storage.datasetEpoch;
    final protected = await _access(character.id, character.isLocked);
    final paths = await _paths;
    return storage.jsonStore.maintain(() async {
      if (epoch != storage.datasetEpoch ||
          anchor.sessionId != source.id ||
          source.characterId != character.id) {
        throw StateError('对话已变化，请重新选择');
      }
      final currentCharacters = await storage.jsonStore.read(
        paths.characters,
        <dynamic>[],
      );
      final currentCharacter = (currentCharacters as List)
          .whereType<Map<String, dynamic>>()
          .where((c) => c['id'] == character.id)
          .firstOrNull;
      if (currentCharacter == null ||
          (currentCharacter['isLocked'] == true && !protected)) {
        throw StateError('角色或私密状态已变化，请重新选择');
      }
      final sessions = await storage.jsonStore.read(
        paths.chatSessions,
        <dynamic>[],
      );
      if (!(sessions as List).any(
        (s) =>
            s is Map &&
            s['id'] == source.id &&
            s['characterId'] == character.id,
      )) {
        throw StateError('对话不存在');
      }
      final messages = await storage.loadChatBySession(source);
      if (!anchor.matches(messages)) throw StateError('对话已变化，请重新选择');
      final index = messages.indexWhere((m) => m.id == anchor.messageId);
      final target = messages[index];
      if (initialState != null) {
        final state = CharacterStateView.fromJson(initialState);
        if (state.sessionId != source.id ||
            state.characterId != character.id ||
            (state.anchor != null &&
                !state.anchor!.matches(messages.take(index + 1).toList()))) {
          throw StateError('状态不属于此剧情前缀');
        }
      }
      if ((!target.isUser && !target.isAssistant) ||
          target.effectiveContent.trim().isEmpty ||
          target.isAssistant && target.effectiveReplyState != 'completed') {
        throw StateError('请选择已保存的完整消息');
      }
      final prefix = messages
          .take(index + 1)
          .where(
            (m) =>
                (m.isUser || m.isAssistant) &&
                m.effectiveContent.trim().isNotEmpty,
          )
          .map(
            (m) => {
              ...m.toJson()
                ..remove('variants')
                ..remove('selectedVariantIndex'),
              'sourceVariantId': logicalVariantId(m),
            },
          )
          .toList();
      final immutable = <String, dynamic>{
        'schemaVersion': 1,
        'characterId': character.id,
        'characterNameSnapshot': character.name,
        'sourceSessionId': source.id,
        'sourceSessionTitle': source.title,
        'branchRootSessionId': source.branchRootSessionId ?? source.id,
        'anchor': anchor.toJson(),
        'messages': prefix,
        'initialState': initialState,
        'contextPolicy': 'isolated',
      };
      final checkpoint = StoryCheckpoint({
        ...immutable,
        'id': newStoryId(),
        'title': title.trim().isEmpty ? '剧情存档' : title.trim(),
        'createdAt': DateTime.now().toIso8601String(),
        'requiresUnlock': protected,
        'contentHash': checkpointContentHash(immutable),
      });
      final rows = await storage.jsonStore.read(
        paths.checkpointsIndex,
        <dynamic>[],
      );
      final pending = await storage.jsonStore.read(
        paths.checkpointTransactions,
        <dynamic>[],
      );
      await storage.jsonStore.write(paths.checkpointTransactions, [
        ...pending as List,
        checkpoint.id,
      ]);
      await storage.jsonStore.write(
        paths.checkpoint(checkpoint.id),
        checkpoint.toJson(),
      );
      try {
        await storage.jsonStore.write(paths.checkpointsIndex, [
          ...rows as List,
          _summary(checkpoint),
        ]);
      } catch (_) {
        final file = paths.checkpoint(checkpoint.id);
        if (await file.exists()) await file.delete();
        rethrow;
      }
      try {
        await storage.jsonStore.write(paths.checkpointTransactions, pending);
      } on Object {
        /* Recovery can finish after committed publication. */
      }
      return checkpoint;
    });
  }

  Map<String, dynamic> _summary(StoryCheckpoint c) => {
    'id': c.id,
    'title': c.title,
    'characterId': c.characterId,
    'requiresUnlock': c.requiresUnlock,
  };
  Future<void> rename(String id, String title) async {
    final snapshot = await load(id);
    final epoch = storage.datasetEpoch;
    final paths = await _paths;
    await storage.jsonStore.maintain(() async {
      if (epoch != storage.datasetEpoch) throw StateError('数据已更新');
      final current = await storage.jsonStore.read(paths.checkpoint(id), null);
      if (current is! Map<String, dynamic>) throw StateError('存档不存在');
      final updated = StoryCheckpoint({
        ...current,
        'title': title.trim().isEmpty ? snapshot.title : title.trim(),
      });
      await storage.jsonStore.write(paths.checkpoint(id), updated.toJson());
      final rows = await storage.jsonStore.read(
        paths.checkpointsIndex,
        <dynamic>[],
      );
      await storage.jsonStore.write(
        paths.checkpointsIndex,
        (rows as List)
            .map((r) => r is Map && r['id'] == id ? _summary(updated) : r)
            .toList(),
      );
    });
  }

  Future<void> delete(String id) async {
    await load(id);
    final paths = await _paths;
    await storage.jsonStore.maintain(() async {
      final rows = await storage.jsonStore.read(
        paths.checkpointsIndex,
        <dynamic>[],
      );
      await storage.jsonStore.write(
        paths.checkpointsIndex,
        (rows as List).where((r) => r is! Map || r['id'] != id).toList(),
      );
      final file = paths.checkpoint(id);
      if (await file.exists()) await file.delete();
    });
  }

  Future<ChatSession> fork(String checkpointId, {required String title}) async {
    final epoch = storage.datasetEpoch;
    final checkpoint = await load(checkpointId);
    final authorizedProtected = await _access(
      checkpoint.characterId,
      checkpoint.requiresUnlock,
    );
    final characters = await storage.loadCharacters();
    if (!characters.any((c) => c.id == checkpoint.characterId)) {
      throw StateError('原角色已删除，无法继续此存档');
    }
    final paths = await _paths;
    return storage.jsonStore.maintain(() async {
      if (epoch != storage.datasetEpoch) throw StateError('数据已更新');
      final checkpointIndex = await storage.jsonStore.read(
        paths.checkpointsIndex,
        <dynamic>[],
      );
      final saved = await storage.jsonStore.read(
        paths.checkpoint(checkpointId),
        null,
      );
      final currentCharacters = await storage.jsonStore.read(
        paths.characters,
        <dynamic>[],
      );
      final currentCharacter = (currentCharacters as List)
          .whereType<Map<String, dynamic>>()
          .where((c) => c['id'] == checkpoint.characterId)
          .firstOrNull;
      if (currentCharacter == null ||
          saved is! Map<String, dynamic> ||
          !(checkpointIndex as List).any(
            (r) => r is Map && r['id'] == checkpointId,
          )) {
        throw StateError('存档或原角色已删除');
      }
      if (saved['contentHash'] != checkpoint.contentHash ||
          ((saved['requiresUnlock'] == true ||
                  currentCharacter['isLocked'] == true) &&
              !authorizedProtected)) {
        throw StateError('私密状态或存档已变化，请重新打开');
      }
      final raw = checkpoint.toJson();
      final now = DateTime.now();
      final session = ChatSession(
        id: newStoryId(),
        characterId: checkpoint.characterId,
        title: title,
        createdAt: now,
        updatedAt: now,
        lastUsedAt: now,
        openingMessageInitialized: true,
        messageCount: checkpoint.messages.length,
        isStoryBranch: true,
        parentSessionId: raw['sourceSessionId'] as String,
        sourceCheckpointId: checkpointId,
        branchRootSessionId: raw['branchRootSessionId'] as String,
        branchFromMessageId: checkpoint.anchor.messageId,
        branchFromVariantId: checkpoint.anchor.variantId,
        sourceSessionTitle: raw['sourceSessionTitle'] as String,
      );
      final journal = await storage.jsonStore.read(
        paths.storyTransactions,
        <dynamic>[],
      );
      await storage.jsonStore.write(paths.storyTransactions, [
        ...journal as List,
        session.id,
      ]);
      await storage.jsonStore.write(paths.chatBySession(session.id), {
        'sessionId': session.id,
        'characterId': session.characterId,
        'messages': checkpoint.messages.map((m) => m.toJson()).toList(),
      });
      await storage.jsonStore.write(
        paths.summaryBySession(session.id),
        ChatSummary.empty(session.characterId, session.id).toJson(),
      );
      if (raw['initialState'] is Map) {
        final state = Map<String, dynamic>.from(raw['initialState'] as Map);
        await CharacterStateService(storage).initializeState(
          session.id,
          session.characterId,
          CharacterStateView.fromJson(state),
        );
      }
      final rows = await storage.jsonStore.read(
        paths.chatSessions,
        <dynamic>[],
      );
      await storage.jsonStore.write(paths.chatSessions, [
        ...rows as List,
        session.toJson(),
      ]);
      // Publication already committed. A failed cleanup is recovered on startup;
      // it must not turn success into a retry that creates a duplicate branch.
      try {
        await storage.jsonStore.write(paths.storyTransactions, journal);
      } on Object {
        /* journal retains committed identity */
      }
      return session;
    });
  }

  static Future<void> recover(LocalStorageService storage) async {
    final paths = StoragePaths(await storage.appDataDirectory);
    await storage.jsonStore.maintain(() async {
      final pendingCheckpoints = await storage.jsonStore.read(
        paths.checkpointTransactions,
        <dynamic>[],
      );
      if (pendingCheckpoints is List && pendingCheckpoints.isNotEmpty) {
        final index = await storage.jsonStore.read(
          paths.checkpointsIndex,
          <dynamic>[],
        );
        final published = (index as List)
            .whereType<Map<String, dynamic>>()
            .map((r) => r['id'])
            .toSet();
        for (final id in pendingCheckpoints.whereType<String>()) {
          if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
              published.contains(id)) {
            continue;
          }
          final file = paths.checkpoint(id);
          if (await file.exists()) await file.delete();
        }
        await storage.jsonStore.write(
          paths.checkpointTransactions,
          <dynamic>[],
        );
      }
      final journal = await storage.jsonStore.read(
        paths.storyTransactions,
        <dynamic>[],
      );
      if (journal is! List || journal.isEmpty) return;
      final rows = await storage.jsonStore.read(
        paths.chatSessions,
        <dynamic>[],
      );
      final ids = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((r) => r['id'])
          .toSet();
      for (final id in journal.whereType<String>()) {
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) || ids.contains(id)) {
          continue;
        }
        for (final file in [
          paths.chatBySession(id),
          paths.summaryBySession(id),
          paths.characterState(id),
        ]) {
          if (await file.exists()) await file.delete();
        }
      }
      await storage.jsonStore.write(paths.storyTransactions, <dynamic>[]);
    });
  }
}
