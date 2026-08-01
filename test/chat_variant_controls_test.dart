import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/chat_variant_controls.dart';

void main() {
  testWidgets('variant controls switch within bounds and regenerate', (
    tester,
  ) async {
    var previous = 0;
    var next = 0;
    var regenerate = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: ChatVariantControls(
            selectedIndex: 1,
            variantCount: 3,
            onPrevious: () => previous++,
            onNext: () => next++,
            onRegenerate: () => regenerate++,
          ),
        ),
      ),
    );

    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('上一个候选'));
    await tester.tap(find.byTooltip('下一个候选'));
    await tester.tap(find.text('重新生成'));
    expect((previous, next, regenerate), (1, 1, 1));
  });

  testWidgets('single old reply has no controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: ChatVariantControls(selectedIndex: 0, variantCount: 1),
        ),
      ),
    );

    expect(find.byType(IconButton), findsNothing);
    expect(find.text('重新生成'), findsNothing);
  });

  testWidgets('generating disables all variant actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: ChatVariantControls(
            selectedIndex: 0,
            variantCount: 2,
            isGenerating: true,
            onPrevious: () {},
            onNext: () {},
            onRegenerate: () {},
          ),
        ),
      ),
    );

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });
}
