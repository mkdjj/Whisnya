import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/chat_bubble_theme.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.isUser,
    required this.appearance,
    required this.child,
    this.highlighted = false,
    this.isError = false,
    this.fallbackTextColor,
    this.maxWidth = 760,
    this.margin = const EdgeInsets.only(bottom: 10),
    super.key,
  });

  final bool isUser;
  final ChatBubbleAppearance appearance;
  final Widget child;
  final bool highlighted;
  final bool isError;
  final int? fallbackTextColor;
  final double maxWidth;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = isError
        ? colors.errorContainer
        : appearance.backgroundColor == null
        ? (isUser ? colors.primaryContainer : colors.surfaceContainerHighest)
        : Color(appearance.backgroundColor!);
    final textColor = isError
        ? colors.onErrorContainer
        : appearance.textColor == null
        ? fallbackTextColor == null
              ? (isUser ? colors.onPrimaryContainer : colors.onSurfaceVariant)
              : Color(fallbackTextColor!)
        : Color(appearance.textColor!);
    final fill =
        appearance.style == ChatBubbleStyle.outline ||
            appearance.style == ChatBubbleStyle.textOnly
        ? Colors.transparent
        : base.withValues(alpha: appearance.opacity.clamp(0, 1).toDouble());
    final bubbleTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
      iconTheme: theme.iconTheme.copyWith(color: textColor),
    );
    final content = DefaultTextStyle.merge(
      style: TextStyle(color: textColor),
      child: Theme(data: bubbleTheme, child: child),
    );
    final skin = appearance.imageSkin;
    final bubble = skin != null && !isError
        ? _ImageSkinBubble(
            skin: skin,
            isUser: isUser,
            fill: base.withValues(alpha: appearance.opacity),
            content: content,
            fallback: _buildBubble(context, content, fill, base),
          )
        : _buildBubble(context, content, fill, base);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: margin, child: bubble),
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    Widget content,
    Color fill,
    Color base,
  ) {
    final style = appearance.style;
    final radius = _radius(style);
    final borderColor = highlighted
        ? Theme.of(context).colorScheme.primary
        : base.withValues(alpha: 0.62);
    final border = switch (style) {
      ChatBubbleStyle.outline => Border.all(color: borderColor, width: 1.5),
      ChatBubbleStyle.note => Border.all(color: borderColor, width: 1),
      ChatBubbleStyle.pixel => Border.all(color: borderColor, width: 2),
      ChatBubbleStyle.glass => Border.all(
        color: borderColor.withValues(alpha: 0.45),
      ),
      _ when highlighted => Border.all(color: borderColor, width: 2),
      _ => null,
    };
    final padding = switch (style) {
      ChatBubbleStyle.textOnly => const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 4,
      ),
      ChatBubbleStyle.candy => const EdgeInsets.fromLTRB(16, 12, 10, 8),
      ChatBubbleStyle.comic => EdgeInsets.fromLTRB(
        isUser ? 12 : 16,
        10,
        isUser ? 16 : 12,
        14,
      ),
      _ => const EdgeInsets.fromLTRB(12, 10, 8, 7),
    };

    if (style == ChatBubbleStyle.textOnly) {
      return Padding(
        key: const ValueKey('chat-bubble-textOnly'),
        padding: padding,
        child: content,
      );
    }
    if (style == ChatBubbleStyle.comic) {
      return CustomPaint(
        key: const ValueKey('chat-bubble-comic'),
        painter: _ComicBubblePainter(
          color: fill,
          borderColor: borderColor,
          isUser: isUser,
          highlighted: highlighted,
        ),
        child: Padding(padding: padding, child: content),
      );
    }

    final decoration = BoxDecoration(
      color: fill,
      borderRadius: radius,
      border: border,
      boxShadow: switch (style) {
        ChatBubbleStyle.note => [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18 * appearance.opacity),
            offset: const Offset(3, 3),
          ),
        ],
        ChatBubbleStyle.pixel => [
          BoxShadow(
            color: borderColor.withValues(
              alpha: borderColor.a * appearance.opacity,
            ),
            offset: const Offset(4, 4),
          ),
        ],
        ChatBubbleStyle.candy => [
          BoxShadow(
            color: base.withValues(alpha: 0.25 * appearance.opacity),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
        _ => const [],
      },
    );
    final decorated = DecoratedBox(
      key: ValueKey('chat-bubble-${style.name}'),
      decoration: decoration,
      child: Padding(padding: padding, child: content),
    );
    if (style != ChatBubbleStyle.glass || appearance.opacity == 0) {
      return decorated;
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: decorated,
      ),
    );
  }

  BorderRadius _radius(ChatBubbleStyle style) => switch (style) {
    ChatBubbleStyle.square => BorderRadius.circular(3),
    ChatBubbleStyle.capsule => BorderRadius.circular(32),
    ChatBubbleStyle.note => BorderRadius.circular(7),
    ChatBubbleStyle.pixel => BorderRadius.zero,
    ChatBubbleStyle.candy => BorderRadius.circular(24),
    _ => BorderRadius.circular(16),
  };
}

class _ImageSkinBubble extends StatefulWidget {
  const _ImageSkinBubble({
    required this.skin,
    required this.isUser,
    required this.fill,
    required this.content,
    required this.fallback,
  });

  final ChatBubbleImageSkin skin;
  final bool isUser;
  final Color fill;
  final Widget content;
  final Widget fallback;

  @override
  State<_ImageSkinBubble> createState() => _ImageSkinBubbleState();
}

class _ImageSkinBubbleState extends State<_ImageSkinBubble> {
  var _failed = false;

  @override
  void didUpdateWidget(covariant _ImageSkinBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skin.imagePath != widget.skin.imagePath) _failed = false;
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    if (_failed ||
        skin.imageWidth <= 0 ||
        skin.imageHeight <= 0 ||
        !File(skin.imagePath).existsSync()) {
      return widget.fallback;
    }
    final mirror = widget.isUser && skin.mirrorForUser;
    final fillRegion = mirror ? skin.fillRegion.mirrored : skin.fillRegion;
    final padding = mirror ? skin.textPadding.mirrored : skin.textPadding;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned(
                    left: constraints.maxWidth * fillRegion.left,
                    top: constraints.maxHeight * fillRegion.top,
                    width:
                        constraints.maxWidth *
                        (fillRegion.right - fillRegion.left),
                    height:
                        constraints.maxHeight *
                        (fillRegion.bottom - fillRegion.top),
                    child: ColoredBox(
                      key: const ValueKey('chat-bubble-image-fill'),
                      color: widget.fill,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Transform.flip(
              key: const ValueKey('chat-bubble-image-decoration'),
              flipX: mirror,
              child: Image.file(
                File(skin.imagePath),
                fit: BoxFit.fill,
                centerSlice: Rect.fromLTRB(
                  skin.stretchRegion.left * skin.imageWidth,
                  skin.stretchRegion.top * skin.imageHeight,
                  skin.stretchRegion.right * skin.imageWidth,
                  skin.stretchRegion.bottom * skin.imageHeight,
                ),
                errorBuilder: (_, _, _) {
                  if (!_failed) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _failed = true);
                    });
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              padding.top,
              padding.right,
              padding.bottom,
            ),
            child: widget.content,
          ),
        ],
      ),
    );
  }
}

class _ComicBubblePainter extends CustomPainter {
  const _ComicBubblePainter({
    required this.color,
    required this.borderColor,
    required this.isUser,
    required this.highlighted,
  });

  final Color color;
  final Color borderColor;
  final bool isUser;
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height - 8),
          const Radius.circular(16),
        ),
      );
    final x = isUser ? size.width - 24 : 24.0;
    path
      ..moveTo(x - 8, size.height - 9)
      ..lineTo(x, size.height)
      ..lineTo(x + 6, size.height - 9)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? 2 : 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ComicBubblePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.isUser != isUser ||
      oldDelegate.highlighted != highlighted;
}
