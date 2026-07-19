import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../models/chat_bubble_theme.dart';
import 'bubble_import_models.dart';

final class BubbleNinePatchParser {
  BubbleNinePatchData parse(Uint8List bytes) {
    final source = img.decodePng(bytes);
    if (source == null || source.width < 3 || source.height < 3) {
      throw BubblePackageException('无效的 Android .9.png');
    }

    final innerWidth = source.width - 2;
    final innerHeight = source.height - 2;
    final horizontalStretch = _markers(
      List.generate(innerWidth, (index) => source.getPixel(index + 1, 0)),
    );
    final verticalStretch = _markers(
      List.generate(innerHeight, (index) => source.getPixel(0, index + 1)),
    );
    if (horizontalStretch == null || verticalStretch == null) {
      throw BubblePackageException('.9.png 缺少顶部或左侧拉伸标记');
    }

    final horizontalContent = _markers(
      List.generate(
        innerWidth,
        (index) => source.getPixel(index + 1, source.height - 1),
      ),
    );
    final verticalContent = _markers(
      List.generate(
        innerHeight,
        (index) => source.getPixel(source.width - 1, index + 1),
      ),
    );
    final cropped = img.copyCrop(
      source,
      x: 1,
      y: 1,
      width: innerWidth,
      height: innerHeight,
    );

    return BubbleNinePatchData(
      imageBytes: Uint8List.fromList(img.encodePng(cropped)),
      stretchRegion: BubbleNormalizedRect(
        left: horizontalStretch.$1 / innerWidth,
        top: verticalStretch.$1 / innerHeight,
        right: horizontalStretch.$2 / innerWidth,
        bottom: verticalStretch.$2 / innerHeight,
      ),
      textPadding: BubbleContentInsets(
        left: horizontalContent?.$1.toDouble() ?? 0,
        top: verticalContent?.$1.toDouble() ?? 0,
        right: horizontalContent == null
            ? 0
            : (innerWidth - horizontalContent.$2).toDouble(),
        bottom: verticalContent == null
            ? 0
            : (innerHeight - verticalContent.$2).toDouble(),
      ),
    );
  }

  static (int, int)? _markers(List<img.Pixel> pixels) {
    int? start;
    var end = 0;
    for (var index = 0; index < pixels.length; index++) {
      if (!_isMarker(pixels[index])) continue;
      start ??= index;
      end = index + 1;
    }
    return start == null ? null : (start, end);
  }

  static bool _isMarker(img.Pixel pixel) =>
      pixel.a > 0 && pixel.r <= 16 && pixel.g <= 16 && pixel.b <= 16;
}
