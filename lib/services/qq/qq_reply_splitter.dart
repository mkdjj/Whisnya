class QqReplySplitter {
  const QqReplySplitter._();

  static String truncate(String text, {required int maxReplyCharacters}) =>
      _takeRunes(text.trim(), maxReplyCharacters);

  static List<String> splitOneBot(
    String text, {
    required int maxReplyCharacters,
    required int replyChunkCharacters,
  }) {
    var remaining = _takeRunes(text.trim(), maxReplyCharacters);
    if (remaining.isEmpty) return const [];
    final result = <String>[];
    while (remaining.runes.length > replyChunkCharacters) {
      final candidate = _takeRunes(remaining, replyChunkCharacters);
      final boundary = _bestBoundary(candidate);
      final chunk = candidate.substring(0, boundary).trim();
      if (chunk.isNotEmpty) result.add(chunk);
      remaining = remaining.substring(boundary).trimLeft();
    }
    if (remaining.trim().isNotEmpty) result.add(remaining.trim());
    return result;
  }

  static int _bestBoundary(String candidate) {
    final minimumRunes = (candidate.runes.length * 0.5).floor();
    for (final delimiter in const [
      '\n\n',
      '\n',
      '。',
      '？',
      '！',
      '?',
      '!',
      '. ',
    ]) {
      final index = candidate.lastIndexOf(delimiter);
      if (index < 0) continue;
      final end = index + delimiter.length;
      if (candidate.substring(0, end).runes.length >= minimumRunes) return end;
    }
    return candidate.length;
  }

  static String _takeRunes(String value, int count) {
    if (count <= 0) return '';
    final runes = value.runes.toList();
    return String.fromCharCodes(
      runes.length <= count ? runes : runes.take(count),
    );
  }
}
