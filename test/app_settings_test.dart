import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/image_crop_region.dart';

void main() {
  test('round trips background crop coordinates', () {
    final settings = const AppSettings().copyWith(
      globalBackgroundImage: 'original.jpg',
      globalBackgroundRegion: ImageCropRegion.fromPixels(
        sourceWidth: 4000,
        sourceHeight: 3000,
        x: 1000,
        y: 300,
        width: 2000,
        height: 1500,
      ),
    );
    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.globalBackgroundRegion.x, 0.25);
    expect(restored.globalBackgroundRegion.y, 0.1);
    expect(restored.globalBackgroundRegion.width, 0.5);
    expect(restored.globalBackgroundRegion.height, 0.5);
  });

  test('round trips custom summary settings', () {
    final settings = AppSettings.fromJson(const {
      'useCustomChatSummaryItems': true,
      'customChatSummaryItems': ['  关系  ', '', '事件'],
      'useCustomTheaterSummaryItems': true,
      'customTheaterSummaryItems': [' 群聊关系 ', '计划 '],
    });

    expect(settings.useCustomChatSummaryItems, isTrue);
    expect(settings.customChatSummaryItems, ['关系', '事件']);
    expect(settings.useCustomTheaterSummaryItems, isTrue);
    expect(settings.customTheaterSummaryItems, ['群聊关系', '计划']);
    expect(settings.toJson()['customChatSummaryItems'], ['关系', '事件']);
  });

  test('fills defaults when custom summary items are empty', () {
    final settings = const AppSettings().copyWith(
      useCustomChatSummaryItems: true,
      customChatSummaryItems: const ['', '  '],
      useCustomTheaterSummaryItems: true,
      customTheaterSummaryItems: const [],
    );

    expect(
      settings.customChatSummaryItems,
      AppSettings.defaultChatSummaryItems,
    );
    expect(
      settings.customTheaterSummaryItems,
      AppSettings.defaultTheaterSummaryItems,
    );
  });

  test('truncates custom summary items at 20', () {
    final settings = AppSettings.fromJson({
      'customChatSummaryItems': [for (var i = 0; i < 25; i++) '项目 $i'],
      'customTheaterSummaryItems': [for (var i = 0; i < 25; i++) '群聊 $i'],
    });

    expect(settings.customChatSummaryItems, hasLength(20));
    expect(settings.customChatSummaryItems.last, '项目 19');
    expect(settings.customTheaterSummaryItems, hasLength(20));
    expect(settings.customTheaterSummaryItems.last, '群聊 19');
  });

  test('disabling custom summaries keeps saved items', () {
    final settings = const AppSettings().copyWith(
      useCustomChatSummaryItems: true,
      customChatSummaryItems: const ['用户偏好'],
    );
    final disabled = settings.copyWith(useCustomChatSummaryItems: false);

    expect(disabled.useCustomChatSummaryItems, isFalse);
    expect(disabled.customChatSummaryItems, ['用户偏好']);
  });

  test('restores default summary items', () {
    final settings = const AppSettings().copyWith(
      customChatSummaryItems: const ['自定义'],
      customTheaterSummaryItems: const ['自定义群聊'],
    );
    final restored = settings.copyWith(
      customChatSummaryItems: AppSettings.defaultChatSummaryItems,
      customTheaterSummaryItems: AppSettings.defaultTheaterSummaryItems,
    );

    expect(
      restored.customChatSummaryItems,
      AppSettings.defaultChatSummaryItems,
    );
    expect(
      restored.customTheaterSummaryItems,
      AppSettings.defaultTheaterSummaryItems,
    );
  });

  test('provides English default summary items', () {
    expect(
      AppSettings.defaultChatSummaryItemsEn,
      contains('What happened in the recent chat'),
    );
    expect(
      AppSettings.defaultTheaterSummaryItemsEn,
      contains('The current topic, last action, and what should happen next'),
    );
  });

  test('default summaries preserve current voice and unfinished context', () {
    expect(
      AppSettings.defaultChatSummaryItems.join(' '),
      allOf(contains('称呼'), contains('动作描写格式'), contains('未完成')),
    );
    expect(
      AppSettings.defaultTheaterSummaryItems.join(' '),
      allOf(contains('语气'), contains('最后动作'), contains('下一步')),
    );
    expect(
      AppSettings.defaultChatSummaryItemsEn.join(' '),
      allOf(contains('address'), contains('unfinished')),
    );
    expect(
      AppSettings.defaultTheaterSummaryItemsEn.join(' '),
      allOf(contains('voice'), contains('next')),
    );
  });
}
