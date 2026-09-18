import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/qq_contact_binding.dart';
import 'package:whisnya/models/qq_diagnostic_event.dart';
import 'package:whisnya/models/qq_integration_settings.dart';
import 'package:whisnya/screens/settings/qq_integration_screen.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/app_i18n.dart';

void main() {
  testWidgets(
    'integration screen exposes onebot controls without notification mode',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: QqIntegrationScreen(
            storage: _QqMemoryStorage(),
            isAndroid: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('非官方接入风险'), findsOneWidget);
      expect(find.byType(SegmentedButton<QqIntegrationMode>), findsNothing);
      expect(find.text('通知监听'), findsNothing);
      expect(find.textContaining('QQ 小号'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Termux / NapCat Bridge'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Termux / NapCat Bridge'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('联系人绑定'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('联系人绑定'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byIcon(Icons.receipt_long_outlined),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('诊断日志'), findsWidgets);
    },
  );

  testWidgets('integration screen provides English labels and risk text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: QqIntegrationScreen(
          storage: _QqMemoryStorage(),
          isAndroid: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QQ private chat auto-reply'), findsOneWidget);
    expect(find.text('Unofficial integration risk'), findsOneWidget);
    expect(find.text('Notification listener'), findsNothing);
    expect(find.textContaining('non-critical QQ account'), findsOneWidget);
  });
}

final class _QqMemoryStorage extends LocalStorageService {
  _QqMemoryStorage() : super(appDataDirectory: Directory.systemTemp);

  QqIntegrationSettings settings = const QqIntegrationSettings();
  final bindings = <QqContactBinding>[];
  final diagnostics = <QqDiagnosticEvent>[];

  @override
  Future<QqIntegrationSettings> loadQqIntegrationSettings() async => settings;

  @override
  Future<void> saveQqIntegrationSettings(QqIntegrationSettings value) async {
    settings = value;
  }

  @override
  Future<List<QqContactBinding>> loadQqContactBindings() async => [...bindings];

  @override
  Future<List<QqDiagnosticEvent>> loadQqDiagnostics() async => [...diagnostics];
}
