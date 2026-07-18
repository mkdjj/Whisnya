import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/screens/user_profile_edit_screen.dart';
import 'package:whisnya/screens/settings_screen.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets('settings exposes the global user profile editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: Scaffold(
          body: SettingsScreen(
            storage: LocalStorageService(),
            settings: const AppSettings(),
            onSettingsChanged: () async {},
          ),
        ),
      ),
    );

    await tester.drag(find.byType(Scrollable), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp('用户设定|User profile')), findsOneWidget);
  });

  testWidgets('edits a user profile and defaults an empty nickname', (
    tester,
  ) async {
    UserProfile? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<UserProfile>(
                MaterialPageRoute(
                  builder: (_) => UserProfileEditScreen(
                    storage: LocalStorageService(),
                    profile: const UserProfile(
                      name: '旧名字',
                      avatar: 'avatar.png',
                    ),
                    title: '用户设定',
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('user-profile-name')), '');
    await tester.enterText(
      find.byKey(const ValueKey('user-profile-description')),
      '旅行者',
    );
    await tester.tap(find.byKey(const ValueKey('user-profile-clear-avatar')));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(saved?.name, '用户');
    expect(saved?.description, '旅行者');
    expect(saved?.avatar, isEmpty);
  });
}
