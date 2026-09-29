import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_state.dart';
import 'package:whisnya/widgets/character_state_card.dart';
import 'package:whisnya/widgets/chat_header_panel.dart';

void main() {
  testWidgets('expanded state and tools remain scrollable above messages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = CharacterStateView.unknown('s', 'c').apply(
      StateEdit(
        expectedRevision: 0,
        values: {
          for (final entry in characterStateLimits.entries)
            entry.key: '长' * entry.value,
        },
      ),
      null,
      'manual',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 260),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                ChatHeaderPanel(
                  maxHeight: constraints.maxHeight * .35,
                  tools: const SizedBox(
                    key: ValueKey('tools'),
                    height: 40,
                    child: Text('API'),
                  ),
                  stateCard: CharacterStateCard(
                    view: state,
                    onEdit: (_) async {},
                    onRefresh: () async {},
                    onReset: () async {},
                  ),
                ),
                const Expanded(child: SizedBox(key: ValueKey('messages'))),
                const SizedBox(height: 60, child: TextField()),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('tools'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(CharacterStateCard)).dy),
    );
    await tester.tap(find.text('当前状态'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('messages'))).height,
      greaterThan(100),
    );
    final header = find.byType(ChatHeaderPanel);
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(of: header, matching: find.byType(SingleChildScrollView)),
    );
    expect(scroll.primary, isFalse);
    await tester.scrollUntilVisible(
      find.text('恢复为未知'),
      200,
      scrollable: find.descendant(
        of: header,
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(find.text('恢复为未知').hitTestable(), findsOneWidget);
  });
}
