import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/screens/settings_screen.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/app_background.dart';

void main() {
  testWidgets('settings subpages use the dark theme base color', (
    tester,
  ) async {
    final storage = _WorldBookStorage();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: SettingsScreen(
            storage: storage,
            settings: const AppSettings(),
            onSettingsChanged: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('外观与语言'));
    await tester.pumpAndSettle();
    final background = find.byType(AppBackground).last;
    final box = tester.widget<ColoredBox>(
      find.ancestor(of: background, matching: find.byType(ColoredBox)).first,
    );
    expect(box.color, ThemeData.dark().scaffoldBackgroundColor);
  });
  testWidgets(
    'background percentage follows image visibility without reversing surface transparency',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = _WorldBookStorage();
      await tester.pumpWidget(_app(storage));
      await tester.tap(find.text('外观与语言'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('主题设置'));
      await tester.pumpAndSettle();
      Slider slider(String title) => tester.widget<Slider>(
        find.descendant(
          of: find
              .ancestor(of: find.text(title), matching: find.byType(Column))
              .first,
          matching: find.byType(Slider),
        ),
      );
      expect(slider('界面背景透明度').value, 1);
      expect(slider('底部导航栏透明度').value, 0);
      expect(slider('列表卡片透明度').value, 0);
      slider('界面背景透明度').onChangeEnd!(0);
      await tester.pumpAndSettle();
      expect(storage.savedSettings?.globalBackgroundOpacity, 0);
      slider('界面背景透明度').onChangeEnd!(1);
      await tester.pumpAndSettle();
      expect(storage.savedSettings?.globalBackgroundOpacity, 1);
    },
  );

  testWidgets(
    'world book settings lives in memory category and opens the global list',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = _WorldBookStorage()..books.add(_book('book_1', '测试世界书'));

      await tester.pumpWidget(_app(storage));
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('记忆与收藏'));
      await tester.pumpAndSettle();

      final continuous = find.byKey(
        const ValueKey('split-role-messages-setting'),
      );
      final worldBooks = find.byKey(const ValueKey('world-book-settings-tile'));
      expect(continuous, findsNothing);
      expect(worldBooks, findsOneWidget);

      await tester.tap(worldBooks);
      await tester.pumpAndSettle();

      expect(find.text('关键词世界书'), findsOneWidget);
      expect(find.text('测试世界书'), findsOneWidget);
    },
  );

  testWidgets('global world book settings creates and edits a book', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _WorldBookStorage()
      ..characters.add(_character(worldBookIds: const ['existing_book']));

    await tester.pumpWidget(_app(storage));
    await tester.tap(find.text('记忆与收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-book-settings-tile')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, '添加世界书'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新世界书');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(storage.books.single.name, '新世界书');
    expect(find.text('新世界书'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑世界书'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '已修改世界书');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(storage.books.single.name, '已修改世界书');
    expect(find.text('已修改世界书'), findsOneWidget);
    expect(storage.characters.single.worldBookIds, ['existing_book']);
  });

  testWidgets('global world book settings creates and edits keyword entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _WorldBookStorage()..books.add(_book('book_1', '测试世界书'));

    await tester.pumpWidget(_app(storage));
    await tester.tap(find.text('记忆与收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-book-settings-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试世界书'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, '添加词条'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '词条标题');
    await tester.enterText(find.byType(TextField).at(1), '词条内容');
    await tester.enterText(find.byType(TextField).at(2), '关键词');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(storage.entries['book_1']!.single.content, '词条内容');
    expect(find.text('词条标题'), findsOneWidget);

    await tester.tap(find.text('词条标题'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '已修改内容');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(storage.entries['book_1']!.single.content, '已修改内容');
    expect(find.textContaining('已修改内容'), findsOneWidget);
  });
}

Widget _app(_WorldBookStorage storage) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: appSupportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  home: Scaffold(
    body: SettingsScreen(
      storage: storage,
      settings: const AppSettings(),
      onSettingsChanged: () async {},
    ),
  ),
);

WorldBook _book(String id, String name) {
  final now = DateTime(2026);
  return WorldBook(
    id: id,
    name: name,
    description: '测试描述',
    createdAt: now,
    updatedAt: now,
  );
}

AppCharacter _character({List<String> worldBookIds = const []}) =>
    AppCharacter.fromJson({
      'id': 'character_1',
      'name': '测试角色',
      'worldBookIds': worldBookIds,
    });

final class _WorldBookStorage extends LocalStorageService {
  AppSettings? savedSettings;
  @override
  Future<void> saveSettings(AppSettings settings) async {
    savedSettings = settings;
  }

  final books = <WorldBook>[];
  final entries = <String, List<WorldBookEntry>>{};
  final characters = <AppCharacter>[];

  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig();

  @override
  Future<List<AppCharacter>> loadCharacters() async => [...characters];

  @override
  Future<List<NovelBook>> loadNovels() async => const [];

  @override
  Future<List<WorldBook>> loadWorldBooks() async => [...books];

  @override
  Future<void> saveWorldBook(WorldBook book) async {
    final index = books.indexWhere((item) => item.id == book.id);
    if (index < 0) {
      books.add(book);
    } else {
      books[index] = book;
    }
  }

  @override
  Future<List<WorldBookEntry>> loadWorldBookEntries(String worldBookId) async =>
      [...entries[worldBookId] ?? const <WorldBookEntry>[]];

  @override
  Future<void> saveWorldBookEntry(WorldBookEntry entry) async {
    final items = entries.putIfAbsent(entry.worldBookId, () => []);
    final index = items.indexWhere((item) => item.id == entry.id);
    if (index < 0) {
      items.add(entry);
    } else {
      items[index] = entry;
    }
  }

  @override
  Future<void> updateCharacterWorldBookReferences(
    String characterId,
    List<String> worldBookIds,
  ) async {
    final index = characters.indexWhere((item) => item.id == characterId);
    if (index >= 0) {
      characters[index] = characters[index].copyWith(
        worldBookIds: worldBookIds,
      );
    }
  }
}
