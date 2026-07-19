import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/novel_book.dart';

void main() {
  test('novel book json keeps reader state', () {
    final book = NovelBook(
      id: 'book',
      title: 'Book',
      textPath: 'book.txt',
      readingMode: 1,
      chapterIndex: 3,
      fontSize: 22,
      lineHeight: 1.9,
      manualChapterTitles: const ['一', '二'],
      readerTheme: 2,
      bookmarkedChapterIndexes: const [1, 3],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 2),
    );

    expect(NovelBook.fromJson(book.toJson()).toJson(), book.toJson());
  });
}
