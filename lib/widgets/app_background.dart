import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({required this.settings, required this.child, super.key});

  final AppSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = settings.globalBackgroundImage.trim();
    if (path.isEmpty) {
      return child;
    }
    final file = File(path);

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: settings.globalBackgroundOpacity.clamp(0, 1).toDouble(),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: settings.globalBackgroundBlur,
              sigmaY: settings.globalBackgroundBlur,
            ),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
