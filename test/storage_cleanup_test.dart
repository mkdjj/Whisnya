import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/novel_summary_service.dart';
import 'package:whisnya/services/storage/storage_paths.dart';

void main() {
  late Directory directory;
  late LocalStorageService storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('storage_cleanup_');
    storage = LocalStorageService(appDataDirectory: directory);
    await storage.saveSettings(const AppSettings());
  });

  tearDown(() => directory.delete(recursive: true));

  test('character deletion keeps an avatar referenced by theater', () async {
    final avatar = await storage.saveMediaImage(
      folder: 'avatars',
      characterId: 'character',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final character = AppCharacter.fromJson({
      'id': 'character',
      'name': 'Character',
      'avatar': avatar,
    });
    await storage.saveCharacter(character);
    await storage.saveTheaterSession(
      TheaterSession(
        id: 'theater',
        title: 'Theater',
        participants: [
          TheaterParticipant.fromAppCharacter(character, id: 'participant'),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );

    await storage.deleteCharacter(character.id);

    expect(await File(avatar).exists(), isTrue);
    expect(await storage.loadCharacters(), isEmpty);
  });

  test('theater deletion removes its unused media', () async {
    final avatar = await storage.saveMediaImage(
      folder: 'theater_avatars',
      characterId: 'theater',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final session = TheaterSession(
      id: 'theater',
      title: 'Theater',
      avatar: avatar,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await storage.saveTheaterSession(session);

    await storage.deleteTheaterSession(session.id);

    expect(await File(avatar).exists(), isFalse);
  });

  test('novel deletion removes its resumable summary cache', () async {
    final book = await storage.importNovelText(
      title: 'Novel',
      content: 'Content',
    );
    await NovelSummaryService(storage).saveCache(
      NovelSummaryCache(
        novelId: book.id,
        selectedChunks: const ['Content'],
        completedSummaries: const [],
        currentIndex: 0,
      ),
    );
    final cache = StoragePaths(directory).novelSummaryCache(book.id);
    expect(await cache.exists(), isTrue);

    await storage.deleteNovel(book);

    expect(await cache.exists(), isFalse);
  });

  test('manual cleanup removes media with no saved references', () async {
    final unused = await storage.saveMediaImage(
      folder: 'avatars',
      characterId: 'unused',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    final deleted = await storage.cleanupUnusedMedia();

    expect(deleted, 1);
    expect(await File(unused).exists(), isFalse);
  });

  test(
    'startup does not delete media when metadata may be incomplete',
    () async {
      final unreferenced = await storage.saveMediaImage(
        folder: 'avatars',
        characterId: 'unreferenced',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await storage.ensureReady();

      expect(await File(unreferenced).exists(), isTrue);
    },
  );
}
