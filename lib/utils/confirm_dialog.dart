import 'package:flutter/material.dart';

import 'app_i18n.dart';

Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmLabel = '确认',
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.t(title)),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.t('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.t(confirmLabel)),
            ),
          ],
        ),
      ) ==
      true;
}

Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  String initialText = '',
  String? label,
  String? hint,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  int? minLines,
  int maxLines = 1,
  IconData? prefixIcon,
  bool clearOnCancel = false,
  bool emptyIsNull = false,
}) {
  final controller = TextEditingController(text: initialText);
  void finish(BuildContext dialogContext, String value) {
    final text = value.trim();
    Navigator.of(dialogContext).pop(emptyIsNull && text.isEmpty ? null : text);
  }

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.t(title)),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label == null ? null : dialogContext.t(label),
          hintText: hint == null ? null : dialogContext.t(hint),
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        ),
        onSubmitted: maxLines == 1
            ? (value) => finish(dialogContext, value)
            : null,
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(clearOnCancel ? '' : null),
          child: Text(dialogContext.t(cancelLabel)),
        ),
        FilledButton(
          onPressed: () => finish(dialogContext, controller.text),
          child: Text(dialogContext.t(confirmLabel)),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
