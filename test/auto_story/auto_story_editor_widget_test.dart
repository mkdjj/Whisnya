import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/screens/auto_story/auto_story_editor_screen.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';

class _Storage extends LocalStorageService {
  _Storage(this.root) : super(appDataDirectory: root);
  final Directory root;
  @override
  Future<Directory> get appDataDirectory async => root;
  @override
  Future<void> ensureReady() async {}
  @override
  Future<AppSettings> loadSettings() async => const AppSettings(
    userProfile: UserProfile(
      name: 'Original B',
      description: 'Original persona',
    ),
  );
  @override
  Future<List<AppCharacter>> loadCharacters() async => [
    AppCharacter.fromJson({'id': 'actor', 'name': 'Actor A'}),
  ];
  @override
  Future<List<WorldBook>> loadWorldBooks() async => [];
  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig.fromJson({
    'endpoints': [
      {
        'id': 'api',
        'name': 'API',
        'baseUrl': 'https://example.invalid/v1',
        'apiKey': 'test',
        'model': 'model',
        'enabled': true,
      },
    ],
  });
}

void main() {
  for (final width in [1100.0, 320.0]) {
    testWidgets(
      width == 320
          ? 'narrow editor with large text stays within the screen'
          : 'draft editor validates and saves without changing the global profile',
      (tester) async {
        final root = Directory.systemTemp.createTempSync('story-editor-');
        addTearDown(() => root.deleteSync(recursive: true));
        tester.view.physicalSize = Size(width, 3200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final storage = _Storage(root);
        AutoStoryEditorResult? result;
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
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<AutoStoryEditorResult>(
                          MaterialPageRoute(
                            builder: (_) => AutoStoryEditorScreen(
                              storage: storage,
                              settings: const AppSettings(),
                            ),
                          ),
                        );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        if (width == 320) {
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 12; i++) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -550),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          return;
        }
        await tester.ensureVisible(find.text('保存草稿'));
        await tester.tap(find.text('保存草稿'));
        await tester.pumpAndSettle();
        expect(find.text('此项不能为空'), findsWidgets);
        expect(result, isNull);
        final actor = find.byType(DropdownButtonFormField<String>).first;
        await tester.ensureVisible(actor);
        await tester.tap(actor);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Actor A').last);
        await tester.pumpAndSettle();
        for (final entry in {
          'bName': 'Edited B',
          'bPersona': 'Local persona',
          'opening': 'Rain',
          'ending': 'Friends',
        }.entries) {
          final target = find.byKey(ValueKey('auto-story-${entry.key}'));
          await tester.ensureVisible(target);
          await tester.enterText(target, entry.value);
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('auto-story-rounds')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('auto-story-rounds')),
          '30',
        );
        await tester.ensureVisible(find.text('已确认双方公开介绍与资料范围'));
        await tester.tap(find.text('已确认双方公开介绍与资料范围'));
        await tester.pump();
        await tester.ensureVisible(find.text('保存草稿'));
        await tester.runAsync(() => tester.tap(find.text('保存草稿')));
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          result,
          isNotNull,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join('\n'),
        );
        expect(result!.generatePlan, isFalse);
        expect(result!.story.actors[1].name, 'Edited B');
        expect(result!.story.requestLedger, isEmpty);
        expect(result!.story.config.maxRequests, 82);
        expect(result!.story.turns, isEmpty);
        expect((await storage.loadSettings()).userProfile.name, 'Original B');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
