import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/memento.dart';
import 'package:whisnya/screens/memento_screen.dart';
import 'package:whisnya/services/memento_service.dart';
import 'package:whisnya/services/share_card_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

class _QueryService extends MementoService {
  _QueryService(LocalStorageService storage) : super(storage: storage);
  final queries = <MementoQuery>[];

  @override
  Future<List<MementoIndex>> queryMementos(MementoQuery query) async {
    queries.add(query);
    if (query.keyword.isNotEmpty || query.tag != null) return [];
    return [
      MementoIndex(
        id: 'one',
        characterId: 'c',
        title: 'Earlier result',
        tags: const [],
        createdAt: DateTime.utc(2026),
        requiresUnlock: false,
      ),
    ];
  }
}

MementoSnapshot _sampleSnapshot() => MementoSnapshot(
  id: 'one',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  idempotencyKey: 'one',
  title: 'Old title',
  characterId: 'c',
  characterNameSnapshot: 'Role',
  sessionTitleSnapshot: 'Session',
  sourceSessionId: 's',
  entries: [
    MementoEntry(
      sourceMessageId: 'm',
      sourcePrefixDigest: 'd',
      role: 'user',
      speakerNameSnapshot: 'Me',
      time: DateTime.utc(2026),
      contentSnapshot: 'Body',
    ),
  ],
);

void main() {
  testWidgets('share title layout is debounced but export uses latest title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final epoch = ValueNotifier<int>(0);
    final authorized = Completer<MementoSnapshot>();
    var authorizationCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ShareCardEditorScreen(
          snapshot: _sampleSnapshot(),
          authorize: () {
            authorizationCalls++;
            return authorized.future;
          },
          datasetEpoch: epoch,
          initialProtectionState: false,
          protectionState: () async => false,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Latest title');
    await tester.pump(const Duration(milliseconds: 299));
    expect(
      find.descendant(
        of: find.byType(ShareCardPageView),
        matching: find.text('Old title'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save PNG'));
    await tester.pump();
    expect(authorizationCalls, 1);
    expect(
      find.descendant(
        of: find.byType(ShareCardPageView),
        matching: find.text('Latest title'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    authorized.complete(_sampleSnapshot());
    epoch.dispose();
  });
  testWidgets('typing coalesces queries and hides stale results immediately', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('collection_debounce'),
    ))!;
    final storage = LocalStorageService(appDataDirectory: dir);
    final service = _QueryService(storage);
    await tester.runAsync(() => storage.appDataDirectory);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: MementoScreen(service: service)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Earlier result'), findsOneWidget);
    expect(service.queries, hasLength(1));

    await tester.enterText(find.byType(TextField).first, 'S');
    await tester.pump();
    expect(find.text('Earlier result'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(find.byType(TextField).first, 'Stay');
    await tester.pump(const Duration(milliseconds: 299));
    expect(service.queries, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.queries, hasLength(2));
    expect(service.queries.last.keyword, 'Stay');
    await tester.pumpAndSettle();
    expect(find.text('Earlier result'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'After restore');
    await tester.pump(const Duration(milliseconds: 100));
    storage.jsonStore.datasetEpochNotifier.value++;
    await tester.pump();
    expect(service.queries, hasLength(3));
    expect(service.queries.last.keyword, 'After restore');
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.queries, hasLength(3));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });
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
