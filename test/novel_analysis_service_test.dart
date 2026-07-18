import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/novel/novel_analysis_service.dart';
import 'package:whisnya/services/novel_summary_service.dart';

void main() {
  test('resumes cached chunks and removes cache after completion', () async {
    final directory = await Directory.systemTemp.createTemp('novel_analysis_');
    addTearDown(() => directory.delete(recursive: true));
    final cacheStore = NovelSummaryService(
      LocalStorageService(appDataDirectory: directory),
    );
    final cache = NovelSummaryCache(
      novelId: 'book',
      selectedChunkIndexes: const [0, 1],
      selectedChunks: const ['片段一', '片段二'],
      completedSummaries: const ['总结一'],
      currentIndex: 1,
      endpointId: 'endpoint',
      updatedAt: DateTime(2026),
    );
    await cacheStore.saveCache(cache);
    final gateway = _FakeGateway(['总结二', '{"summary":"全书总结","roles":[]}']);

    final events = await NovelAnalysisService(gateway, cacheStore)
        .analyze(
          novelId: 'book',
          chunks: cache.selectedChunks,
          endpoint: _endpoint,
          resumeCache: cache,
        )
        .toList();

    expect(gateway.requests, hasLength(2));
    expect(events.whereType<NovelAnalysisProgress>().single.current, 2);
    expect(events.whereType<NovelAnalysisCompleted>().single.summary, '全书总结');
    expect(await cacheStore.loadCache('book'), isNull);
  });
}

final _endpoint = AiEndpointConfig(
  id: 'endpoint',
  name: 'Endpoint',
  apiKey: 'key',
  baseUrl: 'https://example.com/v1',
  model: 'model',
  enabled: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeGateway implements AiGateway {
  _FakeGateway(this.responses);
  final List<String> responses;
  final requests = <List<Map<String, String>>>[];
  var index = 0;

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) {
    requests.add(messages);
    return Stream.value(responses[index++]);
  }

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) => throw UnimplementedError();
}
