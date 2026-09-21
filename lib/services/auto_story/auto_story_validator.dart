import 'dart:convert';

/// Conservative format checks, not a guarantee of narrative semantics.
class AutoStoryValidator {
  static String actorContent(
    String raw, {
    required String actorName,
    required String otherActorName,
    String actorId = 'A',
  }) {
    var text = raw.trim();
    if (text.startsWith('[')) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        /* May be prose. */
      }
      if (decoded is List) throw const FormatException('演员回复不能是JSON。');
    }
    if (text.isEmpty ||
        text.runes.length > 4100 ||
        RegExp(
          r'^(?:```|\{|\[\s*\{|<think>|导演分析\s*[:：]|分析\s*[:：]|Analysis\s*:)',
          caseSensitive: false,
        ).hasMatch(text)) {
      throw const FormatException('演员回复必须是非空的单人故事正文。');
    }
    final own = <String>{actorName, actorId, '演员 $actorId'};
    final other = <String>{
      if (otherActorName != actorName) otherActorName,
      actorId == 'A' ? 'B' : 'A',
      actorId == 'A' ? '演员 B' : '演员 A',
    };
    for (final name in other.where((name) => name.isNotEmpty)) {
      if (RegExp(
        '(?:^|\\s|[。！？!?]\\s*)${RegExp.escape(name)}\\s*[:：]',
      ).hasMatch(text)) {
        throw const FormatException('演员不能输出另一方的台词。');
      }
    }
    for (final name in own.where((name) => name.isNotEmpty)) {
      final prefix = RegExp('^${RegExp.escape(name)}\\s*[:：]\\s*');
      if (prefix.hasMatch(text)) {
        text = text.replaceFirst(prefix, '').trim();
        break;
      }
    }
    if (text.isEmpty || text.runes.length > 4000) {
      throw const FormatException('演员正文长度须为 1～4000 Unicode 字符。');
    }
    return text;
  }
}
