import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/character_state.dart';
import 'package:whisnya/widgets/character_state_card.dart';

void main() {
  testWidgets('editor can explicitly clear and lock an unknown value', (
    tester,
  ) async {
    StateEdit? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CharacterStateCard(
            view: CharacterStateView.unknown('s', 'c'),
            english: true,
            onEdit: (value) async {
              result = value;
            },
            onRefresh: () async {},
            onReset: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Current state'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.values.containsKey('emotion'), true);
    expect(result!.values['emotion'], null);
    expect(result!.locks['emotion'], true);
  });
  testWidgets(
    'card starts collapsed without refresh and exposes editing on expansion',
    (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CharacterStateCard(
              view: CharacterStateView.unknown('s', 'c'),
              english: true,
              onEdit: (_) async {},
              onRefresh: () async {
                refreshes++;
              },
              onReset: () async {},
            ),
          ),
        ),
      );
      expect(refreshes, 0);
      expect(find.text('AI refresh'), findsNothing);
      await tester.tap(find.text('Current state'));
      await tester.pumpAndSettle();
      expect(find.text('AI refresh'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(4));
      expect(refreshes, 0);
    },
  );
}
