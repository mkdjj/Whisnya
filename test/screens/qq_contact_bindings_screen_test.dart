import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/qq_contact_binding.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/screens/settings/qq_contact_binding_edit_screen.dart';
import 'package:whisnya/screens/settings/qq_contact_bindings_screen.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';

void main() {
  testWidgets('onebot binding editor creates a dedicated initialized session', (
    tester,
  ) async {
    final storage = _BindingStorage();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: QqContactBindingEditScreen(
          storage: storage,
          mode: QqIntegrationMode.oneBot,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qq-external-user-id')),
      '900719925474099312345',
    );
    await tester.enterText(
      find.byKey(const ValueKey('qq-display-name')),
      'Alice',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(storage.bindings, hasLength(1));
    expect(storage.bindings.single.externalUserId, '900719925474099312345');
    expect(storage.sessions.single.openingMessageInitialized, isTrue);
    expect(storage.sessions.single.title, 'QQ · Alice');
  });

  testWidgets(
    'notification binding list never offers manual contact key input',
    (tester) async {
      final storage = _BindingStorage();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: QqContactBindingsScreen(
            storage: storage,
            mode: QqIntegrationMode.notification,
            isAndroid: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('捕获下一条 QQ 私聊通知'), findsOneWidget);
      expect(find.byKey(const ValueKey('qq-external-user-id')), findsNothing);
    },
  );

  testWidgets('binding deletion notifies the running integration immediately', (
    tester,
  ) async {
    final storage = _BindingStorage();
    storage.bindings.add(
      QqContactBinding(
        id: 'binding',
        mode: QqIntegrationMode.oneBot,
        externalUserId: '10001',
        displayName: 'Alice',
        characterId: 'character',
        sessionId: 'session',
        createdAt: storage.now,
        updatedAt: storage.now,
      ),
    );
    final snapshots = <List<QqContactBinding>>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: QqContactBindingsScreen(
          storage: storage,
          mode: QqIntegrationMode.oneBot,
          isAndroid: false,
          onBindingsChanged: (bindings) async {
            snapshots.add([...bindings]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).at(1));
    await tester.pumpAndSettle();

    expect(storage.bindings, isEmpty);
    expect(snapshots, hasLength(1));
    expect(snapshots.single, isEmpty);
  });
}

final class _BindingStorage extends LocalStorageService {
  _BindingStorage() : super(appDataDirectory: Directory.systemTemp);

  final now = DateTime(2026, 8, 3);
  final bindings = <QqContactBinding>[];
  final sessions = <ChatSession>[];

  @override
  Future<List<AppCharacter>> loadCharacters() async => [_character(now)];

  @override
  Future<List<QqContactBinding>> loadQqContactBindings() async => [...bindings];

  @override
  Future<void> saveQqContactBinding(QqContactBinding value) async {
    bindings.add(value);
  }

  @override
  Future<void> deleteQqContactBinding(String id) async {
    bindings.removeWhere((binding) => binding.id == id);
  }

  @override
  Future<ChatSession> createChatSession(
    String characterId, {
    String? title,
  }) async {
    final value = ChatSession(
      id: 'session',
      characterId: characterId,
      title: title ?? '',
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
    sessions.add(value);
    return value;
  }

  @override
  Future<ChatSession> markOpeningMessageInitialized({
    required String sessionId,
    required String characterId,
  }) async {
    sessions[0] = sessions[0].copyWith(openingMessageInitialized: true);
    return sessions[0];
  }
}

AppCharacter _character(DateTime now) => AppCharacter(
  id: 'character',
  name: 'Role',
  avatar: '',
  backgroundImage: '',
  backgroundImageOpacity: 1,
  backgroundBlur: 0,
  inputOpacity: 1,
  description: '',
  personality: '',
  background: '',
  speakingStyle: '',
  openingMessage: '',
  extraPrompt: '',
  createdAt: now,
  updatedAt: now,
  lastUsedAt: now,
);
