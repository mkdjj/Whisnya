import 'dart:io';

import 'package:ai_role_chat/models/ai_provider.dart';
import 'package:ai_role_chat/models/app_character.dart';
import 'package:ai_role_chat/models/app_settings.dart';
import 'package:ai_role_chat/models/chat_message.dart';
import 'package:ai_role_chat/models/novel_book.dart';
import 'package:ai_role_chat/prompts.dart';
import 'package:ai_role_chat/screens/novel_screen.dart';
import 'package:ai_role_chat/services/local_storage_service.dart';
import 'package:ai_role_chat/utils/app_i18n.dart';
import 'package:ai_role_chat/utils/role_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds role system prompt with summary', () {
    final character = AppCharacter(
      id: 'c1',
      name: '测试角色',
      avatar: '',
      backgroundImage: '',
      backgroundImageOpacity: 1,
      backgroundBlur: 0,
      bubbleOpacity: 0.92,
      inputOpacity: 0.92,
      description: '简介',
      personality: '温和',
      background: '背景',
      speakingStyle: '简洁',
      openingMessage: '你好',
      extraPrompt: '补充',
      defaultProvider: AiProvider.deepseek,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );

    final prompt = PromptBuilder.buildSystemPrompt(character, '历史总结');

    expect(prompt, contains('【角色名称】'));
    expect(prompt, contains('测试角色'));
    expect(prompt, contains('历史总结'));
  });

  test('builds summary prompt from chat messages', () {
    final prompt = PromptBuilder.buildSummaryPrompt([
      ChatMessage(role: 'user', content: '你好', time: DateTime(2026)),
      ChatMessage(role: 'assistant', content: '你好呀', time: DateTime(2026)),
    ]);

    expect(prompt, contains('本次聊天主要内容'));
    expect(prompt, contains('用户：你好'));
    expect(prompt, contains('角色：你好呀'));
  });

  test('parses pasted role card fields', () {
    final parsed = RoleImportParser.parse('''
角色名称：小夏
简介：住在海边的朋友
性格设定：温柔、直接
说话方式：短句，偶尔开玩笑
与用户的关系：老朋友
开场白：你终于来了。
''');

    expect(parsed.name, '小夏');
    expect(parsed.description, '住在海边的朋友');
    expect(parsed.personality, contains('温柔'));
    expect(parsed.speakingStyle, contains('短句'));
    expect(parsed.speakingStyle, isNot(contains('老朋友')));
    expect(parsed.openingMessage, '你终于来了。');
  });

  test('does not put unlabeled text into extra prompt', () {
    final parsed = RoleImportParser.parse('这是一整段没有标题的角色设定');

    expect(parsed.filledCount, 0);
    expect(parsed.extraPrompt, isEmpty);
  });

  test('formats character as importable role card', () {
    final character = AppCharacter(
      id: 'c1',
      name: '小夏',
      avatar: '',
      backgroundImage: '',
      backgroundImageOpacity: 1,
      backgroundBlur: 0,
      bubbleOpacity: 0.92,
      inputOpacity: 0.92,
      description: '住在海边的朋友',
      personality: '温柔',
      background: '海边长大',
      speakingStyle: '短句',
      openingMessage: '你来了。',
      extraPrompt: '不编造记忆',
      defaultProvider: AiProvider.deepseek,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );

    final parsed = RoleImportParser.parse(
      RoleImportParser.formatCharacter(character),
    );

    expect(parsed.name, character.name);
    expect(parsed.extraPrompt, character.extraPrompt);
  });

  test('detects markdown Chinese novel chapters', () {
    final chapters = detectNovelChapters('''
本文件来自尚香书苑。

# 第 1 节
第一节正文。

# 第 2 节
第二节正文。
''');

    expect(chapters, hasLength(2));
    expect(chapters.first.title, '第 1 节');
    expect(chapters.first.content, contains('第一节正文'));
  });

  test('detects common txt catalog styles', () {
    final chapters = detectNovelChapters('''
正文 第一卷 原上草 第一章 秦少爷初临宝地
第一章正文。

第二章 防狼术小试牛刀
第二章正文。

[::]作者的话
后记正文。
''');

    expect(chapters.map((chapter) => chapter.title), [
      '正文 第一卷 原上草 第一章 秦少爷初临宝地',
      '第二章 防狼术小试牛刀',
      '作者的话',
    ]);
    expect(chapters.first.content, contains('第一章正文。'));
  });

  test('skips duplicated txt catalog headings', () {
    final chapters = detectNovelChapters('''
目录
第一章 初遇
第二章 再见

正文
第一章 初遇
真正正文一。

第二章 再见
真正正文二。
''');

    expect(chapters.map((chapter) => chapter.title), ['第一章 初遇', '第二章 再见']);
    expect(chapters.first.content, contains('真正正文一。'));
    expect(chapters.first.content, isNot(contains('目录')));
  });

  test('does not treat sentence-like chapter mentions as headings', () {
    final chapters = detectNovelChapters('''
第一章 初遇
第一章的时候她还小。

第二章 再见
第二章正文。
''');

    expect(chapters.map((chapter) => chapter.title), ['第一章 初遇', '第二章 再见']);
    expect(chapters.first.content, contains('第一章的时候她还小。'));
  });

  test('detects English chapter headings', () {
    final chapters = detectNovelChapters('''
CHAPTER I
One.

Chapter 2 The Door
Two.
''');

    expect(chapters, hasLength(2));
    expect(chapters.first.title, 'CHAPTER I');
  });

  test('builds automatic catalog when headings are missing', () {
    final chapters = buildNovelChapters('abcdefghi', autoChunkSize: 4);

    expect(chapters.map((chapter) => chapter.title), [
      '第 1 段',
      '第 2 段',
      '第 3 段',
    ]);
    expect(chapters[1].content, 'efgh');
  });

  test('builds clamped ten-chapter summary ranges', () {
    expect(chapterRangeIndexes(53, 50, 10), [49, 50, 51, 52]);
    expect(chapterRangeIndexes(80, 36, 10), [
      35,
      36,
      37,
      38,
      39,
      40,
      41,
      42,
      43,
      44,
    ]);
    expect(chapterRangeIndexes(0, 1, 10), isEmpty);
  });

  test('rewrites restored app data paths', () {
    final restoredRoot = [
      'D:',
      'new_phone',
      'app_data',
    ].join(Platform.pathSeparator);

    expect(
      restoreAppDataPath(
        '/data/user/0/app/files/app_data/novels/book.txt',
        restoredRoot,
      ),
      [restoredRoot, 'novels', 'book.txt'].join(Platform.pathSeparator),
    );
    expect(
      restoreAppDataPath('/tmp/avatar.jpg', restoredRoot),
      '/tmp/avatar.jpg',
    );
  });

  test('stores app language setting', () {
    final settings = AppSettings.fromJson(const {
      'languageCode': appLanguageEn,
    });

    expect(settings.languageCode, appLanguageEn);
    expect(settings.toJson()['languageCode'], appLanguageEn);
    expect(appLocaleFromCode(appLanguageEn)?.languageCode, 'en');
    expect(appLocaleFromCode(appLanguageSystem), isNull);
  });

  test('keeps novel role indexes valid after deleting a role', () {
    expect(
      novelRoleIndexAfterDelete(
        selectedIndex: 2,
        deletedIndex: 1,
        newLength: 4,
        keepReplacement: true,
      ),
      1,
    );
    expect(
      novelRoleIndexAfterDelete(
        selectedIndex: 1,
        deletedIndex: 1,
        newLength: 2,
        keepReplacement: true,
      ),
      1,
    );
    expect(
      novelRoleIndexAfterDelete(
        selectedIndex: 1,
        deletedIndex: 1,
        newLength: 2,
        keepReplacement: false,
      ),
      -1,
    );
    expect(
      novelRoleIndexAfterDelete(
        selectedIndex: 0,
        deletedIndex: 0,
        newLength: 0,
        keepReplacement: true,
      ),
      -1,
    );
  });

  test('novel merge prompt skips minor roles', () {
    final prompt = PromptBuilder.buildNovelMergePrompt(['女主反复出现，路人甲只出现一次。']);

    expect(prompt, contains('出场次数明显低'));
    expect(prompt, contains('不要放进 roles'));
    expect(prompt, contains('roles 最多 5 个'));
    expect(
      prompt,
      contains('只输出 name、description、personality、background、speakingStyle'),
    );
    expect(prompt, contains('不要输出开场白、补充设定'));
  });

  test('novel chat prompt includes selected user role', () {
    final book = NovelBook(
      id: 'n1',
      title: '测试小说',
      textPath: '',
      summary: '设定',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    const aiRole = NovelRoleCandidate(
      name: '小夏',
      description: 'AI 角色',
      personality: '温和',
      speakingStyle: '简洁',
      background: '背景',
    );
    const userRole = NovelRoleCandidate(
      name: '阿青',
      description: '用户角色',
      personality: '直接',
      speakingStyle: '短句',
      background: '用户背景',
    );

    final prompt = PromptBuilder.buildNovelChatSystemPrompt(
      book,
      aiRole,
      userRole,
    );

    expect(prompt, contains('用户选择扮演：阿青'));
    expect(prompt, contains('不要替用户说话或行动'));
  });
}
