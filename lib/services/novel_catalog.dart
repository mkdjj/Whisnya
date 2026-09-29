import 'novel_parser.dart';

const novelCatalogRules = {
  'auto': '自动识别',
  'standard': '标准章节',
  'numbers': '数字标题',
  'symbols': '特殊符号标题',
  'paragraphs': '按段落分段',
  'legacy': '旧版规则',
};

class NovelCatalog {
  const NovelCatalog(this.chapters, {this.usedFallback = false});
  final List<NovelChapter> chapters;
  final bool usedFallback;
}

String normalizeNovelText(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
const _numerals = r'0-9０-９零〇○一二三四五六七八九十百千万两壹贰叁肆伍陆柒捌玖拾佰仟';
final _standard = RegExp(
  '^(?:第\\s*[$_numerals]+\\s*(?:章|节(?!课)|卷|回(?![合来去事])|部(?![分是门落])|篇(?!张)|集(?![合和])|话|幕)|[卷部篇]\\s*[$_numerals]+)',
);
final _english = RegExp(
  r'^(chapter|section|part|book|volume|episode)\s+([0-9]+|[ivxlcdm]+)\b',
  caseSensitive: false,
);
final _special = RegExp(
  r'^(序章|楔子|引子|前言|序言|终章|尾声|后记|大结局|番外篇?|外传|间章)(?:$|[\s:：、—-])',
);
final _numeric = RegExp(
  '^([$_numerals]{1,8})(?:(?:[、.．:：_—-]\\s*|\\s+).{1,60})?\$',
);
final _symbols = RegExp(r'^(?:[☆★✦✧][、\s]*.+|={3,6}.+={3,6})$');
final _spaces = RegExp(r'\s+');
final _markdownPrefix = RegExp(r'^#{1,6}\s*');
final _openingBracket = RegExp(r'^[【\[（(「『]\s*');
final _closingBracket = RegExp(r'[】\]）)」』]$');
final _bodyPrefix = RegExp(r'^正文\s+');

class _Heading {
  const _Heading(
    this.title,
    this.line,
    this.start,
    this.bodyStart,
    this.family,
  );
  final String title, family;
  final int line, start, bodyStart;
  String get key => title.replaceAll(_spaces, '');
}

/// Rule matching only proposes boundaries. Weak formats need repeated,
/// separated evidence; raw source is never rewritten or globally deduplicated.
NovelCatalog buildNovelCatalog(
  String raw, {
  String rule = 'auto',
  int chunkSize = 12000,
}) {
  if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
  if (!novelCatalogRules.containsKey(rule)) rule = 'auto';
  final text = normalizeNovelText(raw);
  if (rule == 'paragraphs') return _paragraphs(text, chunkSize);
  if (rule == 'legacy') {
    var cursor = 0;
    final chapters = <NovelChapter>[];
    for (final chapter in buildNovelChapters(text, autoChunkSize: chunkSize)) {
      final found = text.indexOf(chapter.content, cursor);
      final start = found < 0 ? cursor : found;
      final end = (start + chapter.content.length).clamp(start, text.length);
      chapters.add(
        NovelChapter(
          title: chapter.title,
          content: chapter.content,
          startOffset: start,
          endOffset: end,
        ),
      );
      cursor = end;
    }
    return NovelCatalog(chapters);
  }
  final lines = text.split('\n');
  final candidates = <_Heading>[];
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    final rawLine = lines[i];
    final title = rawLine.replaceAll('\uFEFF', '').trim();
    if (title.isEmpty || title.length > 100) {
      offset += rawLine.length + 1;
      continue;
    }
    var matchText = title;
    if (matchText.startsWith('[::]')) matchText = matchText.substring(4).trim();
    matchText = matchText.replaceFirst(_markdownPrefix, '');
    matchText = matchText.replaceFirst(_openingBracket, '');
    matchText = matchText.replaceFirst(_closingBracket, '');
    matchText = matchText.replaceFirst(_bodyPrefix, '');
    String? family;
    if (title.isNotEmpty && title.length <= 100) {
      if (_standard.hasMatch(matchText) ||
          _english.hasMatch(matchText) ||
          _special.hasMatch(matchText) ||
          title.startsWith('[::]')) {
        family = 'standard';
      } else if (_numeric.hasMatch(matchText)) {
        family = 'numbers';
      } else if (_symbols.hasMatch(title)) {
        family = 'symbols';
      }
    }
    if (family != null &&
        rule != 'paragraphs' &&
        (rule == 'auto' || family == rule)) {
      candidates.add(
        _Heading(
          title,
          i,
          offset,
          (offset + rawLine.length + 1).clamp(0, text.length),
          family,
        ),
      );
    }
    offset += rawLine.length + 1;
  }
  var headings = candidates;
  if (rule == 'auto') {
    // A lone year or short numbered list is not a chapter format. Keep a weak
    // family only if it forms a repeated, blank-separated sequence with prose.
    final approved = <_Heading>{
      ...candidates.where((h) => h.family == 'standard'),
    };
    final credible = <String, List<_Heading>>{'numbers': [], 'symbols': []};
    for (var i = 0; i < candidates.length; i++) {
      final h = candidates[i];
      if (h.family == 'standard') continue;
      final end = i + 1 < candidates.length
          ? candidates[i + 1].start
          : text.length;
      if ((h.line == 0 || lines[h.line - 1].trim().isEmpty) &&
          text.substring(h.bodyStart, end).trim().length >= 80) {
        credible[h.family]!.add(h);
      }
    }
    for (final family in ['numbers', 'symbols']) {
      if (credible[family]!.length >= 3) approved.addAll(credible[family]!);
    }
    headings = candidates.where(approved.contains).toList();
  }
  // Only suppress a dense opening run if the same sequence occurs later.
  // Same titles elsewhere (e.g. numbering restarts in a new volume) are kept.
  var run = 0;
  while (run + 1 < headings.length &&
      text
          .substring(headings[run].bodyStart, headings[run + 1].start)
          .trim()
          .isEmpty) {
    run++;
  }
  final count = run + 1;
  if (count >= 2) {
    for (var start = 2; start < headings.length - 1; start++) {
      if (text
          .substring(headings[start].bodyStart, headings[start + 1].start)
          .trim()
          .isEmpty) {
        continue;
      }
      var matches = 0;
      while (matches < count &&
          matches < start &&
          start + matches < headings.length &&
          headings[matches].key == headings[start + matches].key) {
        matches++;
      }
      if (matches >= 2) {
        headings = headings.sublist(matches);
        break;
      }
    }
  }
  if (headings.isEmpty) return _paragraphs(text, chunkSize);
  final chapters = <NovelChapter>[];
  if (text.substring(0, headings.first.start).trim().isNotEmpty) {
    chapters.add(
      NovelChapter(
        title: '前言 / 原目录',
        content: text.substring(0, headings.first.start),
        startOffset: 0,
        endOffset: headings.first.start,
      ),
    );
  }
  for (var i = 0; i < headings.length; i++) {
    final h = headings[i];
    final end = i + 1 < headings.length ? headings[i + 1].start : text.length;
    final body = text.substring(h.bodyStart, end);
    chapters.add(
      NovelChapter(
        title: h.title,
        content: body.trim().isEmpty ? text.substring(h.start, end) : body,
        startOffset: h.start,
        endOffset: end,
      ),
    );
  }
  return NovelCatalog(chapters);
}

NovelCatalog _paragraphs(String text, int size) {
  final chapters = <NovelChapter>[];
  for (var start = 0; start < text.length;) {
    var end = (start + size).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end - 1);
      if (newline > start + size ~/ 2) end = newline + 1;
      // Do not divide a UTF-16 surrogate pair, even with tiny test chunk sizes.
      if (end > start &&
          text.codeUnitAt(end - 1) >= 0xD800 &&
          text.codeUnitAt(end - 1) <= 0xDBFF) {
        end++;
      }
    }
    chapters.add(
      NovelChapter(
        title: '第 ${chapters.length + 1} 段（自动分段）',
        content: text.substring(start, end),
        startOffset: start,
        endOffset: end,
      ),
    );
    start = end;
  }
  return NovelCatalog(chapters, usedFallback: true);
}
