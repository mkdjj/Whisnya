import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/novel_catalog.dart';

void main() {
  String body(String marker) => '$marker${'这里是一段模拟正文。' * 20}\n';
  test('full-width, financial Chinese, markdown and English headings', () {
    final result = buildNovelCatalog(
      '## 第１２章 相遇\n甲\n第壹拾叁章 再会\n乙\nChapter XIV: Home\n丙',
    );
    expect(result.chapters, hasLength(3));
    expect(result.chapters.last.content, '丙');
    for (final c in result.chapters) {
      expect(c.endOffset, greaterThan(c.startOffset));
    }
  });
  test('explicit numeric headings accept whitespace and Chinese numbers', () {
    final result = buildNovelCatalog('一 初见\n甲\n二 再会\n乙', rule: 'numbers');
    expect(result.chapters.map((c) => c.title), ['一 初见', '二 再会']);
  });
  test('invalid rules fall back to auto and empty input is safe', () {
    expect(
      buildNovelCatalog('第一章 开始\n正文', rule: 'unknown').chapters.single.title,
      '第一章 开始',
    );
    expect(buildNovelCatalog('').chapters, isEmpty);
    expect(() => buildNovelCatalog('text', chunkSize: 0), throwsArgumentError);
  });
  test('punctuation, wrappers, CR and front matter survive recognition', () {
    final result = buildNovelCatalog('前言内容\r【第一章 你是谁？】\r正文甲\r第二章 出发！\r正文乙');
    expect(result.chapters.map((c) => c.title), [
      '前言 / 原目录',
      '【第一章 你是谁？】',
      '第二章 出发！',
    ]);
    expect(result.chapters.first.content, contains('前言内容'));
    expect(result.chapters.last.content, contains('正文乙'));
  });
  test('isolated numbers and prose lists do not cut standard chapters', () {
    final result = buildNovelCatalog(
      '第一章 开始\n${body('甲')}\n2024\n1、准备物品\n2、检查行李\n第一回合结束之后他回家了\n第二章 后续\n${body('乙')}',
    );
    expect(result.chapters.map((c) => c.title), ['第一章 开始', '第二章 后续']);
    expect(result.chapters.first.content, contains('2、检查行李'));
  });
  test('dense opening catalog is not confused with repeated volume chapters', () {
    final text =
        '目录\n第一章 开始\n第二章 后续\n\n第一卷\n第一章 开始\n${body('甲')}\n第二章 后续\n${body('乙')}\n第二卷\n第一章 开始\n${body('丙')}\n第二章 后续\n${body('丁')}';
    final result = buildNovelCatalog(text);
    expect(result.chapters.where((c) => c.title == '第一章 开始'), hasLength(2));
    for (final marker in ['甲', '乙', '丙', '丁']) {
      expect(result.chapters.any((c) => c.content.contains(marker)), isTrue);
    }
    expect(result.chapters.first.content, contains('目录'));
  });
  test('weak formats need repeated separated evidence in automatic mode', () {
    final text = [for (var i = 1; i <= 3; i++) '$i\n${body('段$i')}'].join('\n');
    expect(buildNovelCatalog(text).chapters.map((c) => c.title), [
      '1',
      '2',
      '3',
    ]);
    final result = buildNovelCatalog('2024\n只是年份，没有目录。');
    expect(result.usedFallback, isTrue);
  });
  test(
    'explicit symbol rule supports short chapters without losing the end',
    () {
      final result = buildNovelCatalog('☆、初见\n甲\n☆、再会\n乙', rule: 'symbols');
      expect(result.chapters.map((c) => c.title), ['☆、初见', '☆、再会']);
      expect(result.chapters.last.content, contains('乙'));
    },
  );
  test(
    'fallback boundaries preserve surrogate pairs and every source character',
    () {
      final text = '甲😀乙\n\n丙丁\n戊己';
      final result = buildNovelCatalog(text, rule: 'paragraphs', chunkSize: 3);
      expect(result.chapters.map((c) => c.content).join(), text);
      expect(
        result.chapters.map((c) => c.content).join(),
        isNot(contains('\uFFFD')),
      );
    },
  );
}
