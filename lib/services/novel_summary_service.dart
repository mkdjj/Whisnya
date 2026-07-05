import 'dart:convert';
import 'dart:io';

import 'local_storage_service.dart';

class NovelSummaryCache {
  const NovelSummaryCache({
    required this.novelId,
    required this.selectedChunkIndexes,
    required this.selectedChunks,
    required this.completedSummaries,
    required this.currentIndex,
    required this.endpointId,
    required this.updatedAt,
  });

  final String novelId;
  final List<int> selectedChunkIndexes;
  final List<String> selectedChunks;
  final List<String> completedSummaries;
  final int currentIndex;
  final String endpointId;
  final DateTime updatedAt;

  bool get canResume =>
      selectedChunks.isNotEmpty && currentIndex <= selectedChunks.length;

  NovelSummaryCache copyWith({
    List<String>? completedSummaries,
    int? currentIndex,
    DateTime? updatedAt,
  }) {
    return NovelSummaryCache(
      novelId: novelId,
      selectedChunkIndexes: selectedChunkIndexes,
      selectedChunks: selectedChunks,
      completedSummaries: completedSummaries ?? this.completedSummaries,
      currentIndex: currentIndex ?? this.currentIndex,
      endpointId: endpointId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory NovelSummaryCache.fromJson(Map<String, dynamic> json) {
    return NovelSummaryCache(
      novelId: json['novelId'] as String? ?? '',
      selectedChunkIndexes: (json['selectedChunkIndexes'] as List? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(),
      selectedChunks: (json['selectedChunks'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      completedSummaries: (json['completedSummaries'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      endpointId: json['endpointId'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'novelId': novelId,
      'selectedChunkIndexes': selectedChunkIndexes,
      'selectedChunks': selectedChunks,
      'completedSummaries': completedSummaries,
      'currentIndex': currentIndex,
      'endpointId': endpointId,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class NovelSummaryService {
  const NovelSummaryService(this.storage);

  final LocalStorageService storage;

  Future<NovelSummaryCache?> loadCache(String novelId) async {
    final file = await _cacheFile(novelId);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final cache = NovelSummaryCache.fromJson(decoded);
      return cache.novelId == novelId && cache.canResume ? cache : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveCache(NovelSummaryCache cache) async {
    final file = await _cacheFile(cache.novelId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(cache.toJson()), flush: true);
  }

  Future<void> deleteCache(String novelId) async {
    final file = await _cacheFile(novelId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _cacheFile(String novelId) async {
    final directory = await storage.appDataDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}novel_summary_cache${Platform.pathSeparator}$novelId.json',
    );
  }
}
