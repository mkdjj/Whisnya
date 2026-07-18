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
  Widget build(BuildContext context) => MediaBackground(
    imagePath: settings.globalBackgroundImage,
    region: settings.globalBackgroundRegion,
    opacity: settings.globalBackgroundOpacity,
    blur: settings.globalBackgroundBlur,
    child: child,
  );
}

class MediaBackground extends StatelessWidget {
  const MediaBackground({
    required this.imagePath,
    required this.opacity,
    required this.blur,
    required this.child,
    this.region = ImageCropRegion.full,
    this.overlayOpacity = 0,
    super.key,
  });

  final String imagePath;
  final ImageCropRegion region;
  final double opacity;
  final double blur;
  final double overlayOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();
    if (path.isEmpty) return child;
    final alpha = opacity.clamp(0, 1).toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: alpha,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: croppedFileImage(context, File(path), region: region),
          ),
        ),
        if (overlayOpacity > 0)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: overlayOpacity * alpha),
            ),
            child: child,
          )
        else
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
