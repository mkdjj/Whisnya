import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/controllers/novel_reader_controller.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/services/novel_parser.dart';

void main() {
  test('owns chapter, bookmark, search, and progress state', () {
    final controller = NovelReaderController(_book);
    controller.load(
      readChunks: const ['开头内容', '目标片段'],
      chapters: const [
        NovelChapter(title: '第一章', content: '开头内容'),
        NovelChapter(title: '第二章', content: '目标章节'),
      ],
    );

    expect(controller.safeChapterIndex, 0);
    expect(controller.bookForChapter(99).chapterIndex, 1);
    final bookmarked = controller.bookWithToggledCurrentBookmark();
    expect(bookmarked.bookmarkedChapterIndexes, [0, 2]);

    expect(controller.search('目标').target, NovelReaderSearchTarget.chapter);
    expect(controller.search('目标').index, 1);
    expect(controller.searchQuery, '目标');

    expect(controller.updateReadProgress(pixels: 50, maxExtent: 100), isTrue);
    expect(controller.readProgress, 0.5);
    expect(
      controller.updateReadProgress(pixels: 50.5, maxExtent: 100),
      isFalse,
    );
  });
}

final _book = NovelBook(
  id: 'book',
  title: '小说',
  textPath: 'book.txt',
  readingMode: 1,
  chapterIndex: -3,
  bookmarkedChapterIndexes: const [2],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
