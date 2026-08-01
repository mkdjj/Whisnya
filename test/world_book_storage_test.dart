import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/services/chat/chat_session_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/storage_paths.dart';

void main() {
  late Directory directory;
  late ChatSessionService service;
  late StoragePaths paths;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whisnya_world_books_');
    service = ChatSessionService(root: directory);
    paths = StoragePaths(directory);
  });

  tearDown(() => directory.delete(recursive: true));

  test('saving a world book completes and persists it', () async {
    final book = _book('worldbook_1', name: '修仙世界');

    await expectLater(
      service.saveWorldBook(book).timeout(const Duration(seconds: 2)),
      completes,
    );

    final saved = await service.loadWorldBooks();
    expect(saved.single.id, 'worldbook_1');
    expect(saved.single.name, '修仙世界');
  });

  test('world book create update and delete preserve entry cleanup', () async {
    final book = _book('worldbook_1', name: '旧名称');
    await service.saveWorldBook(book).timeout(const Duration(seconds: 2));
    await service.saveWorldBookEntry(_entry('entry_1', book.id));

    expect((await service.loadWorldBooks()).single.name, '旧名称');

    await service.saveWorldBook(book.copyWith(name: '新名称'));
    expect((await service.loadWorldBooks()).single.name, '新名称');
    expect(await paths.worldBookEntries(book.id).exists(), isTrue);

    await service.deleteWorldBook(book.id);

    expect(await service.loadWorldBooks(), isEmpty);
    expect(await paths.worldBookEntries(book.id).exists(), isFalse);
  });

  test('world book entry create update and delete round trips', () async {
    final entry = _entry('entry_1', 'worldbook_1');
    await service.saveWorldBook(_book(entry.worldBookId));

    await service.saveWorldBookEntry(entry).timeout(const Duration(seconds: 2));
    expect(
      (await service.loadWorldBookEntries('worldbook_1')).single.content,
      '内容 entry_1',
    );

    await service.saveWorldBookEntry(
      entry.copyWith(content: '更新内容', enabled: false),
    );
    final updated = (await service.loadWorldBookEntries('worldbook_1')).single;
    expect(updated.content, '更新内容');
    expect(updated.enabled, isFalse);

    await service.deleteWorldBookEntry('worldbook_1', entry.id);
    expect(await service.loadWorldBookEntries('worldbook_1'), isEmpty);
  });

  test(
    'a queued world book delete prevents its entry file from returning',
    () async {
      final book = _book('worldbook_1');
      await service.saveWorldBook(book);

      final deleteFuture = service.deleteWorldBook(book.id);
      final saveResult = service
          .saveWorldBookEntry(_entry('late_entry', book.id))
          .then<Object?>(
            (_) => null,
            onError: (Object error, StackTrace _) => error,
          );

      await deleteFuture.timeout(const Duration(seconds: 2));
      final saveError = await saveResult.timeout(const Duration(seconds: 2));

      expect(saveError, isA<StateError>());
      expect(await service.loadWorldBooks(), isEmpty);
      expect(await paths.worldBookEntries(book.id).exists(), isFalse);
    },
  );

  test('concurrent world book and entry saves do not lose data', () async {
    await Future.wait([
      for (var index = 0; index < 6; index++)
        service.saveWorldBook(_book('worldbook_$index')),
    ]).timeout(const Duration(seconds: 2));

    await Future.wait([
      for (var index = 0; index < 6; index++)
        service.saveWorldBookEntry(_entry('entry_$index', 'worldbook_0')),
    ]).timeout(const Duration(seconds: 2));

    expect((await service.loadWorldBooks()).map((book) => book.id).toSet(), {
      for (var index = 0; index < 6; index++) 'worldbook_$index',
    });
    expect(
      (await service.loadWorldBookEntries(
        'worldbook_0',
      )).map((entry) => entry.id).toSet(),
      {for (var index = 0; index < 6; index++) 'entry_$index'},
    );
  });

  test('legacy keyword memory migration completes once', () async {
    final storage = LocalStorageService(appDataDirectory: directory);
    final character = AppCharacter.fromJson({
      'id': 'character_1',
      'name': '角色一',
    });
    final now = DateTime(2026);
    await storage.saveCharacter(character);
    await storage.saveCharacterMemory(
      CharacterMemoryEntry(
        id: 'legacy_memory_1',
        characterId: character.id,
        scope: MemoryScope.character,
        title: '宗门',
        content: '天剑宗位于北境',
        keywords: const ['天剑宗'],
        createdAt: now,
        updatedAt: now,
      ),
    );

    final memories = await storage
        .loadCharacterMemories(character.id)
        .timeout(const Duration(seconds: 2));
    final books = await storage.loadWorldBooks();
    final migratedBook = books.single;
    final entries = await storage.loadWorldBookEntries(migratedBook.id);
    final refreshedCharacter = (await storage.loadCharacters()).single;

    expect(memories, isEmpty);
    expect(migratedBook.id, 'legacy_worldbook_character_1');
    expect(entries.single.content, '天剑宗位于北境');
    expect(entries.single.keywords, ['天剑宗']);
    expect(refreshedCharacter.worldBookIds, [migratedBook.id]);

    await storage
        .loadCharacterMemories(character.id)
        .timeout(const Duration(seconds: 2));
    expect(await storage.loadWorldBooks(), hasLength(1));
    expect(await storage.loadWorldBookEntries(migratedBook.id), hasLength(1));
  });
}

WorldBook _book(String id, {String? name}) {
  final now = DateTime(2026);
  return WorldBook(
    id: id,
    name: name ?? '世界书 $id',
    description: '测试',
    createdAt: now,
    updatedAt: now,
  );
}

WorldBookEntry _entry(String id, String worldBookId) {
  final now = DateTime(2026);
  return WorldBookEntry(
    id: id,
    worldBookId: worldBookId,
    title: '词条 $id',
    content: '内容 $id',
    keywords: ['关键词$id'],
    createdAt: now,
    updatedAt: now,
  );
}
