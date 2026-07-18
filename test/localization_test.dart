import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/app_i18n.dart';

void main() {
  testWidgets('native delegates support static and dynamic app translations', (
    tester,
  ) async {
    late String save;
    late String progress;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) {
            save = context.t('保存');
            progress = context.t('正在总结 2 / 5');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(save, 'Save');
    expect(progress, 'Summarizing 2 / 5');
  });
}
