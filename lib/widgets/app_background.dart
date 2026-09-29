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
    if (alpha == 0) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: alpha,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: croppedFileImage(File(path), region: region),
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
  File file, {
  ImageCropRegion region = ImageCropRegion.full,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      if (viewport.width <= 0 || viewport.height <= 0) {
        return const SizedBox.shrink();
      }
      Widget decodedImage(Size displaySize, BoxFit fit) {
        final size = backgroundDecodeSize(
          displaySize,
          MediaQuery.devicePixelRatioOf(context),
        );
        return Image(
          image: ResizeImage(
            FileImage(file),
            width: size.width.toInt(),
            height: size.height.toInt(),
            policy: ResizeImagePolicy.fit,
          ),
          fit: fit,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }

      if (region.isFull) {
        // Without source dimensions, a square bound preserves either orientation.
        final side = math.max(viewport.width, viewport.height);
        return decodedImage(Size.square(side), BoxFit.cover);
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
              child: decodedImage(
                Size(sourceWidth * scale, sourceHeight * scale),
                BoxFit.fill,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Bound decoded pixels even for tiny crops of enormous source images.
/// Quantization avoids a new image-cache entry for every small layout change.
Size backgroundDecodeSize(Size displaySize, double pixelRatio) {
  double dimension(double value) => value.isFinite && value > 0
      ? (value * pixelRatio.clamp(1, 4) / 64).ceilToDouble() * 64
      : 2048;
  final width = dimension(displaySize.width);
  final height = dimension(displaySize.height);
  final scale = math.min(
    1.0,
    math.min(
      4096 / math.max(width, height),
      math.sqrt(4 * 1024 * 1024 / (width * height)),
    ),
  );
  return Size(
    math.max(1, (width * scale).floor()).toDouble(),
    math.max(1, (height * scale).floor()).toDouble(),
  );
}
