import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/migration/legacy_novel_chat_migration_service.dart';

void main() {
  test('persists a loadable target before deleting legacy files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'whisnya_novel_migration_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: directory);
    final book = _book();
    final time = DateTime(2026);
    await storage.saveNovel(book);
    await storage.saveSettings(
      const AppSettings(userProfile: UserProfile(name: '全局用户')),
    );
    await storage.saveNovelChat(book.id, [
      ChatMessage(role: 'user', content: '旧消息', time: time),
    ]);
    await storage.saveSummary(
      ChatSummary(
        characterId: 'novel_chat_${book.id}',
        summary: '旧总结',
        updatedAt: time,
        summarizedMessageCount: 1,
      ),
    );

    final result = await LegacyNovelChatMigrationService(storage).migrateAll();

    expect(result.migratedNovelCount, 1);
    final session = (await storage.loadTheaterSessions()).single;
    expect(session.boundNovelId, book.id);
    expect(session.userParticipant?.name, '全局用户');
    expect(
      (await storage.loadTheaterMessages(session.id)).single.content,
      '旧消息',
    );
    expect(await storage.legacyNovelChatDataExists(book.id), isFalse);
  });

  test('migrates messages and summary without losing metadata', () async {
    final book = _book(selectedRoleIndex: 1, userRoleIndex: 0);
    final firstTime = DateTime(2026, 1, 1, 10);
    final lastTime = DateTime(2026, 1, 1, 11);
    final storage = _MemoryStorage(
      books: [book],
      chats: {
        book.id: ChatSession(
          characterId: book.id,
          messages: [
            ChatMessage(role: 'user', content: '用户消息', time: firstTime),
            ChatMessage(
              role: 'assistant',
              content: '角色消息',
              time: lastTime,
              endpointId: 'endpoint',
              endpointName: 'Endpoint',
              model: 'model',
            ),
            ChatMessage(role: 'system', content: '系统消息', time: lastTime),
          ],
        ),
      },
      summaries: {
        book.id: ChatSummary(
          characterId: 'novel_chat_${book.id}',
          summary: '旧总结',
          updatedAt: lastTime,
          summarizedMessageCount: 2,
        ),
      },
    );

    final result = await LegacyNovelChatMigrationService(storage).migrateAll();

    expect(result.migratedNovelCount, 1);
    expect(result.migratedMessageCount, 3);
    expect(result.failedNovelIds, isEmpty);
    expect(storage.deleted, contains(book.id));
    final session = storage.sessions.values.single;
    expect(session.boundNovelId, book.id);
    expect(session.userParticipant?.name, '甲');
    expect(session.aiParticipants.first.name, '乙');
    expect(session.theaterSummary, '旧总结');
    expect(session.summarizedMessageCount, 2);
    final messages = storage.theaterMessages[session.id]!;
    expect(messages.map((item) => item.content), ['用户消息', '角色消息', '系统消息']);
    expect(messages.first.time, firstTime);
    expect(messages[1].endpointId, 'endpoint');
    expect(messages[1].endpointName, 'Endpoint');
    expect(messages[1].model, 'model');
    expect(messages[2].speakerType, TheaterSpeakerType.system);
    expect(messages.map((item) => item.round), orderedEquals([1, 1, 1]));
  });

  test(
    'handles message-only, summary-only, missing roles and bad indexes',
    () async {
      final messageOnly = _book(id: 'message', selectedRoleIndex: 99);
      final summaryOnly = _book(id: 'summary', roles: const []);
      final storage = _MemoryStorage(
        books: [messageOnly, summaryOnly],
        chats: {
          messageOnly.id: ChatSession(
            characterId: messageOnly.id,
            messages: [_message('assistant', 'only message')],
          ),
        },
        summaries: {
          summaryOnly.id: ChatSummary(
            characterId: 'novel_chat_${summaryOnly.id}',
            summary: 'only summary',
            updatedAt: DateTime(2026),
            summarizedMessageCount: 99,
          ),
        },
      );

      final result = await LegacyNovelChatMigrationService(
        storage,
      ).migrateAll();

      expect(result.migratedNovelCount, 2);
      final messageSession = storage.sessions['theater_legacy_novel_message']!;
      expect(messageSession.aiParticipants.first.name, '甲');
      final summarySession = storage.sessions['theater_legacy_novel_summary']!;
      expect(summarySession.aiParticipants.single.name, '小说角色');
      expect(summarySession.aiParticipants.single.background, 'novel summary');
      expect(storage.theaterMessages[summarySession.id], isEmpty);
    },
  );

  test(
    'is idempotent and resumes after target was partially written',
    () async {
      final book = _book();
      final storage = _MemoryStorage(
        books: [book],
        settings: const AppSettings(userProfile: UserProfile(name: '全局用户')),
        chats: {
          book.id: ChatSession(
            characterId: book.id,
            messages: [_message('user', 'one'), _message('assistant', 'two')],
          ),
        },
      );
      storage.sessions['theater_legacy_novel_${book.id}'] = TheaterSession(
        id: 'theater_legacy_novel_${book.id}',
        title: 'partial',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
      );

      final service = LegacyNovelChatMigrationService(storage);
      final first = await service.migrateAll();
      final second = await service.migrateAll();

      expect(first.migratedNovelCount, 1);
      expect(second.migratedNovelCount, 0);
      expect(storage.sessions, hasLength(1));
      expect(storage.theaterMessages.values.single, hasLength(2));
      expect(storage.sessions.values.single.userParticipant?.name, '全局用户');
      expect(
        storage.theaterMessages.values.single.first.speakerId,
        storage.sessions.values.single.userParticipantId,
      );
      expect(storage.theaterMessages.values.single.first.speakerName, '全局用户');
      expect(
        storage.theaterMessages.values.single.map((item) => item.id).toSet(),
        hasLength(2),
      );
    },
  );

  test('save or verification failure retains old data and continues', () async {
    final failed = _book(id: 'failed');
    final valid = _book(id: 'valid');
    final storage = _MemoryStorage(
      books: [failed, valid],
      chats: {
        failed.id: ChatSession(
          characterId: failed.id,
          messages: [_message('user', 'failed')],
        ),
        valid.id: ChatSession(
          characterId: valid.id,
          messages: [_message('user', 'valid')],
        ),
      },
      failSaveMessagesFor: {'failed'},
    );

    final result = await LegacyNovelChatMigrationService(storage).migrateAll();

    expect(result.failedNovelIds, ['failed']);
    expect(result.migratedNovelCount, 1);
    expect(storage.chats, contains('failed'));
    expect(storage.deleted, contains('valid'));

    final verifyStorage = _MemoryStorage(
      books: [failed],
      chats: {
        failed.id: ChatSession(
          characterId: failed.id,
          messages: [_message('user', 'failed')],
        ),
      },
      failVerificationFor: {'failed'},
    );
    final verifyResult = await LegacyNovelChatMigrationService(
      verifyStorage,
    ).migrateAll();
    expect(verifyResult.failedNovelIds, ['failed']);
    expect(verifyStorage.chats, contains('failed'));
    expect(verifyStorage.deleted, isEmpty);
  });
}

final class _MemoryStorage extends LocalStorageService {
  _MemoryStorage({
    required this.books,
    Map<String, ChatSession>? chats,
    Map<String, ChatSummary>? summaries,
    this.settings = const AppSettings(),
    this.failSaveMessagesFor = const {},
    this.failVerificationFor = const {},
  }) : chats = chats ?? {},
       summaries = summaries ?? {},
       super();

  final List<NovelBook> books;
  final AppSettings settings;
  final Map<String, ChatSession> chats;
  final Map<String, ChatSummary> summaries;
  final Set<String> failSaveMessagesFor;
  final Set<String> failVerificationFor;
  final sessions = <String, TheaterSession>{};
  final theaterMessages = <String, List<TheaterMessage>>{};
  final deleted = <String>{};

  @override
  Future<List<NovelBook>> loadNovels() async => books;

  @override
  Future<AppSettings> loadSettings() async => settings;

  @override
  Future<bool> legacyNovelChatDataExists(String novelId) async =>
      chats.containsKey(novelId) || summaries.containsKey(novelId);

  @override
  Future<ChatSession> loadNovelChat(String novelId) async =>
      chats[novelId] ?? ChatSession.empty(novelId);

  @override
  Future<ChatSummary> loadSummary(String characterId) async {
    final novelId = characterId.replaceFirst('novel_chat_', '');
    return summaries[novelId] ?? ChatSummary.empty(characterId);
  }

  @override
  Future<void> saveTheaterSession(TheaterSession session) async {
    sessions[session.id] = session;
  }

  @override
  Future<void> saveTheaterMessages(
    String sessionId,
    List<TheaterMessage> messages,
  ) async {
    final novelId = sessionId.replaceFirst('theater_legacy_novel_', '');
    if (failSaveMessagesFor.contains(novelId)) {
      throw StorageException('save failed');
    }
    theaterMessages[sessionId] = [...messages];
  }

  @override
  Future<List<TheaterSession>> loadTheaterSessions() async =>
      sessions.values.toList();

  @override
  Future<List<TheaterMessage>> loadTheaterMessages(String sessionId) async {
    final novelId = sessionId.replaceFirst('theater_legacy_novel_', '');
    if (failVerificationFor.contains(novelId)) return const [];
    return theaterMessages[sessionId] ?? const [];
  }

  @override
  Future<void> deleteLegacyNovelChatData(String novelId) async {
    deleted.add(novelId);
    chats.remove(novelId);
    summaries.remove(novelId);
  }
}

NovelBook _book({
  String id = 'novel',
  List<NovelRoleCandidate> roles = const [
    NovelRoleCandidate(
      name: '甲',
      description: '',
      personality: '',
      speakingStyle: '',
      background: '',
    ),
    NovelRoleCandidate(
      name: '乙',
      description: '',
      personality: '',
      speakingStyle: '',
      background: '',
    ),
  ],
  int selectedRoleIndex = -1,
  int userRoleIndex = -1,
}) => NovelBook(
  id: id,
  title: id,
  textPath: '$id.txt',
  summary: 'novel summary',
  roles: roles,
  selectedRoleIndex: selectedRoleIndex,
  userRoleIndex: userRoleIndex,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ChatMessage _message(String role, String content) =>
    ChatMessage(role: role, content: content, time: DateTime(2026));
