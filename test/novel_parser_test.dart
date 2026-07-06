import 'dart:convert';

import 'package:whisnya/services/novel_parser.dart';
import 'package:whisnya/services/novel_summary_service.dart';
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

  test('detects common txt chapter headings', () {
    final chapters = detectNovelChapters('''
序章
开始。

第1章 初见
正文一。

第一章 重逢
正文二。

Chapter 3 Reunion
正文三。

001
正文四。

卷一 春日
正文五。

番外 小事
正文六。

终章
结束。
''');

    expect(chapters.map((chapter) => chapter.title), [
      '序章',
      '第1章 初见',
      '第一章 重逢',
      'Chapter 3 Reunion',
      '001',
      '卷一 春日',
      '番外 小事',
      '终章',
    ]);
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
