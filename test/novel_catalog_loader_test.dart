import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/novel_catalog.dart';
import 'package:whisnya/services/novel_catalog_loader.dart';

void main() {
  test('background parsing preserves synchronous chapter boundaries', () async {
    final text = '第一章 开始\n${'模拟正文。' * 60000}\n第二章 结束！\n尾声内容';
    final expected = buildNovelCatalog(text);
    final actual = await NovelCatalogLoader(text).load('auto');
    expect(
      actual.chapters.map(
        (c) => (c.title, c.content, c.startOffset, c.endOffset),
      ),
      expected.chapters.map(
        (c) => (c.title, c.content, c.startOffset, c.endOffset),
      ),
    );
  });
  test(
    'cache reuses pending requests, evicts old rules and isolates books',
    () async {
      final loader = NovelCatalogLoader('第一章 开始\n甲', backgroundThreshold: 0);
      final first = loader.load('auto');
      expect(identical(first, loader.load('auto')), isTrue);
      await first;
      await loader.load('standard');
      await loader.load('numbers');
      final rebuilt = loader.load('auto');
      expect(identical(first, rebuilt), isFalse);
      await rebuilt;
      final other = await NovelCatalogLoader('第一章 开始\n乙').load('auto');
      expect(other.chapters.single.content, '乙');
    },
  );
  test('preview is bounded and preserves surrogate pairs', () {
    expect(novelChapterPreview('  abc'), 'abc');
    expect(novelChapterPreview('a😀b', maxLength: 2), 'a…');
    expect(novelChapterPreview(' \n${'字' * 100000}').length, 161);
    expect(novelChapterPreview('  '), '');
  });
}
