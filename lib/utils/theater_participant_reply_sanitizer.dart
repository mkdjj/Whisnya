const theaterMultipleRoleErrorText = '模型仍然输出了多个角色，请重试或更换模型';

String? sanitizeParticipantReply({
  required String rawReply,
  required String targetName,
  required List<String> allParticipantNames,
}) {
  final text = rawReply.trim();
  if (text.isEmpty || targetName.trim().isEmpty) return null;

  final names = <String>{
    targetName.trim(),
    ...allParticipantNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty),
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  final alternatives = names.map(RegExp.escape).join('|');
  final markerPattern = RegExp(
    '<<<\\s*WhisnyaSpeaker\\s*[:：]\\s*($alternatives)\\s*>>>'
    '|\\[\\s*($alternatives)\\s*\\]'
    '|【\\s*($alternatives)\\s*】'
    '|(?:^|\\n)[ \\t]*($alternatives)[ \\t]*[:：]',
    multiLine: true,
  );
  final markers = markerPattern.allMatches(text).toList();

  if (markers.isEmpty) {
    final speakerLikeNames = names.where(
      (name) => RegExp(
        '${RegExp.escape(name)}\\s*(?:说|问|答|回答|回应|[:：])',
      ).hasMatch(text),
    );
    return speakerLikeNames.length > 1 ? null : text;
  }

  if (text.substring(0, markers.first.start).trim().isNotEmpty) return null;
  final targetBlocks = <String>[];
  for (var i = 0; i < markers.length; i++) {
    final marker = markers[i];
    final speaker = [
      for (var group = 1; group <= 4; group++) marker.group(group),
    ].whereType<String>().first;
    if (speaker != targetName.trim()) continue;
    final end = i + 1 < markers.length ? markers[i + 1].start : text.length;
    final content = text.substring(marker.end, end).trim();
    if (content.isNotEmpty) targetBlocks.add(content);
  }

  return targetBlocks.isEmpty ? null : targetBlocks.join('\n');
}
