import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/widgets/chat_input_composer.dart';

void main() {
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
