import 'dart:convert';

import '../../models/api_config.dart';
import '../../models/novel_book.dart';
import '../../prompts.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';
import '../novel_summary_service.dart';

sealed class NovelAnalysisEvent {
  const NovelAnalysisEvent();
}

final class NovelAnalysisProgress extends NovelAnalysisEvent {
  const NovelAnalysisProgress(this.current, this.total);
  final int current;
  final int total;
}

final class NovelAnalysisCompleted extends NovelAnalysisEvent {
  const NovelAnalysisCompleted(this.summary, this.roles);
  final String summary;
  final List<NovelRoleCandidate> roles;
}

class NovelAnalysisService {
  const NovelAnalysisService(this._gateway, this._cacheStore);

  final AiGateway _gateway;
  final NovelSummaryService _cacheStore;

  Stream<NovelAnalysisEvent> analyze({
    required String novelId,
    required List<String> chunks,
    required AiEndpointConfig endpoint,
    NovelSummaryCache? resumeCache,
    AiCancelToken? cancelToken,
  }) async* {
    var cache =
        resumeCache ??
        NovelSummaryCache(
          novelId: novelId,
          selectedChunkIndexes: [for (var i = 0; i < chunks.length; i++) i],
          selectedChunks: chunks,
          completedSummaries: const [],
          currentIndex: 0,
          endpointId: endpoint.id,
          updatedAt: DateTime.now(),
        );
    final summaries = [...cache.completedSummaries];
    await _cacheStore.saveCache(cache);
    for (
      var i = cache.currentIndex.clamp(0, chunks.length);
      i < chunks.length;
      i++
    ) {
      final summary = await _request(endpoint, [
        {'role': 'system', 'content': '你是小说分析助手，只提炼原文信息。'},
        {
          'role': 'user',
          'content': PromptBuilder.buildNovelChunkPrompt(
            chunks[i],
            i + 1,
            chunks.length,
          ),
        },
      ], cancelToken);
      summaries.add(summary);
      cache = cache.copyWith(
        completedSummaries: summaries,
        currentIndex: i + 1,
        updatedAt: DateTime.now(),
      );
      await _cacheStore.saveCache(cache);
      yield NovelAnalysisProgress(i + 1, chunks.length);
    }
    final merged = await _request(endpoint, [
      {'role': 'system', 'content': '你只输出可解析 JSON。'},
      {
        'role': 'user',
        'content': PromptBuilder.buildNovelMergePrompt(summaries),
      },
    ], cancelToken);
    final result = parseNovelAnalysisResult(merged);
    await _cacheStore.deleteCache(novelId);
    yield NovelAnalysisCompleted(result.summary, result.roles);
  }

  Future<String> _request(
    AiEndpointConfig endpoint,
    List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
  ) async {
    final text = await _gateway
        .streamMessage(
          apiKey: endpoint.apiKey,
          baseUrl: endpoint.baseUrl,
          model: endpoint.model,
          messages: messages,
          temperature: 0.2,
          cancelToken: cancelToken,
          maxTokens: 800,
        )
        .join();
    if (text.trim().isEmpty) throw AiException('API 没有返回可用回复。');
    return text;
  }
}

({String summary, List<NovelRoleCandidate> roles}) parseNovelAnalysisResult(
  String raw,
) {
  try {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException();
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    final rawRoles = decoded['roles'];
    return (
      summary: decoded['summary'] as String? ?? raw,
      roles: rawRoles is List
          ? rawRoles
                .whereType<Map<String, dynamic>>()
                .map(NovelRoleCandidate.fromJson)
                .where((role) => role.name.trim().isNotEmpty)
                .take(5)
                .toList()
          : const [],
    );
  } on FormatException {
    return (summary: raw, roles: const []);
  }
}
