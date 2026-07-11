String joinNonEmptyLines(Iterable<String> lines) =>
    lines.where((line) => line.trim().isNotEmpty).join('\n');
