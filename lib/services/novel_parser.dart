import 'dart:convert';

import 'package:charset/charset.dart';

const supportedNovelEncodings = ['utf-8', 'gbk', 'gb18030'];

class NovelDecodeException implements Exception {
  const NovelDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NovelChapter {
  const NovelChapter({required this.title, required this.content});

  final String title;
  final String content;
}

String decodeNovelBytes(List<int> bytes, {String? encoding}) {
  final names = encoding == null ? supportedNovelEncodings : [encoding];
  for (final name in names) {
    try {
      final text = _decode(bytes, name);
      if (_looksReadable(text)) {
        return text;
      }
    } on FormatException {
      continue;
    }
  }
  throw const NovelDecodeException('TXT 编码识别失败，请手动选择编码重新导入。');
}

String _decode(List<int> bytes, String encoding) {
  switch (encoding.toLowerCase()) {
    case 'utf-8':
    case 'utf8':
      return utf8.decode(bytes);
    case 'gbk':
    case 'gb18030':
      return gbk.decode(bytes, allowMalformed: false);
    default:
      throw FormatException('Unsupported encoding: $encoding');
  }
}

bool _looksReadable(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.contains('\uFFFD')) {
    return false;
  }
  final controls = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F]',
  ).allMatches(text).length;
  return controls / text.length < 0.01;
}

List<NovelChapter> detectNovelChapters(String text) {
  const number = r'[0-9０-９零〇○一二三四五六七八九十百千万两壹贰叁肆伍陆柒捌玖拾佰仟]+';
  const unit = r'[章节篇卷回部集话幕]';

  String? chapterTitle(String raw) {
    var line = raw.replaceFirst('\uFEFF', '').trim();
    if (line.startsWith('[::]')) {
      final title = line.substring(4).trim();
      return title.isEmpty ? null : title;
    }
    while (line.startsWith('#')) {
      line = line.substring(1).trimLeft();
    }
    if (line.isEmpty || line.length > 80) return null;

    final compact = line.replaceAll(RegExp(r'\s+'), '');
    final sentenceEnd = RegExp(r'[。！？!?；;，,、]$').hasMatch(line);
    if (RegExp('^第$number$unit\$').hasMatch(compact)) return line;
    if (RegExp('^第$number$unit.{1,60}\$').hasMatch(compact) && !sentenceEnd) {
      return line;
    }
    if (RegExp('^[卷部篇]$number.{0,60}\$').hasMatch(compact) && !sentenceEnd) {
      return line;
    }
    if (RegExp('^正文.*第$number$unit.{1,60}\$').hasMatch(compact) &&
        !sentenceEnd) {
      return line;
    }
    if (RegExp(r'^(序章|楔子|引子|前言|序言|正文|终章|尾声|后记|大结局)$').hasMatch(compact)) {
      return line;
    }
    if (RegExp(r'^(番外|番外篇|外传|间章|同人|附录|作品相关).{0,60}$').hasMatch(compact) &&
        !sentenceEnd) {
      return line;
    }
    if (RegExp(
      r'^(chapter|part|book|volume)\s+([0-9]+|[ivxlcdm]+)\b.{0,60}$',
      caseSensitive: false,
    ).hasMatch(line)) {
      return line;
    }
    if (RegExp(r'^[0-9０-９]{1,4}$').hasMatch(compact)) return line;
    if (RegExp(r'^[0-9０-９]{1,4}\s*[、.．。:：-]\s*.{1,60}$').hasMatch(line) &&
        !sentenceEnd) {
      return line;
    }
    return null;
  }

  bool numberedTitle(String title) {
    final compact = title.replaceAll(RegExp(r'\s+'), '');
    return RegExp('^第$number$unit').hasMatch(compact) ||
        RegExp('^[卷部篇]$number').hasMatch(compact) ||
        RegExp('^正文.*第$number$unit').hasMatch(compact) ||
        RegExp(
          r'^(chapter|part|book|volume)\s+([0-9]+|[ivxlcdm]+)\b',
          caseSensitive: false,
        ).hasMatch(title) ||
        RegExp(r'^[0-9０-９]{1,4}([、.．。:：-].*)?$').hasMatch(compact);
  }

  List<({String title, int line})> dropCatalogDuplicates(
    List<({String title, int line})> headings,
  ) {
    final seen = <String>{};
    final kept = <({String title, int line})>[];
    for (final heading in headings.reversed) {
      final key = heading.title.replaceAll(RegExp(r'\s+'), '');
      if (numberedTitle(heading.title) && !seen.add(key)) {
        continue;
      }
      kept.add(heading);
    }
    return kept.reversed.toList();
  }

  final lines = text.replaceAll('\r\n', '\n').split('\n');
  var headings = <({String title, int line})>[];
  for (var i = 0; i < lines.length; i++) {
    final title = chapterTitle(lines[i]);
    if (title != null) {
      headings.add((title: title, line: i));
    }
  }
  if (headings.length < 2) {
    return const [];
  }
  headings = dropCatalogDuplicates(headings);
  if (headings.length < 2) {
    return const [];
  }

  final chapters = <NovelChapter>[];
  for (var i = 0; i < headings.length; i++) {
    final nextLine = i + 1 < headings.length
        ? headings[i + 1].line
        : lines.length;
    final content = lines
        .sublist(headings[i].line + 1, nextLine)
        .join('\n')
        .trim();
    if (content.isNotEmpty) {
      chapters.add(NovelChapter(title: headings[i].title, content: content));
    }
  }
  return chapters;
}

List<String> splitNovelText(String text, int chunkSize) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return const [];
  }

  final chunks = <String>[];
  for (var start = 0; start < normalized.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, normalized.length);
    chunks.add(normalized.substring(start, end));
  }
  return chunks;
}

List<int> chapterRangeIndexes(int total, int startChapter, int count) {
  if (total <= 0 || count <= 0) {
    return const [];
  }
  final start = (startChapter - 1).clamp(0, total - 1).toInt();
  final end = (start + count).clamp(0, total).toInt();
  return [for (var index = start; index < end; index++) index];
}

List<NovelChapter> buildNovelChapters(
  String text, {
  int autoChunkSize = 12000,
}) {
  final detected = detectNovelChapters(text);
  if (detected.isNotEmpty) {
    return detected;
  }
  final chunks = splitNovelText(text, autoChunkSize);
  return [
    for (var i = 0; i < chunks.length; i++)
      NovelChapter(title: '第 ${i + 1} 段', content: chunks[i]),
  ];
}
