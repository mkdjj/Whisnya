import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/controllers/novel_reader_controller.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/services/novel_parser.dart';

void main() {
  test(
    'catalog preview is non-mutating and maps source positions on apply',
    () {
      final book = _book.copyWith(
        chapterIndex: 1,
        readingProgress: .5,
        bookmarkedChapterIndexes: [0, 1, 99],
        manualChapterTitles: ['old'],
      );
      final controller = NovelReaderController(book);
      controller.load(
        readChunks: [],
        chapters: const [
          NovelChapter(title: 'A', content: '', startOffset: 0, endOffset: 100),
          NovelChapter(
            title: 'B',
            content: '',
            startOffset: 100,
            endOffset: 200,
          ),
        ],
      );
      const chapters = [
        NovelChapter(title: 'C', content: '', startOffset: 0, endOffset: 120),
        NovelChapter(title: 'D', content: '', startOffset: 120, endOffset: 200),
      ];
      final next = controller.bookForCatalog(chapters, 'auto');
      expect(controller.book, same(book));
      expect(next.chapterIndex, 1);
      expect(next.readingProgress, .375);
      expect(next.bookmarkedChapterIndexes, [0]);
      expect(next.manualChapterTitles, isEmpty);
      controller.applyCatalog(next, chapters);
      expect(controller.readProgress, .375);
      expect(controller.chapters, chapters);
      expect(NovelBook.fromJson(next.toJson()).chapterRule, 'auto');
      final oldJson = next.toJson()..remove('chapterRule');
      expect(NovelBook.fromJson(oldJson).chapterRule, 'legacy');
    },
  );

  test('empty rebuild is safe and plain reading keeps whole-book progress', () {
    final controller = NovelReaderController(_book.copyWith(readingMode: 0));
    final next = controller.bookForCatalog([], 'paragraphs');
    expect(next.chapterIndex, 0);
    expect(next.readingProgress, .4);
    expect(next.bookmarkedChapterIndexes, isEmpty);
  });

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
    expect(controller.readProgress, 0.4);
    expect(controller.offsetForMaxExtent(250), 100);
    final nextChapter = controller.bookForChapter(99);
    expect(nextChapter.chapterIndex, 1);
    expect(nextChapter.readingProgress, 0);
    final bookmarked = controller.bookWithToggledCurrentBookmark();
    expect(bookmarked.bookmarkedChapterIndexes, [0, 2]);

    expect(controller.search('目标').target, NovelReaderSearchTarget.chapter);
    expect(controller.search('目标').index, 1);
    expect(controller.searchQuery, '目标');

    expect(controller.updateReadProgress(pixels: 50, maxExtent: 100), isTrue);
    expect(controller.readProgress, 0.5);
    expect(controller.bookWithReadProgress().readingProgress, 0.5);
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
  readingProgress: 0.4,
  bookmarkedChapterIndexes: const [2],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
