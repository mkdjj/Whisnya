import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/widgets/app_background.dart';

void main() {
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
