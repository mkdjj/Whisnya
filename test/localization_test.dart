import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/app_i18n.dart';

void main() {
  testWidgets('native delegates support static and dynamic app translations', (
    tester,
  ) async {
    late String save;
    late String progress;
    late String bubble;
    late String userProfile;
    late List<String> repairedLabels;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) {
            save = context.t('保存');
            progress = context.t('正在总结 2 / 5');
            bubble = context.t('聊天气泡样式');
            userProfile = context.t('用户设定');
            repairedLabels = [
              context.t('编辑'),
              context.t('聊天外观'),
              context.t('请先到 API 设置添加配置'),
              context.t('预览'),
            ];
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(save, 'Save');
    expect(progress, 'Summarizing 2 / 5');
    expect(bubble, 'Chat bubble style');
    expect(userProfile, 'User profile');
    expect(repairedLabels, [
      'Edit',
      'Chat appearance',
      'Add an API configuration in API settings first.',
      'Preview',
    ]);
  });
}
