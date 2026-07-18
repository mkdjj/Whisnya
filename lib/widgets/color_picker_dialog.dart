import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';

class ColorPickerResult {
  const ColorPickerResult(this.color);

  final int? color;
}

Future<ColorPickerResult?> showColorPickerDialog({
  required BuildContext context,
  required String title,
  required int? value,
}) {
  var red = value == null ? 17 : (value >> 16) & 0xFF;
  var green = value == null ? 24 : (value >> 8) & 0xFF;
  var blue = value == null ? 39 : value & 0xFF;

  return showDialog<ColorPickerResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final color = Color(_argb(red, green, blue));
        Widget slider(String label, int channel, ValueChanged<int> changed) =>
            Row(
              children: [
                SizedBox(width: 20, child: Text(label)),
                Expanded(
                  child: Slider(
                    value: channel.toDouble(),
                    min: 0,
                    max: 255,
                    divisions: 255,
                    onChanged: (value) => changed(value.round()),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text('$channel', textAlign: TextAlign.end),
                ),
              ],
            );
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
              ),
              slider('R', red, (value) => setState(() => red = value)),
              slider('G', green, (value) => setState(() => green = value)),
              slider('B', blue, (value) => setState(() => blue = value)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const ColorPickerResult(null)),
              child: Text(context.t('默认')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(ColorPickerResult(_argb(red, green, blue))),
              child: Text(context.t('应用')),
            ),
          ],
        );
      },
    ),
  );
}

int _argb(int red, int green, int blue) =>
    0xFF000000 | (red << 16) | (green << 8) | blue;
