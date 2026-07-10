import 'dart:convert';

import 'models/app_character.dart';
import 'models/app_settings.dart';
import 'models/chat_message.dart';
import 'models/novel_book.dart';
import 'models/theater.dart';

class TheaterReplyDraft {
  const TheaterReplyDraft({required this.speaker, required this.content});

  final String speaker;
  final String content;
}

class PromptBuilder {
  const PromptBuilder._();

  static String buildSystemPrompt(AppCharacter character) {
    return '''
你正在扮演用户创建的角色，请严格按照角色设定回复。

【角色名称】
${character.name}

【角色简介】
${character.description}

【性格设定】
${character.personality}

【背景故事】
${character.background}

【说话风格】
${character.speakingStyle}

【补充设定】
${character.extraPrompt}

要求：
1. 尽量保持角色设定。
2. 用户让你写代码、写文章、分析问题时，也要完成任务。
3. 不要主动说自己是程序或模型，除非用户明确询问。
4. 回复语言跟随用户。
5. 不要编造聊天记录中没有的信息。
''';
  }

  static String buildChatMemoryPrompt(String historySummary) =>
      '''
【动态历史总结】
${historySummary.trim().isEmpty ? '暂无。' : historySummary.trim()}
''';

  static List<Map<String, String>> buildChatRequestMessages({
    required AppCharacter character,
    required String historySummary,
    required int summarizedMessageCount,
    required List<ChatMessage> messages,
    required bool useFullContext,
  }) {
    final chatMessages = messages
        .where((message) => message.isUser || message.isAssistant)
        .toList();
    final startIndex = useFullContext
        ? 0
        : summarizedMessageCount.clamp(0, chatMessages.length).toInt();
    final requestMessages = chatMessages.skip(startIndex);
    return [
      {'role': 'system', 'content': buildSystemPrompt(character)},
      {'role': 'system', 'content': buildChatMemoryPrompt(historySummary)},
      for (final message in requestMessages)
        {'role': message.role, 'content': message.content},
    ];
  }

  static int recentContextStartIndex({
    required int messageCount,
    required int summaryLimit,
  }) {
    if (messageCount <= summaryLimit) return 0;
    final safeLimit = summaryLimit
        .clamp(
          AppCharacter.minChatSummaryMessageLimit,
          AppCharacter.maxChatSummaryMessageLimit,
        )
        .toInt();
    final recentBeforeCurrent = (messageCount - safeLimit)
        .clamp(10, safeLimit)
        .toInt();
    final start = messageCount - 1 - recentBeforeCurrent;
    return start < 0 ? 0 : start;
  }

  static int rollingSummaryEndIndex({
    required int messageCount,
    required int summaryLimit,
  }) {
    if (messageCount <= summaryLimit) return 0;
    final safeLimit = summaryLimit
        .clamp(
          AppCharacter.minChatSummaryMessageLimit,
          AppCharacter.maxChatSummaryMessageLimit,
        )
        .toInt();
    final previousCount = messageCount - 1;
    return (previousCount ~/ safeLimit) * safeLimit;
  }

  static String buildSummaryPrompt(
    List<ChatMessage> messages, {
    bool useCustomItems = false,
    List<String> customItems = const [],
  }) {
    final transcript = messages
        .map((message) {
          final roleLabel = message.isUser ? '用户' : '角色';
          return '$roleLabel：${message.content}';
        })
        .join('\n\n');
    final items = _summaryItemsText(
      useCustomItems: useCustomItems,
      customItems: customItems,
      defaults: AppSettings.defaultChatSummaryItems,
      cleaner: AppSettings.cleanChatSummaryItems,
    );

    return '''
请总结以下聊天内容，用于下次继续对话时恢复上下文。

请输出以下内容：
$items

要求：
- 本次没有单独提供已有总结时，请把聊天内容整理成新的历史总结。
- 已有总结是旧记忆底稿，不能只总结新增内容。
- 新增内容只能补充、修正、推进旧总结。
- 仍然成立的信息必须保留。
- 如果新增内容和已有总结冲突，以新增内容为准。
- 不要编造没有出现过的信息。
- 严格区分用户、角色、系统。
- 不要把角色动作写成用户想法。
- 不要把用户括号动作强行解释成心理。
- 输出时只按上面的总结项目组织内容，不要额外增加其他项目。

聊天内容如下：
$transcript
''';
  }

  static String buildRollingSummaryPrompt({
    required String previousSummary,
    required List<ChatMessage> newMessages,
    bool useCustomItems = false,
    List<String> customItems = const [],
    int maxCharacters = 1500,
  }) {
    final transcript = newMessages
        .where((message) => message.isUser || message.isAssistant)
        .map((message) {
          final roleLabel = message.isUser ? '用户' : '角色';
          return '$roleLabel：${message.content}';
        })
        .join('\n\n');
    final items = _summaryItemsText(
      useCustomItems: useCustomItems,
      customItems: customItems,
      defaults: AppSettings.defaultChatSummaryItems,
      cleaner: AppSettings.cleanChatSummaryItems,
    );

    return '''
请把已有历史总结和新增聊天内容合并成一份新的历史总结，用于后续继续对话。

【已有历史总结】
${previousSummary.trim().isEmpty ? '暂无。' : previousSummary.trim()}

【新增聊天内容】
$transcript

请输出以下内容：
$items

要求：
- 已有总结是旧记忆底稿，不能只总结新增内容。
- 新增内容只能补充、修正、推进旧总结。
- 仍然成立的信息必须保留。
- 如果新增内容和已有总结冲突，以新增内容为准。
- 不要编造没有出现过的信息。
- 严格区分用户、角色、系统。
- 不要把角色动作写成用户想法。
- 不要把用户括号动作强行解释成心理。
- 删除重复、口水话和无关细节。
- 最终总结不超过约 $maxCharacters 个中文字符，超长时优先压缩旧细节。
- 输出时只按上面的总结项目组织内容，不要额外增加其他项目。
''';
  }

  static String limitSummary(String summary, int maxCharacters) {
    final text = summary.trim();
    final runes = text.runes;
    return runes.length <= maxCharacters
        ? text
        : String.fromCharCodes(runes.take(maxCharacters));
  }

  static int theaterSummaryEndIndex({
    required List<TheaterMessage> messages,
    required int summarizedMessageCount,
    int messageBatchSize = 20,
    int roundBatchSize = 5,
  }) {
    if (messages.isEmpty) return 0;
    final start = summarizedMessageCount.clamp(0, messages.length).toInt();
    var end = messages.length;
    if (messages.last.speakerType == TheaterSpeakerType.user) {
      final currentRound = messages.last.round;
      while (end > start && messages[end - 1].round == currentRound) {
        end--;
      }
    }
    if (end <= start) return start;
    final pending = messages.sublist(start, end);
    final completeRounds = pending
        .map((message) => message.round)
        .toSet()
        .length;
    return pending.length >= messageBatchSize ||
            completeRounds >= roundBatchSize
        ? end
        : start;
  }

  static List<Map<String, String>> buildTheaterSingleApiRequest({
    required TheaterSession session,
    required String novelSummary,
    required List<TheaterMessage> messages,
  }) {
    final allowed = session.activeAiParticipants;
    return [
      {
        'role': 'system',
        'content':
            '''
你正在 Whisnya 的群聊剧场中同时扮演多个角色。

【群聊名称】
${session.title}

${_theaterNovelFixedText(session)}

【参与角色】
${_theaterParticipantsText(session.participants)}

要求：
1. 只允许动态状态列出的角色发言。
2. 如果用户扮演了某个角色，不要替该角色发言。
3. 每个角色保持自己的性格、背景和说话风格。
4. 不要求所有角色都发言，但至少输出 1 条回复。
5. 每条回复不要过长。
6. 每段回复前必须单独一行输出角色标记。
7. 角色名必须完全匹配允许发言角色列表。
8. 不要输出 JSON、Markdown 代码块或说明文字。

输出格式：
<<<WhisnyaSpeaker:角色名>>>
回复内容

<<<WhisnyaSpeaker:另一角色名>>>
回复内容
''',
      },
      {
        'role': 'system',
        'content': _theaterDynamicMemory(
          session: session,
          novelSummary: novelSummary,
          allowed: allowed,
        ),
      },
      {'role': 'user', 'content': _theaterMessagesText(messages)},
    ];
  }

  static List<Map<String, String>> buildTheaterParticipantRequest({
    required TheaterSession session,
    required TheaterParticipant participant,
    required String novelSummary,
    required List<TheaterMessage> messages,
  }) {
    return [
      {
        'role': 'system',
        'content':
            '''
你正在 Whisnya 的群聊剧场中扮演一个角色。

【群聊名称】
${session.title}

${_theaterNovelFixedText(session)}

【你只能扮演】
${_theaterParticipantText(participant)}

【全部参与角色（固定顺序）】
${_theaterParticipantsText(session.participants)}

要求：
1. 你只能作为「${participant.name}」发言。
2. 不要替其他角色或用户说话。
3. 不要输出旁白，除非用户明确要求。
4. 保持角色设定、语气和关系状态。
5. 直接输出回复正文，不要加角色名。
''',
      },
      {
        'role': 'system',
        'content': _theaterDynamicMemory(
          session: session,
          novelSummary: novelSummary,
          allowed: participant.isMuted ? const [] : [participant],
        ),
      },
      {'role': 'user', 'content': _theaterMessagesText(messages)},
    ];
  }

  static String buildTheaterSummaryPrompt({
    required String previousSummary,
    required List<TheaterMessage> messages,
    bool useCustomItems = false,
    List<String> customItems = const [],
  }) {
    final items = _summaryItemsText(
      useCustomItems: useCustomItems,
      customItems: customItems,
      defaults: AppSettings.defaultTheaterSummaryItems,
      cleaner: AppSettings.cleanTheaterSummaryItems,
    );

    return '''
请把已有群聊总结和新增群聊内容合并成一份新的群聊总结。

【已有群聊总结】
${previousSummary.trim().isEmpty ? '暂无。' : previousSummary.trim()}

【新增群聊内容】
${_theaterMessagesText(messages)}

请输出：
$items

要求：
- 已有总结是旧记忆底稿，不能只总结新增内容。
- 新增内容只能补充、修正、推进旧总结。
- 仍然成立的信息必须保留。
- 如果新增内容和已有总结冲突，以新增内容为准。
- 不要编造没有出现过的信息。
- 严格区分用户、角色、系统。
- 不要把角色动作写成用户想法。
- 不要把用户括号动作强行解释成心理。
- 尽量简洁，避免越来越长。
- 最终总结不超过约 1500 个中文字符，超长时优先压缩旧细节。
- 输出时只按上面的总结项目组织内容，不要额外增加其他项目。
''';
  }

  static String _summaryItemsText({
    required bool useCustomItems,
    required List<String> customItems,
    required List<String> defaults,
    required List<String> Function(Iterable<String>) cleaner,
  }) {
    final items = useCustomItems ? cleaner(customItems) : defaults;
    return [
      for (var i = 0; i < items.length; i++) '${i + 1}. ${items[i]}',
    ].join('\n');
  }

  static List<TheaterReplyDraft> parseTheaterReplies(String raw) {
    final text = _stripJsonFence(raw);
    final decoded = jsonDecode(text);
    final list = switch (decoded) {
      List value => value,
      {'replies': List value} => value,
      {'messages': List value} => value,
      _ => throw const FormatException('not a theater reply list'),
    };
    return list
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => TheaterReplyDraft(
            speaker: (item['speaker'] ?? item['name'] ?? '').toString().trim(),
            content: (item['content'] ?? item['message'] ?? '')
                .toString()
                .trim(),
          ),
        )
        .where((reply) => reply.speaker.isNotEmpty && reply.content.isNotEmpty)
        .toList();
  }

  static String _stripJsonFence(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }

  static String _theaterNovelFixedText(TheaterSession session) {
    if (session.boundNovelId.isEmpty) return '【绑定小说】\n无';
    return '''
【绑定小说】
${session.boundNovelTitle}
''';
  }

  static String _theaterDynamicMemory({
    required TheaterSession session,
    required String novelSummary,
    required List<TheaterParticipant> allowed,
  }) {
    final muted = session.allAiParticipants
        .where((participant) => participant.isMuted)
        .map((participant) => participant.name)
        .join('、');
    return '''
【小说总结】
${novelSummary.trim().isEmpty ? '暂无。' : novelSummary.trim()}

【群聊总结】
${session.theaterSummary.trim().isEmpty ? '暂无。' : session.theaterSummary.trim()}

【本轮允许发言】
${allowed.isEmpty ? '无' : allowed.map((participant) => participant.name).join('、')}

【当前禁言】
${muted.isEmpty ? '无' : muted}
''';
  }

  static String _theaterParticipantsText(List<TheaterParticipant> roles) {
    return roles.map(_theaterParticipantText).join('\n\n');
  }

  static String _theaterParticipantText(TheaterParticipant role) {
    return '''
- 名称：${role.name}
  简介：${role.description}
  性格：${role.personality}
  背景：${role.background}
  说话风格：${role.speakingStyle}
''';
  }

  static String _theaterMessagesText(List<TheaterMessage> messages) {
    if (messages.isEmpty) return '暂无群聊记录。';
    return messages
        .map((message) => '${message.speakerName}：${message.content}')
        .join('\n\n');
  }

  static String buildNovelChunkPrompt(String chunk, int index, int total) {
    return '''
请阅读小说片段 $index / $total，并提炼信息。

请输出：
1. 本片段剧情摘要。
2. 出现的主要角色。
3. 角色关系与性格线索。
4. 重要世界观、地点、事件。

要求：
- 简洁但不要漏掉关键设定。
- 不要加入原文没有的信息。

小说片段：
$chunk
''';
  }

  static String buildNovelMergePrompt(List<String> summaries) {
    return '''
请合并以下小说分段摘要，生成可用于角色扮演聊天的小说设定档，并提取适合 AI 扮演的角色。

请只输出 JSON，不要使用 Markdown 代码块：
{
  "summary": "小说总设定与剧情摘要",
  "roles": [
    {
      "name": "角色名",
      "description": "角色简介",
      "personality": "性格设定",
      "background": "背景故事",
      "speakingStyle": "说话风格"
    }
  ]
}

要求：
- 优先提取女性角色，但不要编造不存在的角色。
- 每个角色只输出 name、description、personality、background、speakingStyle 这 5 个字段，不要输出开场白、补充设定或其他字段。
- 只输出反复出现、戏份充足或推动主线的重要角色；把出场次数明显低、戏份明显少、路人、临时名字删掉，不要放进 roles。
- roles 最多 5 个，只保留最主要的人物。
- 所有字段都用中文。
- JSON 必须可解析。

分段摘要：
${summaries.join('\n\n---\n\n')}
''';
  }

  static String buildNovelChatSystemPrompt(
    NovelBook book,
    NovelRoleCandidate role,
    NovelRoleCandidate? userRole,
  ) {
    final userRoleText = userRole == null
        ? '用户未指定固定角色，可以扮演自己、原作角色或临时角色。'
        : '''
用户选择扮演：${userRole.name}
用户角色简介：${userRole.description}
用户角色性格：${userRole.personality}
用户角色背景：${userRole.background}
互动时把用户当作该角色，不要替用户说话或行动。''';

    return '''
你正在小说《${book.title}》的私密聊天模式中扮演角色。

【小说设定档】
${book.summary}

【你扮演的角色】
${role.name}

【角色简介】
${role.description}

【性格设定】
${role.personality}

【背景故事】
${role.background}

【说话风格】
${role.speakingStyle}

【用户扮演】
$userRoleText

要求：
1. 严格保持小说设定和角色口吻。
2. 用户没有固定角色时，可以扮演自己、原作角色或临时角色，你要自然接戏。
3. 不要主动说自己是 AI 或模型。
4. 不要把小说原文整段复述给用户。
5. 回复语言跟随用户。
''';
  }

  static List<Map<String, String>> buildNovelChatRequestMessages({
    required NovelBook book,
    required NovelRoleCandidate aiRole,
    required NovelRoleCandidate? userRole,
    required String historySummary,
    required int summarizedMessageCount,
    required List<ChatMessage> messages,
  }) {
    final chatMessages = messages
        .where((message) => message.isUser || message.isAssistant)
        .toList();
    final start = summarizedMessageCount.clamp(0, chatMessages.length).toInt();
    return [
      {
        'role': 'system',
        'content': buildNovelChatSystemPrompt(book, aiRole, userRole),
      },
      {
        'role': 'system',
        'content':
            '''
【小说聊天历史总结】
${historySummary.trim().isEmpty ? '暂无。' : historySummary.trim()}
''',
      },
      for (final message in chatMessages.skip(start))
        {'role': message.role, 'content': message.content},
    ];
  }
}
