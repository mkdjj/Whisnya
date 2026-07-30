List<String> roleMessageSegments(String text, {required bool enabled}) {
  if (!enabled) return [text];
  final segments = <String>[];
  var start = 0;
  for (final match in RegExp(r'（[^（）]*）|\([^()]*\)').allMatches(text)) {
    final before = text.substring(start, match.start).trim();
    if (before.isNotEmpty) segments.add(before);
    segments.add(match.group(0)!);
    start = match.end;
  }
  final after = text.substring(start).trim();
  if (after.isNotEmpty) segments.add(after);
  return segments.length > 1 ? segments : [text];
}
