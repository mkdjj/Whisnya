import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/widgets/chat_bubble.dart';
import 'package:whisnya/widgets/chat_bubble_theme_editor.dart';

void main() {
  Widget app(ChatBubbleAppearance appearance, {bool isUser = false}) =>
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            isUser: isUser,
            appearance: appearance,
            child: const Text('A long bubble message that remains visible.'),
          ),
        ),
      );

  testWidgets('renders every bubble style', (tester) async {
    for (final style in ChatBubbleStyle.values) {
      await tester.pumpWidget(app(ChatBubbleAppearance(style: style)));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('long bubble'), findsOneWidget);
    }
  });

  testWidgets('user and role align to opposite sides', (tester) async {
    await tester.pumpWidget(app(const ChatBubbleAppearance()));
    expect(
      tester.widget<Align>(find.byType(Align).first).alignment,
      Alignment.centerLeft,
    );
    await tester.pumpWidget(app(const ChatBubbleAppearance(), isUser: true));
    expect(
      tester.widget<Align>(find.byType(Align).first).alignment,
      Alignment.centerRight,
    );
  });

  testWidgets('text only has no decoration and transparent fill keeps text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const ChatBubbleAppearance(
          style: ChatBubbleStyle.textOnly,
          textColor: 0xFFFF0000,
          opacity: 0,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chat-bubble-textOnly')), findsOneWidget);
    expect(find.byType(DecoratedBox), findsNothing);
    final text = find.textContaining('long bubble');
    expect(text, findsOneWidget);
    expect(
      DefaultTextStyle.of(tester.element(text)).style.color,
      const Color(0xFFFF0000),
    );
  });

  testWidgets('outline fill is transparent', (tester) async {
    await tester.pumpWidget(
      app(const ChatBubbleAppearance(style: ChatBubbleStyle.outline)),
    );
    final box = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chat-bubble-outline')),
    );
    expect((box.decoration as BoxDecoration).color, Colors.transparent);
  });

  testWidgets('zero opacity removes glass blur and pixel shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const ChatBubbleAppearance(style: ChatBubbleStyle.glass, opacity: 0)),
    );
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(
      app(const ChatBubbleAppearance(style: ChatBubbleStyle.pixel, opacity: 0)),
    );
    final box = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chat-bubble-pixel')),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color?.a, 0);
    expect(decoration.boxShadow?.single.color.a, 0);
    expect(find.textContaining('long bubble'), findsOneWidget);
  });

  testWidgets('theme editor previews style changes immediately', (
    tester,
  ) async {
    var theme = ChatBubbleTheme.characterDefault;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ChatBubbleThemeEditor(
                theme: theme,
                defaultTheme: ChatBubbleTheme.characterDefault,
                onPreview: (value) => setState(() => theme = value),
                onSave: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ChoiceChip).at(1));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-bubble-square')), findsWidgets);
  });
}
