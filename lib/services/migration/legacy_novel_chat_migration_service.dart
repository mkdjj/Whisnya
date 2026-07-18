import '../../models/chat_message.dart';
import '../../models/novel_book.dart';
import '../../models/theater.dart';
import '../../models/user_profile.dart';
import '../local_storage_service.dart';
import '../theater/novel_theater_factory.dart';

class LegacyNovelChatMigrationResult {
  const LegacyNovelChatMigrationResult({
    required this.migratedNovelCount,
    required this.migratedMessageCount,
    required this.failedNovelIds,
  });

  final int migratedNovelCount;
  final int migratedMessageCount;
  final List<String> failedNovelIds;

  List<String> get recoveryMessages => [
    if (migratedNovelCount > 0) '已将 $migratedNovelCount 本小说的旧聊天迁移到群聊',
    if (failedNovelIds.isNotEmpty) '部分小说聊天迁移失败，旧数据已保留，下次启动会重试',
  ];
}

class LegacyNovelChatMigrationService {
  const LegacyNovelChatMigrationService(
    this.storage, {
    this.factory = const NovelTheaterFactory(),
  });

  final LocalStorageService storage;
  final NovelTheaterFactory factory;

  Future<LegacyNovelChatMigrationResult> migrateAll() async {
    var migratedNovels = 0;
    var migratedMessages = 0;
    final failed = <String>[];
    final books = await storage.loadNovels();
    final userProfile = (await storage.loadSettings()).userProfile;
    for (final book in books) {
      try {
        if (!await storage.legacyNovelChatDataExists(book.id)) continue;
        final count = await _migrate(book, userProfile);
        if (count == null) continue;
        migratedNovels++;
        migratedMessages += count;
      } catch (_) {
        failed.add(book.id);
      }
    }
    return LegacyNovelChatMigrationResult(
      migratedNovelCount: migratedNovels,
      migratedMessageCount: migratedMessages,
      failedNovelIds: failed,
    );
  }

  Future<int?> _migrate(NovelBook book, UserProfile userProfile) async {
    final chat = await storage.loadNovelChat(book.id);
    final summary = await storage.loadSummary('novel_chat_${book.id}');
    if (chat.messages.isEmpty && summary.summary.trim().isEmpty) {
      await storage.deleteLegacyNovelChatData(book.id);
      return null;
    }
    final sessionId = 'theater_legacy_novel_${book.id}';
    final session = factory.createLegacySession(
      book,
      sessionId: sessionId,
      theaterSummary: summary.summary,
      summarizedMessageCount: summary.summarizedMessageCount,
      userProfile: userProfile,
    );
    final messages = _convertMessages(chat.messages, session);

    await storage.saveTheaterSession(session);
    await storage.saveTheaterMessages(sessionId, messages);
    await _verify(session, messages);
    await storage.deleteLegacyNovelChatData(book.id);
    return messages.length;
  }

  List<TheaterMessage> _convertMessages(
    List<ChatMessage> messages,
    TheaterSession session,
  ) {
    final user = session.userParticipant;
    final ai = session.aiParticipants.first;
    var round = 0;
    return [
      for (var index = 0; index < messages.length; index++)
        _convertMessage(
          messages[index],
          index: index,
          session: session,
          user: user,
          ai: ai,
          round: messages[index].isUser
              ? ++round
              : round == 0
              ? 1
              : round,
        ),
    ];
  }

  TheaterMessage _convertMessage(
    ChatMessage message, {
    required int index,
    required TheaterSession session,
    required TheaterParticipant? user,
    required TheaterParticipant ai,
    required int round,
  }) {
    final speakerType = message.isUser
        ? TheaterSpeakerType.user
        : message.isAssistant
        ? TheaterSpeakerType.role
        : TheaterSpeakerType.system;
    final speaker = switch (speakerType) {
      TheaterSpeakerType.user => user,
      TheaterSpeakerType.role => ai,
      TheaterSpeakerType.system => null,
    };
    return TheaterMessage(
      id: '${session.id}_legacy_$index',
      sessionId: session.id,
      round: round,
      speakerType: speakerType,
      speakerId: speaker?.id ?? '',
      speakerName:
          speaker?.name ??
          (speakerType == TheaterSpeakerType.user ? '我' : '系统'),
      content: message.content,
      endpointId: message.endpointId ?? '',
      endpointName: message.endpointName ?? '',
      model: message.model ?? '',
      time: message.time,
    );
  }

  Future<void> _verify(
    TheaterSession expectedSession,
    List<TheaterMessage> expectedMessages,
  ) async {
    final sessions = await storage.loadTheaterSessions();
    final session = sessions.where((item) => item.id == expectedSession.id);
    if (session.length != 1 ||
        session.single.boundNovelId != expectedSession.boundNovelId) {
      throw StorageException('迁移群聊验证失败');
    }
    final messages = await storage.loadTheaterMessages(expectedSession.id);
    if (messages.length != expectedMessages.length) {
      throw StorageException('迁移消息数量验证失败');
    }
    if (messages.isEmpty) return;
    for (final index in [0, messages.length - 1]) {
      if (messages[index].content != expectedMessages[index].content ||
          messages[index].time != expectedMessages[index].time) {
        throw StorageException('迁移消息内容验证失败');
      }
    }
  }
}
