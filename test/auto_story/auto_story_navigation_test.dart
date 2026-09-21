import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/screens/home_screen.dart';
import 'package:whisnya/screens/settings_screen.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'auto_story_model_test.dart' show storyFixture;

void main() {
  for (final width in [390.0, 1100.0, 320.0]) {
    testWidgets(
      'story destination on width $width is opt-in and settings stays last',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final root = Directory.systemTemp.createTempSync(
          'auto-story-navigation-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var requests = 0;
        late _NavigationStorage storage;
        await tester.runAsync(() async {
          storage = _NavigationStorage(root);
          await storage.autoStories.createStory(storyFixture());
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
              child: child!,
            ),
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            home: HomeScreen(
              storage: storage,
              settings: const AppSettings(),
              onSettingsChanged: () async {},
              aiService: AiService(
                client: MockClient((_) async {
                  requests++;
                  throw StateError('No unsolicited AI');
                }),
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.byKey(const ValueKey('auto-story-tab')), findsOneWidget);
        final characterRect = tester.getRect(
          find.byKey(const ValueKey('character-card-source')),
        );
        await tester.tap(find.byKey(const ValueKey('auto-story-tab')));
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('故事演绎'), findsOneWidget);
        expect(find.text('Story'), findsOneWidget);
        final storyRect = tester.getRect(
          find
              .ancestor(of: find.text('Story'), matching: find.byType(Card))
              .first,
        );
        final subtitle = tester.getRect(find.textContaining('Same / Same'));
        expect(subtitle.bottom, lessThanOrEqualTo(storyRect.bottom));
        expect(
          subtitle.top,
          greaterThanOrEqualTo(tester.getRect(find.text('Story')).bottom),
        );
        expect(storyRect.top, closeTo(characterRect.top, .1));
        expect(storyRect.left, closeTo(characterRect.left, .1));
        expect(storyRect.right, closeTo(characterRect.right, .1));
        expect(requests, 0);
        expect(find.byKey(const ValueKey('auto-story-create')), findsOneWidget);
        await tester.runAsync(
          () => storage.jsonStore.maintain(() async {
            await storage.autoStories.deleteStory('story-1');
            final fresh = storyFixture(id: 'restored');
            await storage.autoStories.createStory(
              fresh.copyWith(
                config: fresh.config.copyWith(title: 'Restored story'),
              ),
            );
          }, advanceEpoch: true),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('Story'), findsNothing);
        expect(find.text('Restored story'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.settings_outlined));
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.byType(SettingsScreen), findsOneWidget);
        if (width < 600) {
          final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
          expect(nav.selectedIndex, nav.destinations.length - 1);
        } else {
          final nav = tester.widget<NavigationRail>(
            find.byType(NavigationRail),
          );
          expect(nav.selectedIndex, nav.destinations.length - 1);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _NavigationStorage extends LocalStorageService {
  _NavigationStorage(this.root) : super(appDataDirectory: root);
  final Directory root;
  @override
  Future<Directory> get appDataDirectory async => root;
  @override
  Future<void> ensureReady() async {}
  @override
  Future<List<AppCharacter>> loadCharacters() async => [
    AppCharacter.fromJson({'id': 'source', 'name': '角色'}),
  ];
}
