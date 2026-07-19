import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/widgets/chat_bubble.dart';

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

  testWidgets(
    'image skin mirrors decoration only and opacity affects fill only',
    (tester) async {
      late Directory directory;
      final file = await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('bubble-widget-');
        final file = File('${directory.path}${Platform.pathSeparator}skin.png');
        await file.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
            'AAAADUlEQVR42mNk+M/wHwAF/gL+Xr0Y5QAAAABJRU5ErkJggg==',
          ),
        );
        return file;
      });
      addTearDown(() => directory.delete(recursive: true));
      final appearance = ChatBubbleAppearance(
        backgroundColor: 0xFF123456,
        opacity: 0.25,
        imageSkin: ChatBubbleImageSkin(
          imagePath: file!.path,
          imageWidth: 1,
          imageHeight: 1,
        ),
      );

      await tester.pumpWidget(app(appearance, isUser: true));
      await tester.pump();

      final decoration = tester.widget<Transform>(
        find.byKey(const ValueKey('chat-bubble-image-decoration')),
      );
      expect(decoration.transform.entry(0, 0), -1);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('chat-bubble-image-decoration')),
          matching: find.byType(ClipRect),
        ),
        findsOneWidget,
      );
      final fill = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('chat-bubble-image-fill')),
      );
      expect(fill.color.a, closeTo(0.25, 0.001));
      expect(
        find.ancestor(
          of: find.textContaining('long bubble'),
          matching: find.byKey(const ValueKey('chat-bubble-image-decoration')),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('missing image skin falls back to parameter bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const ChatBubbleAppearance(
          imageSkin: ChatBubbleImageSkin(
            imagePath: 'missing.png',
            imageWidth: 32,
            imageHeight: 32,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-bubble-rounded')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-bubble-image-decoration')),
      findsNothing,
    );
  });
}
