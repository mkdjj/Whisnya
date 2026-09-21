import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/screens/memento_screen.dart';
import 'package:whisnya/services/memento_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets('collection has searchable empty state', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('collection_ui'),
    ))!;
    final storage = LocalStorageService(appDataDirectory: dir);
    await tester.runAsync(() => storage.appDataDirectory);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: MementoScreen(service: MementoService(storage: storage)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('No mementos yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
