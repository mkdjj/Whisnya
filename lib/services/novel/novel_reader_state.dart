import '../../models/novel_book.dart';

class NovelReaderState {
  const NovelReaderState({
    required this.chapterIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.theme,
    required this.bookmarks,
  });

  factory NovelReaderState.fromBook(NovelBook book) => NovelReaderState(
    chapterIndex: book.chapterIndex,
    fontSize: book.fontSize,
    lineHeight: book.lineHeight,
    theme: book.readerTheme,
    bookmarks: book.bookmarkedChapterIndexes,
  );

  final int chapterIndex;
  final double fontSize;
  final double lineHeight;
  final int theme;
  final List<int> bookmarks;
}
