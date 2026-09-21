import 'package:flutter/material.dart' show Characters;
import 'chat_message.dart';
import 'message_anchor.dart';

class MementoEntry {
  const MementoEntry({
    required this.sourceMessageId,
    this.sourceVariantId,
    required this.sourcePrefixDigest,
    required this.role,
    required this.speakerNameSnapshot,
    required this.time,
    required this.contentSnapshot,
    this.innerVoiceSnapshot = '',
    this.replyStateSnapshot = 'completed',
    this.avatarAssetId,
  });
  final String sourceMessageId,
      sourcePrefixDigest,
      role,
      speakerNameSnapshot,
      contentSnapshot,
      innerVoiceSnapshot,
      replyStateSnapshot;
  final String? sourceVariantId, avatarAssetId;
  final DateTime time;
  factory MementoEntry.capture({
    required String sessionId,
    required List<ChatMessage> messages,
    required int index,
    required String speakerName,
    String? avatarAssetId,
  }) {
    final m = messages[index];
    final a = MessageAnchor.capture(sessionId, messages, index);
    return MementoEntry(
      sourceMessageId: a.messageId,
      sourceVariantId: a.variantId,
      sourcePrefixDigest: a.prefixDigest,
      role: m.role,
      speakerNameSnapshot: speakerName,
      time: m.effectiveTime,
      contentSnapshot: m.effectiveContent,
      innerVoiceSnapshot: m.effectiveInnerVoice,
      replyStateSnapshot: m.effectiveReplyState,
      avatarAssetId: avatarAssetId,
    );
  }
  Map<String, dynamic> toJson() => {
    'sourceMessageId': sourceMessageId,
    'sourceVariantId': sourceVariantId,
    'sourcePrefixDigest': sourcePrefixDigest,
    'role': role,
    'speakerNameSnapshot': speakerNameSnapshot,
    'time': time.toIso8601String(),
    'contentSnapshot': contentSnapshot,
    'innerVoiceSnapshot': innerVoiceSnapshot,
    'replyStateSnapshot': replyStateSnapshot,
    'avatarAssetId': avatarAssetId,
  };
  factory MementoEntry.fromJson(Map<String, dynamic> j) => MementoEntry(
    sourceMessageId: j['sourceMessageId'] as String,
    sourceVariantId: j['sourceVariantId'] as String?,
    sourcePrefixDigest: j['sourcePrefixDigest'] as String,
    role: j['role'] as String,
    speakerNameSnapshot: j['speakerNameSnapshot'] as String,
    time: DateTime.parse(j['time'] as String),
    contentSnapshot: j['contentSnapshot'] as String,
    innerVoiceSnapshot: j['innerVoiceSnapshot'] as String? ?? '',
    replyStateSnapshot: j['replyStateSnapshot'] as String? ?? 'completed',
    avatarAssetId: j['avatarAssetId'] as String?,
  );
}

class MementoDraft {
  MementoDraft({
    required this.idempotencyKey,
    required this.title,
    required this.characterId,
    required this.characterNameSnapshot,
    required this.sessionTitleSnapshot,
    required this.sourceSessionId,
    this.sourceType = 'chat',
    required List<MementoEntry> entries,
    this.requiresUnlock = false,
    List<String> tags = const [],
    this.note = '',
  }) : entries = List.unmodifiable(entries),
       tags = List.unmodifiable(tags);
  final String idempotencyKey,
      title,
      characterId,
      characterNameSnapshot,
      sessionTitleSnapshot,
      sourceSessionId,
      sourceType,
      note;
  final List<MementoEntry> entries;
  final List<String> tags;
  final bool requiresUnlock;
  void validate() {
    if (sourceType != 'chat' && sourceType != 'autoStory') {
      throw ArgumentError('Invalid memento source type');
    }
    validateMetadata(title, tags, note);
    if (idempotencyKey.isEmpty ||
        entries.isEmpty ||
        entries.length > 50 ||
        entries.fold<int>(
              0,
              (n, e) => n + Characters(e.contentSnapshot).length,
            ) >
            100000 ||
        entries.any((e) => e.role != 'user' && e.role != 'assistant')) {
      throw ArgumentError('Select 1–50 messages, up to 100000 characters');
    }
  }
}

void validateMetadata(String title, List<String> tags, String note) {
  if (title.trim().isEmpty ||
      Characters(title).length > 80 ||
      tags.length > 8 ||
      tags.any((t) => Characters(t).length > 20) ||
      Characters(note).length > 500) {
    throw ArgumentError('Invalid title, tags or note');
  }
}

class MementoSnapshot extends MementoDraft {
  MementoSnapshot({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required super.idempotencyKey,
    required super.title,
    required super.characterId,
    required super.characterNameSnapshot,
    required super.sessionTitleSnapshot,
    required super.sourceSessionId,
    super.sourceType,
    required super.entries,
    super.requiresUnlock,
    super.tags,
    super.note,
  });
  final String id;
  final DateTime createdAt, updatedAt;
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'idempotencyKey': idempotencyKey,
    'title': title,
    'tags': tags,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'characterId': characterId,
    'characterNameSnapshot': characterNameSnapshot,
    'sessionTitleSnapshot': sessionTitleSnapshot,
    'sourceSessionId': sourceSessionId,
    'sourceType': sourceType,
    'requiresUnlock': requiresUnlock,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
  factory MementoSnapshot.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 1 || j['requiresUnlock'] is! bool) {
      throw const FormatException('Invalid collection schema');
    }
    final s = MementoSnapshot(
      id: j['id'] as String,
      idempotencyKey: j['idempotencyKey'] as String,
      title: j['title'] as String,
      characterId: j['characterId'] as String,
      characterNameSnapshot: j['characterNameSnapshot'] as String,
      sessionTitleSnapshot: j['sessionTitleSnapshot'] as String,
      sourceSessionId: j['sourceSessionId'] as String,
      sourceType: j['sourceType'] as String? ?? 'chat',
      entries: (j['entries'] as List)
          .map(
            (e) => MementoEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      requiresUnlock: j['requiresUnlock'] as bool,
      tags: (j['tags'] as List).cast<String>(),
      note: j['note'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
    );
    s.validate();
    return s;
  }
}

class MementoMetadataPatch {
  const MementoMetadataPatch({
    required this.id,
    required this.title,
    required this.tags,
    required this.note,
  });
  final String id, title, note;
  final List<String> tags;
}

class MementoQuery {
  const MementoQuery({this.characterId, this.tag, this.keyword = ''});
  final String? characterId, tag;
  final String keyword;
}

class MementoIndex {
  const MementoIndex({
    required this.id,
    required this.characterId,
    required this.title,
    required this.tags,
    required this.createdAt,
    required this.requiresUnlock,
  });
  final String id, characterId, title;
  final List<String> tags;
  final DateTime createdAt;
  final bool requiresUnlock;
}

enum SourceNavigationResult {
  found,
  sourceMissing,
  messageMissing,
  variantChanged,
  contentChanged,
}
