import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

typedef ChatTextEntry = ({DateTime time, String speaker, String content});

String formatChatText({
  required String title,
  required Iterable<ChatTextEntry> entries,
}) {
  final sections = <String>[
    if (title.trim().isNotEmpty) title.trim(),
    for (final entry in entries)
      if (entry.content.trim().isNotEmpty)
        '[${_formatDateTime(entry.time)}] ${entry.speaker.trim()}\n'
            '${entry.content.trim()}',
  ];
  return sections.isEmpty ? '' : '${sections.join('\n\n')}\n';
}

String chatTextFileName(String title, DateTime time) {
  final safeTitle = title
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceFirst(RegExp(r'[. ]+$'), '');
  final stem = safeTitle.isEmpty ? 'chat' : safeTitle;
  return '$stem-chat-${_dateStamp(time)}-${_timeStamp(time)}.txt';
}

Future<bool> exportChatText({
  required String dialogTitle,
  required String title,
  required Iterable<ChatTextEntry> entries,
}) async {
  final text = formatChatText(title: title, entries: entries);
  if (text.isEmpty) return false;
  return await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: chatTextFileName(title, DateTime.now()),
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: Uint8List.fromList(utf8.encode(text)),
      ) !=
      null;
}

String _formatDateTime(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';
}

String _dateStamp(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}'
      '${_two(value.month)}'
      '${_two(value.day)}';
}

String _timeStamp(DateTime value) =>
    '${_two(value.hour)}${_two(value.minute)}${_two(value.second)}';

String _two(int value) => value.toString().padLeft(2, '0');
