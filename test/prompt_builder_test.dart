import 'dart:io';

import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/prompts/prompt_builder.dart';
import 'package:whisnya/screens/novel/novel_screens.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/novel_parser.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/utils/chat_context_policy.dart';
import 'package:whisnya/utils/character_import_flow.dart';
import 'package:whisnya/utils/role_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps role system prompt stable and moves summary to memory', () {
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
      defaultEndpointId: 'deepseek',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );

    final prompt = PromptBuilder.buildSystemPrompt(character);
    final request = PromptBuilder.buildChatRequestMessages(
      character: character,
      historySummary: '历史总结',
      summarizedMessageCount: 0,
      messages: [
        ChatMessage(
          role: 'assistant',
          content: character.openingMessage,
          time: DateTime(2026),
        ),
      ],
      useFullContext: false,
    );

    expect(prompt, contains('【角色名称】'));
    expect(prompt, contains('测试角色'));
    expect(prompt, isNot(contains('历史总结')));
    expect(prompt, isNot(contains('【开场白】')));
    expect(request[1]['role'], 'system');
    expect(request[1]['content'], contains('历史总结'));
    expect(request[2]['content'], '你好');
  });

  test('builds summary prompt from chat messages', () {
    final prompt = PromptBuilder.buildSummaryPrompt([
      ChatMessage(role: 'user', content: '你好', time: DateTime(2026)),
      ChatMessage(role: 'assistant', content: '你好呀', time: DateTime(2026)),
    ]);

    expect(prompt, contains('角色和用户当前的关系、态度与关系变化'));
    expect(prompt, contains('用户的喜好和重要个人信息'));
    expect(prompt, contains('用户：你好'));
    expect(prompt, contains('角色：你好呀'));
    expect(prompt, isNot(contains('本次聊天主要内容')));
  });

  test('builds custom character summary prompt items', () {
    final prompt = PromptBuilder.buildSummaryPrompt(
      [ChatMessage(role: 'user', content: '喜欢甜食', time: DateTime(2026))],
      useCustomItems: true,
      customItems: const ['  亲密度变化  ', '', '约定事项'],
    );

    expect(prompt, contains('1. 亲密度变化'));
    expect(prompt, contains('2. 约定事项'));
    expect(prompt, isNot(contains('角色和用户的关系、态度等等')));
  });

  test('builds full chat context when requested', () {
    final character = AppCharacter(
      id: 'c1',
      name: '测试角色',
      avatar: '',
      backgroundImage: '',
      backgroundImageOpacity: 1,
      backgroundBlur: 0,
      bubbleOpacity: 0.92,
      inputOpacity: 0.92,
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
      openingMessage: '',
      extraPrompt: '',
      defaultEndpointId: 'deepseek',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );
    final messages = [
      for (var i = 0; i < 35; i++)
        ChatMessage(role: 'user', content: '消息 $i', time: DateTime(2026)),
    ];

    final request = PromptBuilder.buildChatRequestMessages(
      character: character,
      historySummary: '历史总结',
      summarizedMessageCount: 0,
      messages: messages,
      useFullContext: true,
    );

    expect(request, hasLength(37));
    expect(request[2]['content'], '消息 0');
    expect(request.first['content'], isNot(contains('历史总结')));
    expect(request[1]['content'], contains('历史总结'));
  });

  test('builds rolling recent chat context with summary when requested', () {
    final character = AppCharacter(
      id: 'c1',
      name: '测试角色',
      avatar: '',
      backgroundImage: '',
      backgroundImageOpacity: 1,
      backgroundBlur: 0,
      bubbleOpacity: 0.92,
      inputOpacity: 0.92,
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
      openingMessage: '',
      extraPrompt: '',
      defaultEndpointId: 'deepseek',
      chatSummaryMessageLimit: 50,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );
    final messages = [
      for (var i = 1; i <= 56; i++)
        ChatMessage(role: 'user', content: '消息 $i', time: DateTime(2026)),
    ];

    final request = PromptBuilder.buildChatRequestMessages(
      character: character,
      historySummary: '历史总结',
      summarizedMessageCount: 50,
      messages: messages,
      useFullContext: false,
    );

    expect(request, hasLength(14));
    expect(request[2]['content'], '消息 45');
    expect(request.last['content'], '消息 56');
    expect(request.first['content'], isNot(contains('历史总结')));
    expect(request[1]['content'], contains('历史总结'));
  });

  test('keeps twelve raw messages after a fifty-message summary', () {
    final character = AppCharacter(
      id: 'c1',
      name: '测试角色',
      avatar: '',
      backgroundImage: '',
      backgroundImageOpacity: 1,
      backgroundBlur: 0,
      bubbleOpacity: 0.92,
      inputOpacity: 0.92,
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
      openingMessage: '',
      extraPrompt: '',
      defaultEndpointId: 'deepseek',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );
    final messages = [
      ChatMessage(role: 'system', content: '忽略', time: DateTime(2026)),
      for (var i = 1; i <= 51; i++)
        ChatMessage(
          role: i.isOdd ? 'user' : 'assistant',
          content: '消息 $i',
          time: DateTime(2026),
        ),
    ];

    final request = PromptBuilder.buildChatRequestMessages(
      character: character,
      historySummary: '历史总结',
      summarizedMessageCount: 50,
      messages: messages,
      useFullContext: false,
    );

    expect(request.skip(2).map((message) => message['content']), [
      for (var i = 40; i <= 51; i++) '消息 $i',
    ]);
    expect(request[1]['content'], contains('最近原始聊天优先'));
    expect(request[1]['content'], contains('称呼、语气、句式长度、动作描写格式'));
    expect(request[1]['content'], contains('未完成话题'));
    expect(manualSummaryBoundary(messageCount: 51), 39);
  });

  test('grows recent context until the summary threshold', () {
    final start = PromptBuilder.recentContextStartIndex(
      messageCount: 70,
      summaryLimit: 50,
    );

    expect(start, 49);
  });

  test('rolls summary forward by configured blocks', () {
    expect(
      PromptBuilder.rollingSummaryEndIndex(messageCount: 56, summaryLimit: 50),
      50,
    );
    expect(
      PromptBuilder.rollingSummaryEndIndex(messageCount: 70, summaryLimit: 50),
      50,
    );
    expect(
      PromptBuilder.rollingSummaryEndIndex(messageCount: 101, summaryLimit: 50),
      100,
    );
  });

  test('builds rolling summary merge prompt', () {
    final prompt = PromptBuilder.buildRollingSummaryPrompt(
      previousSummary: '旧总结',
      newMessages: [
        ChatMessage(role: 'user', content: '新消息', time: DateTime(2026)),
      ],
    );

    expect(prompt, contains('旧总结'));
    expect(prompt, contains('用户：新消息'));
    expect(prompt, contains('合并'));
    expect(prompt, contains('角色需要长期记住的设定、约定和事件'));
    expect(PromptBuilder.limitSummary('😀内容', 1), '😀');
  });

  test('limits summaries at a nearby complete boundary', () {
    expect(PromptBuilder.limitSummary('短文本。', 20), '短文本。');
    expect(PromptBuilder.limitSummary('第一项：完整内容。第二项：会被截断的长句', 12), '第一项：完整内容。');
    expect(
      PromptBuilder.limitSummary('【关系】\n完整内容\n\n【语气】\n后续很长内容', 14),
      '【关系】\n完整内容',
    );
  });

  test('builds custom rolling summary prompt items', () {
    final prompt = PromptBuilder.buildRollingSummaryPrompt(
      previousSummary: '旧总结',
      newMessages: [
        ChatMessage(role: 'assistant', content: '新回复', time: DateTime(2026)),
      ],
      useCustomItems: true,
      customItems: const ['记住的承诺'],
    );

    expect(prompt, contains('1. 记住的承诺'));
    expect(prompt, isNot(contains('这些聊天说了什么发生了什么')));
  });

  test('builds theater summary prompt default and custom items', () {
    final message = TheaterMessage(
      id: 'm1',
      sessionId: 's1',
      round: 1,
      speakerType: TheaterSpeakerType.user,
      speakerId: 'user',
      speakerName: '用户',
      content: '我去开门',
      time: DateTime(2026),
    );
    final defaultPrompt = PromptBuilder.buildTheaterSummaryPrompt(
      previousSummary: '旧群聊总结',
      messages: [message],
    );
    final customPrompt = PromptBuilder.buildTheaterSummaryPrompt(
      previousSummary: '旧群聊总结',
      messages: [message],
      useCustomItems: true,
      customItems: const ['舞台站位', '下一步行动'],
    );

    expect(defaultPrompt, contains('各个角色、用户之间现在的相互关系'));
    expect(defaultPrompt, contains('用户：我去开门'));
    expect(customPrompt, contains('1. 舞台站位'));
    expect(customPrompt, contains('2. 下一步行动'));
    expect(customPrompt, isNot(contains('这些人（包括用户）在干什么')));
  });

  test('round trips theater session and parses single api replies', () {
    final now = DateTime(2026);
    const participant = TheaterParticipant(
      id: 'p1',
      source: TheaterRoleSource.appCharacter,
      sourceCharacterId: 'c1',
      name: '苏璃',
      avatar: '',
      description: '角色简介',
      personality: '冷静',
      background: '背景',
      speakingStyle: '短句',
      endpointId: 'deepseek',
      isMuted: true,
    );
    final session = TheaterSession(
      id: 't1',
      title: '测试群聊',
      singleEndpointId: 'deepseek',
      isHidden: true,
      isLocked: true,
      multiApiReplyMode: TheaterMultiApiReplyMode.turnBased,
      nextSpeakerIndex: 2,
      lastOpenedAt: DateTime(2026, 2),
      participants: const [participant],
      createdAt: now,
      updatedAt: now,
    );

    final restored = TheaterSession.fromJson(session.toJson());
    final legacySessionJson = session.toJson()..remove('lastOpenedAt');
    final legacySession = TheaterSession.fromJson(legacySessionJson);
    expect(restored.participants.single.name, '苏璃');
    expect(restored.isHidden, isTrue);
    expect(restored.isLocked, isTrue);
    expect(restored.multiApiReplyMode, TheaterMultiApiReplyMode.turnBased);
    expect(restored.nextSpeakerIndex, 2);
    expect(restored.lastOpenedAt, DateTime(2026, 2));
    expect(restored.lastOpenedSortTime, DateTime(2026, 2));
    expect(legacySession.lastOpenedSortTime, session.updatedAt);
    expect(restored.participants.single.isMuted, isTrue);
    expect(restored.activeAiParticipants, isEmpty);
    expect(restored.recentMessageLimit, 30);
    final request = PromptBuilder.buildTheaterSingleApiRequest(
      session: session,
      novelSummary: '',
      messages: const [],
    );
    expect(request.first['content'], contains('<<<WhisnyaSpeaker:角色名>>>'));
    expect(request.first['content'], isNot(contains('JSON 数组')));
    expect(request[1]['content'], contains('【当前禁言】'));
    expect(request[1]['content'], contains('苏璃'));
  });

  test('reorders only AI participants and keeps user slot', () {
    const ai1 = TheaterParticipant(
      id: 'a1',
      source: TheaterRoleSource.appCharacter,
      name: '甲',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
    );
    const user = TheaterParticipant(
      id: 'u1',
      source: TheaterRoleSource.appCharacter,
      name: '用户角色',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
    );
    const ai2 = TheaterParticipant(
      id: 'a2',
      source: TheaterRoleSource.appCharacter,
      name: '乙',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
    );

    final reordered = reorderTheaterAiParticipants(
      const [ai1, user, ai2],
      userParticipantId: user.id,
      oldIndex: 0,
      newIndex: 1,
    );

    expect(reordered.map((item) => item.id), ['a2', 'u1', 'a1']);
  });

  test('keeps theater fixed prefix stable when dynamic memory changes', () {
    final now = DateTime(2026);
    const participant = TheaterParticipant(
      id: 'p1',
      source: TheaterRoleSource.appCharacter,
      name: '苏璃',
      avatar: '',
      description: '简介',
      personality: '冷静',
      background: '背景',
      speakingStyle: '短句',
    );
    final session = TheaterSession(
      id: 't1',
      title: '群聊',
      participants: const [participant],
      createdAt: now,
      updatedAt: now,
    );
    final changed = session.copyWith(
      theaterSummary: '新总结',
      participants: [participant.copyWith(isMuted: true)],
    );

    final before = PromptBuilder.buildTheaterSingleApiRequest(
      session: session,
      novelSummary: '',
      messages: const [],
    );
    final after = PromptBuilder.buildTheaterSingleApiRequest(
      session: changed,
      novelSummary: '小说总结',
      messages: const [],
    );

    expect(after.first, before.first);
    expect(after[1], isNot(before[1]));
  });

  test('does not summarize below the theater preservation floor', () {
    TheaterMessage message(int index, int round, TheaterSpeakerType type) =>
        TheaterMessage(
          id: 'm$index',
          sessionId: 's1',
          round: round,
          speakerType: type,
          speakerId: '',
          speakerName: type == TheaterSpeakerType.user ? '用户' : '角色',
          content: '$index',
          time: DateTime(2026),
        );
    final messages = [
      for (var round = 1; round <= 5; round++)
        message(round, round, TheaterSpeakerType.role),
      message(6, 6, TheaterSpeakerType.user),
    ];

    expect(
      PromptBuilder.theaterSummaryEndIndex(
        messages: messages,
        summarizedMessageCount: 0,
      ),
      0,
    );
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

  test('parses SillyTavern character card JSON fields', () {
    final parsed = RoleImportParser.parseJson({
      'spec': 'chara_card_v2',
      'data': {
        'name': '璃璃',
        'description': '喜欢读书的猫娘',
        'personality': '黏人、聪明',
        'scenario': '住在旧书店',
        'first_mes': '主人，今天也一起看书吗？',
        'mes_example': '<START>\n{{char}}: 喵。',
        'system_prompt': '保持猫娘语气',
        'tags': ['catgirl', 'book'],
      },
    });

    expect(parsed.name, '璃璃');
    expect(parsed.description, contains('读书'));
    expect(parsed.background, '住在旧书店');
    expect(parsed.openingMessage, contains('主人'));
    expect(parsed.extraPrompt, contains('保持猫娘语气'));
    expect(parsed.extraPrompt, contains('catgirl'));
  });

  test('parses common root-level character card JSON fields', () {
    final parsed = RoleImportParser.parseJson({
      'char_name': '小夏',
      'desc': '海边朋友',
      'greeting': '你来了。',
      'creator_notes': '不要编造记忆',
    });

    expect(parsed.name, '小夏');
    expect(parsed.description, '海边朋友');
    expect(parsed.openingMessage, '你来了。');
    expect(parsed.extraPrompt, '不要编造记忆');
  });

  test('extracts prompt text from JSON-LD prompt pages', () {
    final parsed = parsePromptPageHtmlForImport(r'''
<html>
<head><title>口语教练 | AiShort</title></head>
<body>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Article","headline":"口语教练","description":"练习英语口语","hasPart":{"@type":"CreativeWork","additionalType":"https://schema.org/SoftwareSourceCode","encodingFormat":"text/plain","name":"英语对话练习","text":"I want you to act as a spoken English teacher."}}
</script>
</body>
</html>
''');

    expect(parsed, isNotNull);
    expect(parsed!.name, '英语对话练习');
    expect(parsed.description, '练习英语口语');
    expect(parsed.extraPrompt, contains('spoken English teacher'));
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
      defaultEndpointId: 'deepseek',
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
      lastOpenedAt: DateTime(2026, 2),
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
    expect(NovelBook.fromJson(book.toJson()).lastOpenedAt, DateTime(2026, 2));
    expect(book.lastOpenedSortTime, DateTime(2026, 2));
    final legacyBookJson = book.toJson()..remove('lastOpenedAt');
    expect(
      NovelBook.fromJson(legacyBookJson).lastOpenedSortTime,
      book.updatedAt,
    );

    final request = PromptBuilder.buildNovelChatRequestMessages(
      book: book,
      aiRole: aiRole,
      userRole: userRole,
      historySummary: '小说聊天历史',
      summarizedMessageCount: 20,
      messages: [
        for (var i = 1; i <= 25; i++)
          ChatMessage(role: 'user', content: '消息 $i', time: DateTime(2026)),
      ],
    );
    expect(request, hasLength(14));
    expect(request.first['content'], isNot(contains('小说聊天历史')));
    expect(request[1]['content'], contains('小说聊天历史'));
    expect(request[1]['content'], contains('最近原始聊天优先'));
    expect(request[2]['content'], '消息 14');
  });
}
