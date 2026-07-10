import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/image_crop_region.dart';

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
            child: croppedFileImage(
              context,
              file,
              region: settings.globalBackgroundRegion,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

Widget croppedFileImage(
  BuildContext context,
  File file, {
  ImageCropRegion region = ImageCropRegion.full,
}) {
  if (region.isFull) {
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }

  return LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      if (viewport.width <= 0 || viewport.height <= 0) {
        return const SizedBox.shrink();
      }
      final sourceWidth = math.max(region.sourceAspectRatio, 0.001);
      const sourceHeight = 1.0;
      final cropX = region.x.clamp(0, 1).toDouble() * sourceWidth;
      final cropY = region.y.clamp(0, 1).toDouble() * sourceHeight;
      final cropWidth = region.width.clamp(0.001, 1).toDouble() * sourceWidth;
      final cropHeight =
          region.height.clamp(0.001, 1).toDouble() * sourceHeight;
      final scale = math.max(
        viewport.width / cropWidth,
        viewport.height / cropHeight,
      );

      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -cropX * scale + (viewport.width - cropWidth * scale) / 2,
              top: -cropY * scale + (viewport.height - cropHeight * scale) / 2,
              width: sourceWidth * scale,
              height: sourceHeight * scale,
              child: Image.file(
                file,
                fit: BoxFit.fill,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      );
    },
  );
}
