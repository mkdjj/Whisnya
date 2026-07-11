import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/image_crop_region.dart';
import '../utils/app_i18n.dart';

class ImageCropSelection {
  const ImageCropSelection({required this.region});

  final ImageCropRegion region;
}

class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({
    required this.imagePath,
    required this.title,
    required this.aspectRatio,
    required this.outputWidth,
    required this.outputHeight,
    this.renderOutput = true,
    super.key,
  });

  final String imagePath;
  final String title;
  final double aspectRatio;
  final int outputWidth;
  final int outputHeight;
  final bool renderOutput;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  late final Future<img.Image> _imageFuture;
  var _scale = 1.0;
  var _offset = Offset.zero;
  var _startScale = 1.0;
  var _startOffset = Offset.zero;
  var _startFocalPoint = Offset.zero;
  Size? _viewportSize;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadImage();
  }

  Future<img.Image> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw StateError('无法读取图片文件。');
    }
    return image;
  }

  Future<void> _finishCrop(img.Image source) async {
    final viewport = _viewportSize;
    if (viewport == null) {
      return;
    }

    final geometry = _geometryFor(viewport, source);
    final left = geometry.left;
    final top = geometry.top;
    final width = geometry.width;
    final height = geometry.height;

    final x = _clampInt((-left / width) * source.width, 0, source.width - 1);
    final y = _clampInt((-top / height) * source.height, 0, source.height - 1);
    final right = _clampInt(
      ((viewport.width - left) / width) * source.width,
      x + 1,
      source.width,
    );
    final bottom = _clampInt(
      ((viewport.height - top) / height) * source.height,
      y + 1,
      source.height,
    );

    if (!widget.renderOutput) {
      Navigator.of(context).pop(
        ImageCropSelection(
          region: ImageCropRegion.fromPixels(
            sourceWidth: source.width,
            sourceHeight: source.height,
            x: x,
            y: y,
            width: right - x,
            height: bottom - y,
          ),
        ),
      );
      return;
    }

    final cropped = img.copyCrop(
      source,
      x: x,
      y: y,
      width: right - x,
      height: bottom - y,
    );
    final resized = img.copyResize(
      cropped,
      width: widget.outputWidth,
      height: widget.outputHeight,
      interpolation: img.Interpolation.cubic,
    );
    final encoded = img.encodeJpg(resized, quality: 92);
    if (!mounted) return;
    Navigator.of(context).pop(Uint8List.fromList(encoded));
  }

  int _clampInt(num value, int min, int max) {
    return value.round().clamp(min, max).toInt();
  }

  _CropGeometry _geometryFor(Size viewport, img.Image image) {
    final baseScale = math.max(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    final width = image.width * baseScale * _scale;
    final height = image.height * baseScale * _scale;
    final left = (viewport.width - width) / 2 + _offset.dx;
    final top = (viewport.height - height) / 2 + _offset.dy;
    return _CropGeometry(left: left, top: top, width: width, height: height);
  }

  Offset _clampOffset(Offset offset, Size viewport, img.Image image) {
    final baseScale = math.max(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    final width = image.width * baseScale * _scale;
    final height = image.height * baseScale * _scale;
    final maxDx = math.max(0.0, (width - viewport.width) / 2);
    final maxDy = math.max(0.0, (height - viewport.height) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx).toDouble(),
      offset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _reset() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<img.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        final image = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: [
              IconButton(
                tooltip: context.t('重置'),
                onPressed: image == null ? null : _reset,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: context.t('完成裁剪'),
                onPressed: image == null ? null : () => _finishCrop(image),
                icon: const Icon(Icons.check),
              ),
            ],
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.waiting => const Center(
              child: CircularProgressIndicator(),
            ),
            _ when snapshot.hasError => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString()),
              ),
            ),
            _ => _CropBody(
              imagePath: widget.imagePath,
              aspectRatio: widget.aspectRatio,
              image: image!,
              scale: _scale,
              offset: _offset,
              onViewportChanged: (size) => _viewportSize = size,
              geometryFor: _geometryFor,
              onScaleStart: (details) {
                _startScale = _scale;
                _startOffset = _offset;
                _startFocalPoint = details.focalPoint;
              },
              onScaleUpdate: (details, viewport) {
                setState(() {
                  _scale = (_startScale * details.scale).clamp(1.0, 6.0);
                  final nextOffset =
                      _startOffset + details.focalPoint - _startFocalPoint;
                  _offset = _clampOffset(nextOffset, viewport, image);
                });
              },
            ),
          },
        );
      },
    );
  }
}

class _CropBody extends StatelessWidget {
  const _CropBody({
    required this.imagePath,
    required this.aspectRatio,
    required this.image,
    required this.scale,
    required this.offset,
    required this.onViewportChanged,
    required this.geometryFor,
    required this.onScaleStart,
    required this.onScaleUpdate,
  });

  final String imagePath;
  final double aspectRatio;
  final img.Image image;
  final double scale;
  final Offset offset;
  final ValueChanged<Size> onViewportChanged;
  final _CropGeometry Function(Size viewport, img.Image image) geometryFor;
  final GestureScaleStartCallback onScaleStart;
  final void Function(ScaleUpdateDetails details, Size viewport) onScaleUpdate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = 24.0;
        var cropWidth = constraints.maxWidth - horizontalPadding * 2;
        var cropHeight = cropWidth / aspectRatio;
        final maxHeight = constraints.maxHeight - 120;
        if (cropHeight > maxHeight) {
          cropHeight = maxHeight;
          cropWidth = cropHeight * aspectRatio;
        }
        final viewport = Size(cropWidth, cropHeight);
        onViewportChanged(viewport);
        final geometry = geometryFor(viewport, image);

        return Column(
          children: [
            Expanded(
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    color: Colors.black,
                  ),
                  child: ClipRect(
                    child: SizedBox(
                      width: cropWidth,
                      height: cropHeight,
                      child: GestureDetector(
                        onScaleStart: onScaleStart,
                        onScaleUpdate: (details) =>
                            onScaleUpdate(details, viewport),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned(
                              left: geometry.left,
                              top: geometry.top,
                              width: geometry.width,
                              height: geometry.height,
                              child: Image.file(
                                File(imagePath),
                                fit: BoxFit.fill,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: Text(context.t('取消')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final state = context
                            .findAncestorStateOfType<_ImageCropScreenState>();
                        unawaited(state?._finishCrop(image));
                      },
                      icon: const Icon(Icons.check),
                      label: Text(context.t('使用图片')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CropGeometry {
  const _CropGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}
