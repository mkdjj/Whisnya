part of '../novel_screens.dart';

class _NovelChatBackground extends StatelessWidget {
  const _NovelChatBackground({
    required this.imagePath,
    required this.opacity,
    required this.blur,
    required this.child,
  });

  final String imagePath;
  final double opacity;
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();
    if (path.isEmpty) {
      return child;
    }

    final file = File(path);
    final alpha = opacity.clamp(0, 1).toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: alpha,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.16 * alpha),
          ),
          child: child,
        ),
      ],
    );
  }
}
