part of '../novel_screens.dart';

class _ReaderText extends StatelessWidget {
  const _ReaderText({
    required this.text,
    required this.style,
    required this.highlightQuery,
  });

  final String text;
  final TextStyle? style;
  final String highlightQuery;

  @override
  Widget build(BuildContext context) {
    final query = highlightQuery.trim();
    if (query.isEmpty) {
      return SelectableText(text, style: style);
    }
    final matches = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.isEmpty) {
      return SelectableText(text, style: style);
    }

    final highlightStyle = style?.copyWith(
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      color: Theme.of(context).colorScheme.onTertiaryContainer,
    );
    var cursor = 0;
    final spans = <TextSpan>[];
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: highlightStyle,
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}
