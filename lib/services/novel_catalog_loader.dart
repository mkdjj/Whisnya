import 'dart:async';
import 'package:flutter/foundation.dart';

import 'novel_catalog.dart';

NovelCatalog _parseCatalog((String, String) input) =>
    buildNovelCatalog(input.$1, rule: input.$2);

/// Reader-scoped cache: at most two rules, never shared between books.
class NovelCatalogLoader {
  NovelCatalogLoader(this.text, {this.backgroundThreshold = 256 * 1024});

  final String text;
  final int backgroundThreshold;
  final _cache = <String, Future<NovelCatalog>>{};

  Future<NovelCatalog> load(String rule) {
    final cached = _cache.remove(rule);
    if (cached != null) {
      _cache[rule] = cached;
      return cached;
    }
    final future = text.length >= backgroundThreshold
        ? compute(_parseCatalog, (text, rule))
        : Future<NovelCatalog>.sync(() => buildNovelCatalog(text, rule: rule));
    _cache[rule] = future;
    if (_cache.length > 2) unawaited(_cache.remove(_cache.keys.first));
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_cache[rule], future)) unawaited(_cache.remove(rule));
        },
      ),
    );
    return future;
  }
}

/// Keep preview layout independent of chapter length; avoid splitting emoji.
String novelChapterPreview(String content, {int maxLength = 160}) {
  if (maxLength < 1) return '';
  var start = 0;
  while (start < content.length && content[start].trim().isEmpty) {
    start++;
  }
  var end = (start + maxLength).clamp(start, content.length);
  if (end < content.length &&
      end > start &&
      content.codeUnitAt(end - 1) >= 0xD800 &&
      content.codeUnitAt(end - 1) <= 0xDBFF) {
    end--;
  }
  return '${content.substring(start, end)}${end < content.length ? '…' : ''}';
}
