import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/screens/novel/novel_theater_identity_picker.dart';
import 'package:whisnya/utils/app_i18n.dart';

void main() {
  testWidgets('novel theater identity picker shows all three choices', (
    tester,
  ) async {
    NovelTheaterIdentityChoice? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              selected = await showNovelTheaterIdentityPicker(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('选择你在群聊中的身份'), findsOneWidget);
    expect(find.text('使用默认用户设定'), findsOneWidget);
    expect(find.text('扮演小说角色'), findsOneWidget);
    expect(find.text('自定义临时身份'), findsOneWidget);

    await tester.tap(find.text('扮演小说角色'));
    await tester.pumpAndSettle();
    expect(selected, NovelTheaterIdentityChoice.novelRole);
  });
}
