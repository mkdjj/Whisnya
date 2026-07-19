import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';
import '../utils/transparency.dart';

class SettingSlider extends StatelessWidget {
  const SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
    this.height = 32,
    this.displayWidth = 48,
    super.key,
  });

  factory SettingSlider.transparency({
    required String label,
    required double opacity,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
    double height = 32,
    double displayWidth = 48,
    Key? key,
  }) {
    final transparency = opacityToTransparency(opacity);
    return SettingSlider(
      key: key,
      label: label,
      value: transparency,
      min: 0,
      max: 1,
      divisions: 100,
      display: '${(transparency * 100).round()}%',
      onChanged: (value) => onChanged(transparencyToOpacity(value)),
      onChangeEnd: onChangeEnd == null
          ? null
          : (value) => onChangeEnd(transparencyToOpacity(value)),
      height: height,
      displayWidth: displayWidth,
    );
  }

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double height;
  final double displayWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          labelText: context.t(label),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: height,
                child: Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
            SizedBox(
              width: displayWidth,
              child: Text(display, textAlign: TextAlign.end),
            ),
          ],
        ),
      ),
    );
  }
}
