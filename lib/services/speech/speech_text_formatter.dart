import 'package:flutter/widgets.dart' show StringCharacters;

class SpeechTextFormatter {
  const SpeechTextFormatter();
  String format(String source) => source
      .replaceAll(
        RegExp(r'```[^\n]*\n[\s\S]*?(?:```|$)|~~~[^\n]*\n[\s\S]*?(?:~~~|$)'),
        '',
      )
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (match) => match[1]!)
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(
        RegExp(r'^\s{0,3}(?:#{1,6}\s+|>\s*|[-+*]\s+)', multiLine: true),
        '',
      )
      .replaceAll(RegExp(r'[*_`~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<String> chunks(String source, {int maxCodeUnits = 1000}) {
    final text = format(source);
    final chunks = <String>[];
    var current = StringBuffer();
    for (final grapheme in text.characters) {
      if (grapheme.length > maxCodeUnits) {
        throw const FormatException(
          'A character exceeds the speech engine limit',
        );
      }
      if (current.length + grapheme.length > maxCodeUnits) {
        chunks.add(current.toString());
        current = StringBuffer();
      }
      current.write(grapheme);
      if (current.length >= maxCodeUnits ~/ 2 &&
          RegExp(r'[。！？.!?\n]').hasMatch(grapheme)) {
        chunks.add(current.toString());
        current = StringBuffer();
      }
    }
    if (current.isNotEmpty) chunks.add(current.toString());
    return chunks;
  }
}
