import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class MessageContent extends StatelessWidget {
  const MessageContent({
    required this.text,
    this.textColor,
    this.highlightQuery = '',
    super.key,
  });

  final String text;
  final int? textColor;
  final String highlightQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: textColor == null ? null : Color(textColor!),
    );
    if (_hasHighlight) {
      return SelectableText.rich(
        TextSpan(style: baseStyle, children: _highlightSpans(context)),
      );
    }

    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: baseStyle,
      listBullet: baseStyle,
      blockquote: baseStyle,
      tableBody: baseStyle,
      code: baseStyle?.copyWith(fontFamily: 'monospace'),
    );
    return MarkdownBody(data: text, selectable: true, styleSheet: styleSheet);
  }

  bool get _hasHighlight {
    final query = highlightQuery.trim();
    return query.isNotEmpty && text.toLowerCase().contains(query.toLowerCase());
  }

  List<TextSpan> _highlightSpans(BuildContext context) {
    final query = highlightQuery.trim();
    if (query.isEmpty) return [TextSpan(text: text)];

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) break;
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.28),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + query.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}
