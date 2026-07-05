import 'dart:convert';

import 'package:ai_role_chat/services/novel_parser.dart';
import 'package:ai_role_chat/services/novel_summary_service.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes utf8 novel text', () {
    final bytes = utf8.encode('第一章 开始\n正文');

    expect(decodeNovelBytes(bytes), contains('第一章'));
  });

  test('decodes gbk novel text', () {
    final bytes = gbk.encode('第一章 开始\n正文');

    expect(decodeNovelBytes(bytes), contains('正文'));
  });

  test('round trips novel summary cache json', () {
    final cache = NovelSummaryCache(
      novelId: 'n1',
      selectedChunkIndexes: const [0, 1],
      selectedChunks: const ['a', 'b'],
      completedSummaries: const ['sa'],
      currentIndex: 1,
      endpointId: 'e1',
      updatedAt: DateTime(2026),
    );

    final restored = NovelSummaryCache.fromJson(cache.toJson());

    expect(restored.canResume, isTrue);
    expect(restored.completedSummaries, ['sa']);
    expect(restored.currentIndex, 1);
  });
}
