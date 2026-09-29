import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/screens/novel/novel_screens.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

class _Storage extends LocalStorageService {
  _Storage(this.directory);
  final Directory directory;
  NovelBook? saved;
  @override
  Future<Directory> get appDataDirectory async => directory;
  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig();
  @override
  Future<String> loadNovelText(NovelBook book) async =>
      '第一章 开始\n模拟正文甲\n第二章 回来？\n模拟正文乙';
  @override
  Future<void> saveNovel(NovelBook book) async => saved = book;
}

void main() {
  testWidgets('catalog preview cancels without saving and applies explicitly', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('whisnya_catalog_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final storage = _Storage(directory);
    final book = NovelBook(
      id: 'sample',
      title: '模拟小说',
      textPath: 'sample.txt',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderScreen(
          storage: storage,
          aiService: AiService(),
          book: book,
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    Future<void> preview() async {
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('重新识别目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新识别目录'));
      await tester.pumpAndSettle();
      expect(find.text('应用目录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await preview();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(storage.saved, isNull);
    await preview();
    await tester.tap(find.text('应用目录'));
    await tester.pumpAndSettle();
    expect(storage.saved?.chapterRule, 'auto');
    expect(tester.takeException(), isNull);
  });
}
