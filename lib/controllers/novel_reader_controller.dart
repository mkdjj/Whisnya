import '../models/novel_book.dart';
import '../services/novel_parser.dart';

enum NovelReaderSearchTarget { cleared, chapter, chunk, notFound }

final class NovelReaderSearchResult {
  const NovelReaderSearchResult(this.target, [this.index = -1]);

  final NovelReaderSearchTarget target;
  final int index;
}

final class NovelReaderController {
  NovelReaderController(this._book) : _readProgress = _book.readingProgress;

  NovelBook _book;
  var _readChunks = <String>[];
  var _chapters = <NovelChapter>[];
  var _searchQuery = '';
  double _readProgress;

  NovelBook get book => _book;
  List<String> get readChunks => _readChunks;
  List<NovelChapter> get chapters => _chapters;
  String get searchQuery => _searchQuery;
  double get readProgress => _readProgress;
  double offsetForMaxExtent(double maxExtent) =>
      maxExtent <= 0 ? 0 : maxExtent * _readProgress;

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

  NovelBook bookForCatalog(List<NovelChapter> chapters, String rule) {
    int locate(int offset) {
      final index = chapters.lastIndexWhere((c) => c.startOffset <= offset);
      return index < 0 ? 0 : index;
    }

    final current = _chapters.isEmpty ? null : _chapters[safeChapterIndex];
    final offset = current == null
        ? 0
        : current.startOffset +
              ((current.endOffset - current.startOffset) * _readProgress)
                  .round();
    final index = locate(offset);
    final target = chapters.isEmpty ? null : chapters[index];
    final bookmarks =
        _book.bookmarkedChapterIndexes
            .where((i) => i >= 0 && i < _chapters.length)
            .map((i) => locate(_chapters[i].startOffset))
            .toSet()
            .toList()
          ..sort();
    return _book.copyWith(
      chapterRule: rule,
      chapterIndex: index,
      readingProgress: _book.readingMode != 1
          ? _readProgress
          : target == null || target.endOffset <= target.startOffset
          ? 0
          : ((offset - target.startOffset) /
                    (target.endOffset - target.startOffset))
                .clamp(0, 1),
      bookmarkedChapterIndexes: chapters.isEmpty ? [] : bookmarks,
      manualChapterTitles: const [],
    );
  }

  void applyCatalog(NovelBook book, List<NovelChapter> chapters) {
    _book = book;
    _readProgress = book.readingProgress;
    replaceChapters(chapters);
  }

  NovelBook bookForChapter(int index) => _book.copyWith(
    chapterIndex: _chapters.isEmpty
        ? 0
        : index.clamp(0, _chapters.length - 1).toInt(),
    readingProgress: 0,
  );

  NovelBook bookWithReadProgress() =>
      _book.copyWith(readingProgress: _readProgress);

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
