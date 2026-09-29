import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/services/auto_story/auto_story_store.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/json_file_store.dart';

import 'auto_story_model_test.dart' show storyFixture;

class CountingJsonStore extends JsonFileStore {
  final storyLocks = <String>[];
  bool failIndexWrites = false;

  @override
  Future<T> synchronized<T>(File file, FutureOr<T> Function() action) {
    if (file.path.replaceAll('\\', '/').contains('/auto_stories/')) {
      storyLocks.add(file.path.split(RegExp(r'[/\\]')).last);
    }
    return super.synchronized(file, action);
  }

  @override
  Future<void> writeNow(File file, dynamic data, {bool compact = false}) {
    if (failIndexWrites && file.path.endsWith('auto_story_index.json')) {
      throw const FileSystemException('index unavailable');
    }
    return super.writeNow(file, data, compact: compact);
  }
}

void main() {
  late Directory dir;
  late CountingJsonStore json;
  late AutoStoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('auto-story-index-cost-');
    json = CountingJsonStore();
    store = AutoStoryStore(
      LocalStorageService(appDataDirectory: dir, jsonStore: json),
    );
    await store.createStory(storyFixture(id: 'one'));
    await store.createStory(storyFixture(id: 'two'));
    await store.createStory(storyFixture(id: 'three'));
    await store.repairIndex();
    json.storyLocks.clear();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<List<dynamic>> indexRows() async =>
      jsonDecode(await File('${dir.path}/auto_story_index.json').readAsString())
          as List<dynamic>;

  test('mutating one story does not scan unrelated story files', () async {
    await store.mutateStory(
      'one',
      (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Changed')),
    );

    expect(json.storyLocks, everyElement('one.json'));
    final rows = await indexRows();
    expect(rows, hasLength(3));
    expect(
      (rows.cast<Map<String, dynamic>>().singleWhere(
        (r) => r['id'] == 'one',
      ))['title'],
      'Changed',
    );
  });

  test(
    'deleting one story removes its index row without scanning others',
    () async {
      await store.deleteStory('two');

      expect(json.storyLocks, everyElement('two.json'));
      expect(
        (await indexRows()).cast<Map<String, dynamic>>().map((r) => r['id']),
        unorderedEquals(['one', 'three']),
      );
    },
  );

  test(
    'malformed index falls back to full scan and restores valid rows',
    () async {
      await File('${dir.path}/auto_story_index.json').writeAsString('{broken');
      json.storyLocks.clear();

      await store.mutateStory(
        'one',
        (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Recovered')),
      );

      expect(
        json.storyLocks,
        containsAll(['one.json', 'two.json', 'three.json']),
      );
      expect(
        (await indexRows()).cast<Map<String, dynamic>>().map((r) => r['id']),
        unorderedEquals(['one', 'two', 'three']),
      );
    },
  );

  test('malformed index row falls back to full scan', () async {
    final rows = (await indexRows()).cast<Map<String, dynamic>>();
    rows.first['actors'] = ['broken'];
    await File(
      '${dir.path}/auto_story_index.json',
    ).writeAsString(jsonEncode(rows));
    json.storyLocks.clear();

    await store.mutateStory(
      'one',
      (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Recovered')),
    );

    expect(
      json.storyLocks,
      containsAll(['one.json', 'two.json', 'three.json']),
    );
    final repaired = (await indexRows()).cast<Map<String, dynamic>>();
    expect(repaired.first['actors'], isNot(['broken']));
  });

  test(
    'failed index write forces a full repair on the next mutation',
    () async {
      json.failIndexWrites = true;
      await store.mutateStory(
        'one',
        (doc) => doc.copyWith(config: doc.config.copyWith(title: 'First')),
      );
      expect(store.indexNeedsRepair, isTrue);
      expect(
        (await store.listStories()).singleWhere((h) => h.id == 'one').title,
        'First',
      );
      json.failIndexWrites = false;
      json.storyLocks.clear();

      await store.mutateStory(
        'one',
        (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Second')),
      );

      expect(
        json.storyLocks,
        containsAll(['one.json', 'two.json', 'three.json']),
      );
      expect(store.indexNeedsRepair, isFalse);
      final rows = (await indexRows()).cast<Map<String, dynamic>>();
      expect(rows.singleWhere((r) => r['id'] == 'one')['title'], 'Second');
    },
  );

  test('two store instances preserve both concurrent index changes', () async {
    final peer = AutoStoryStore(
      LocalStorageService(appDataDirectory: dir, jsonStore: json),
    );
    await peer.listStories();
    json.storyLocks.clear();

    await Future.wait([
      store.mutateStory(
        'one',
        (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Alpha')),
      ),
      peer.mutateStory(
        'two',
        (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Beta')),
      ),
    ]);

    final rows = (await indexRows()).cast<Map<String, dynamic>>();
    expect(rows.singleWhere((r) => r['id'] == 'one')['title'], 'Alpha');
    expect(rows.singleWhere((r) => r['id'] == 'two')['title'], 'Beta');
    expect(rows, hasLength(3));
  });

  test('a writer lists peer-created stories after its own mutation', () async {
    final peer = AutoStoryStore(
      LocalStorageService(appDataDirectory: dir, jsonStore: json),
    );
    await peer.createStory(storyFixture(id: 'four'));
    await store.mutateStory(
      'one',
      (doc) => doc.copyWith(config: doc.config.copyWith(title: 'Changed')),
    );

    expect(
      (await store.listStories()).map((h) => h.id),
      unorderedEquals(['one', 'two', 'three', 'four']),
    );
  });

  test('usage write refreshes the cached header timestamp', () async {
    final token = await store.reserveRequest('one', RequestPurpose.plan);
    final before = (await store.listStories()).singleWhere(
      (h) => h.id == 'one',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));

    await store.recordUsage(token, totalTokens: 7);

    final doc = await store.loadStory('one');
    final header = (await store.listStories()).singleWhere(
      (h) => h.id == 'one',
    );
    expect(doc.updatedAt.isAfter(before.updatedAt), isTrue);
    expect(header.updatedAt, doc.updatedAt);
  });
}
