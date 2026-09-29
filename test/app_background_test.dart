import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/widgets/app_background.dart';
import 'package:whisnya/models/image_crop_region.dart';

void main() {
  test('decode budget bounds extreme crops and buckets small size changes', () {
    final huge = backgroundDecodeSize(const Size(100000, 20000), 3);
    expect(huge.width, lessThanOrEqualTo(4096));
    expect(huge.width * huge.height, lessThanOrEqualTo(4 * 1024 * 1024));
    expect(
      backgroundDecodeSize(const Size(400, 800), 1),
      backgroundDecodeSize(const Size(401, 801), 1),
    );
  });
  testWidgets('invisible backgrounds do not create image decoders', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaBackground(
          imagePath: 'missing.jpg',
          opacity: 0,
          blur: 8,
          child: Text('content'),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });
  testWidgets(
    'cropped background retains geometry with bounded aspect-preserving decode',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaBackground(
            imagePath: 'missing.jpg',
            opacity: 1,
            blur: 0,
            region: ImageCropRegion(x: .25, width: .5, sourceAspectRatio: 2),
            child: Text('content'),
          ),
        ),
      );
      final provider =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(provider.policy, ResizeImagePolicy.fit);
      expect(
        provider.width! * provider.height!,
        lessThanOrEqualTo(4 * 1024 * 1024),
      );
      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.width! / positioned.height!, 2);
      expect(positioned.left, lessThan(0));
    },
  );
  testWidgets('media background clamps opacity and applies its overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaBackground(
          imagePath: 'missing-image.jpg',
          opacity: 2,
          blur: 3,
          overlayOpacity: 0.18,
          child: Text('content'),
        ),
      ),
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    expect(
      (box.decoration as BoxDecoration).color,
      Colors.black.withValues(alpha: 0.18),
    );
    expect(find.text('content'), findsOneWidget);
  });
}
