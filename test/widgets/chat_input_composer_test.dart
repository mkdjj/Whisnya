import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/widgets/chat_input_composer.dart';

void main() {
  testWidgets('secondary actions leave room for typing on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputComposer(
              controller: controller,
              isGenerating: false,
              hasBackground: false,
              inputOpacity: 1,
              onSend: () {},
              onStop: () {},
              onInspiration: () {},
              onRetry: () => retried = true,
              onEditResend: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(TextField)).width,
      greaterThanOrEqualTo(180),
    );
    await tester.tap(find.widgetWithIcon(TextButton, Icons.refresh));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('input outline follows the configured input opacity', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputComposer(
            controller: controller,
            isGenerating: true,
            hasBackground: true,
            inputOpacity: 0.35,
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    final decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    final borders = [
      decoration.border,
      decoration.enabledBorder,
      decoration.focusedBorder,
      decoration.disabledBorder,
    ];

    for (final border in borders) {
      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderSide.color.a,
        closeTo(0.35, 0.001),
      );
    }
  });
}
