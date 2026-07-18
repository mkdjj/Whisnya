import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/novel_parser.dart';

void main() {
  test('imports UTF-8 and GBK text and detects chapters', () {
    const text = '第一章 开始\n内容一\n第二章 后续\n内容二';

    expect(decodeNovelBytes(utf8.encode(text)), text);
    expect(decodeNovelBytes(gbk.encode(text)), text);
    expect(buildNovelChapters(text).map((item) => item.title), [
      '第一章 开始',
      '第二章 后续',
    ]);
  });

  test('creates default sections when headings are absent', () {
    final chapters = buildNovelChapters('没有章节标题的正文', autoChunkSize: 5);

    expect(chapters.first.title, '第 1 段');
    expect(chapters, hasLength(greaterThan(1)));
  });
}
