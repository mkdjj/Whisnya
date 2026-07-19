import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whisnya/services/bubble_import/bubble_import_models.dart';
import 'package:whisnya/services/bubble_import/bubble_nine_patch_parser.dart';

void main() {
  test('parses stretch and content markers then removes one-pixel border', () {
    final source = img.Image(width: 12, height: 10, numChannels: 4);
    for (var x = 3; x <= 8; x++) {
      source.setPixelRgba(x, 0, 0, 0, 0, 255);
    }
    for (var y = 2; y <= 6; y++) {
      source.setPixelRgba(0, y, 0, 0, 0, 255);
    }
    for (var x = 2; x <= 9; x++) {
      source.setPixelRgba(x, 9, 0, 0, 0, 255);
    }
    for (var y = 2; y <= 7; y++) {
      source.setPixelRgba(11, y, 0, 0, 0, 255);
    }

    final result = BubbleNinePatchParser().parse(
      Uint8List.fromList(img.encodePng(source)),
    );
    final cropped = img.decodePng(Uint8List.fromList(result.imageBytes))!;

    expect((cropped.width, cropped.height), (10, 8));
    expect(result.stretchRegion.left, closeTo(.2, .001));
    expect(result.stretchRegion.right, closeTo(.8, .001));
    expect(result.stretchRegion.top, closeTo(.125, .001));
    expect(result.stretchRegion.bottom, closeTo(.75, .001));
    expect(result.textPadding.left, 1);
    expect(result.textPadding.right, 1);
    expect(result.textPadding.top, 1);
    expect(result.textPadding.bottom, 1);
  });

  test('rejects nine-patch without stretch markers', () {
    final source = img.Image(width: 5, height: 5, numChannels: 4);

    expect(
      () => BubbleNinePatchParser().parse(
        Uint8List.fromList(img.encodePng(source)),
      ),
      throwsA(isA<BubblePackageException>()),
    );
  });
}
