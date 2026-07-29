import 'local_storage_service.dart';
import 'storage/storage_paths.dart';

class NovelSummaryCache {
  const NovelSummaryCache({
    required this.novelId,
    required this.selectedChunks,
    required this.completedSummaries,
    required this.currentIndex,
  });

  final String novelId;
  final List<String> selectedChunks;
  final List<String> completedSummaries;
  final int currentIndex;

  bool get canResume =>
      selectedChunks.isNotEmpty &&
      currentIndex >= 0 &&
      currentIndex <= selectedChunks.length &&
      completedSummaries.length >= currentIndex;

  NovelSummaryCache copyWith({
    List<String>? completedSummaries,
    int? currentIndex,
  }) {
    return NovelSummaryCache(
      novelId: novelId,
      selectedChunks: selectedChunks,
      completedSummaries: completedSummaries ?? this.completedSummaries,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  factory NovelSummaryCache.fromJson(Map<String, dynamic> json) {
    return NovelSummaryCache(
      novelId: json['novelId'] as String? ?? '',
      selectedChunks: (json['selectedChunks'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      completedSummaries: (json['completedSummaries'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'novelId': novelId,
      'selectedChunks': selectedChunks,
      'completedSummaries': completedSummaries,
      'currentIndex': currentIndex,
    };
  }
}

class NovelSummaryService {
  const NovelSummaryService(this.storage);

  final LocalStorageService storage;

  Future<NovelSummaryCache?> loadCache(String novelId) async {
    final file = StoragePaths(
      await storage.appDataDirectory,
    ).novelSummaryCache(novelId);
    if (!await file.exists()) return null;
    try {
      final decoded = await storage.jsonStore.read(file, null);
      if (decoded is! Map<String, dynamic>) return null;
      final cache = NovelSummaryCache.fromJson(decoded);
      return cache.novelId == novelId && cache.canResume ? cache : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveCache(NovelSummaryCache cache) async {
    final file = StoragePaths(
      await storage.appDataDirectory,
    ).novelSummaryCache(cache.novelId);
    await storage.jsonStore.write(file, cache.toJson(), compact: true);
  }

  Future<void> deleteCache(String novelId) async {
    final file = StoragePaths(
      await storage.appDataDirectory,
    ).novelSummaryCache(novelId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
