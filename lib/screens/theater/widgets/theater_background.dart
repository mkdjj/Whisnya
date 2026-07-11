part of '../theater_screens.dart';

class _TheaterBackground extends StatelessWidget {
  const _TheaterBackground({
    required this.imagePath,
    required this.region,
    required this.opacity,
    required this.blur,
    required this.child,
  });

  final String imagePath;
  final ImageCropRegion region;
  final double opacity;
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();
    final alpha = opacity.clamp(0, 1).toDouble();
    if (path.isEmpty) return child;

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
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18 * alpha),
          ),
          child: child,
        ),
      ],
    );
  }
}
