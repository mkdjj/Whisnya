import '../models/novel_book.dart';
import '../services/novel_parser.dart';

enum NovelReaderSearchTarget { cleared, chapter, chunk, notFound }

final class NovelReaderSearchResult {
  const NovelReaderSearchResult(this.target, [this.index = -1]);

  final NovelReaderSearchTarget target;
  final int index;
}

final class NovelReaderController {
  NovelReaderController(this._book);

  NovelBook _book;
  var _readChunks = <String>[];
  var _chapters = <NovelChapter>[];
  var _searchQuery = '';
  var _readProgress = 0.0;

  NovelBook get book => _book;
  List<String> get readChunks => _readChunks;
  List<NovelChapter> get chapters => _chapters;
  String get searchQuery => _searchQuery;
  double get readProgress => _readProgress;

  int get safeChapterIndex => _chapters.isEmpty
      ? 0
      : _book.chapterIndex.clamp(0, _chapters.length - 1).toInt();

  bool get isCurrentChapterBookmarked =>
      _book.bookmarkedChapterIndexes.contains(safeChapterIndex);

  void load({
    required List<String> readChunks,
    required List<NovelChapter> chapters,
  }) {
    _readChunks = [...readChunks];
    _chapters = [...chapters];
  }

  void updateBook(NovelBook book) => _book = book;
  void replaceChapters(List<NovelChapter> chapters) {
    _chapters = [...chapters];
  }

  NovelBook bookForChapter(int index) => _book.copyWith(
    chapterIndex: _chapters.isEmpty
        ? 0
        : index.clamp(0, _chapters.length - 1).toInt(),
  );

  NovelBook bookWithToggledCurrentBookmark() {
    final bookmarks = _book.bookmarkedChapterIndexes.toSet();
    if (!bookmarks.remove(safeChapterIndex)) {
      bookmarks.add(safeChapterIndex);
    }
    final sorted = bookmarks.toList()..sort();
    return _book.copyWith(bookmarkedChapterIndexes: sorted);
  }

  NovelReaderSearchResult search(String query) {
    _searchQuery = query.trim();
    if (_searchQuery.isEmpty) {
      return const NovelReaderSearchResult(NovelReaderSearchTarget.cleared);
    }
    final lower = _searchQuery.toLowerCase();
    if (_book.readingMode == 1 && _chapters.isNotEmpty) {
      final index = _chapters.indexWhere(
        (chapter) =>
            chapter.title.toLowerCase().contains(lower) ||
            chapter.content.toLowerCase().contains(lower),
      );
      return index < 0
          ? const NovelReaderSearchResult(NovelReaderSearchTarget.notFound)
          : NovelReaderSearchResult(NovelReaderSearchTarget.chapter, index);
    }
    final index = _readChunks.indexWhere(
      (chunk) => chunk.toLowerCase().contains(lower),
    );
    return index < 0
        ? const NovelReaderSearchResult(NovelReaderSearchTarget.notFound)
        : NovelReaderSearchResult(NovelReaderSearchTarget.chunk, index);
  }

  bool updateReadProgress({required double pixels, required double maxExtent}) {
    final next = maxExtent <= 0
        ? 1.0
        : (pixels / maxExtent).clamp(0, 1).toDouble();
    if ((next - _readProgress).abs() <= 0.01) return false;
    _readProgress = next;
    return true;
  }

  void resetReadProgress() => _readProgress = 0;
}
