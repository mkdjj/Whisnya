import 'dart:convert';

import 'models/app_character.dart';
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

  static const defaultRecentMessageLimit =
      AppCharacter.defaultChatSummaryMessageLimit;

  static String buildSystemPrompt(
    AppCharacter character,
    String historySummary,
  ) {
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

【开场白】
${character.openingMessage}

【补充设定】
${character.extraPrompt}

【历史总结】
${historySummary.isEmpty ? '暂无历史总结。' : historySummary}

要求：
1. 尽量保持角色设定。
2. 用户让你写代码、写文章、分析问题时，也要完成任务。
3. 不要主动说自己是程序或模型，除非用户明确询问。
4. 回复语言跟随用户。
5. 不要编造历史总结中没有的信息。
''';
  }

  static List<Map<String, String>> buildChatRequestMessages({
    required AppCharacter character,
    required String historySummary,
    required List<ChatMessage> messages,
    required bool useFullContext,
    int recentMessageLimit = defaultRecentMessageLimit,
  }) {
    final chatMessages = messages
        .where((message) => message.isUser || message.isAssistant)
        .toList();
    final startIndex = useFullContext
        ? 0
        : recentContextStartIndex(
            messageCount: chatMessages.length,
            summaryLimit: recentMessageLimit,
          );
    final requestMessages = chatMessages.skip(startIndex);
    return [
      {
        'role': 'system',
        'content': buildSystemPrompt(character, historySummary),
      },
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

  static String buildSummaryPrompt(List<ChatMessage> messages) {
    final transcript = messages
        .map((message) {
          final roleLabel = message.isUser ? '用户' : '角色';
          return '$roleLabel：${message.content}';
        })
        .join('\n\n');

    return '''
请总结以下聊天内容，用于下次继续对话时恢复上下文。

请输出以下内容：
1. 本次聊天主要内容。
2. 用户提到的重要信息。
3. 角色需要记住的设定或关系变化。
4. 当前未完成的话题或任务。
5. 下次聊天应该如何自然接上。

要求：
- 总结简洁清楚。
- 保留重要信息。
- 不要加入聊天中没有出现的新内容。
- 不要写无关内容。

聊天内容如下：
$transcript
''';
  }

  static String buildRollingSummaryPrompt({
    required String previousSummary,
    required List<ChatMessage> newMessages,
  }) {
    final transcript = newMessages
        .where((message) => message.isUser || message.isAssistant)
        .map((message) {
          final roleLabel = message.isUser ? '用户' : '角色';
          return '$roleLabel：${message.content}';
        })
        .join('\n\n');

    return '''
请把已有历史总结和新增聊天内容合并成一份新的历史总结，用于后续继续对话。

【已有历史总结】
${previousSummary.trim().isEmpty ? '暂无。' : previousSummary.trim()}

【新增聊天内容】
$transcript

要求：
- 保留重要事实、关系变化、用户偏好、当前未完成话题。
- 删除重复、口水话和无关细节。
- 不要加入聊天中没有出现的新内容。
- 只输出合并后的总结正文。
''';
  }

  static List<Map<String, String>> buildTheaterSingleApiRequest({
    required TheaterSession session,
    required String novelSummary,
    required List<TheaterMessage> messages,
  }) {
    final allowed = session.aiParticipants;
    return [
      {
        'role': 'system',
        'content':
            '''
你正在 Whisnya 的群聊剧场中同时扮演多个角色。

【群聊名称】
${session.title}

${_theaterNovelText(session, novelSummary)}

【群聊总结】
${session.theaterSummary.trim().isEmpty ? '暂无。' : session.theaterSummary}

【参与角色】
${_theaterParticipantsText(session.participants)}

【本轮允许你发言的角色】
${allowed.map((role) => '- ${role.name}').join('\n')}

要求：
1. 只允许上面列出的角色发言。
2. 如果用户扮演了某个角色，不要替该角色发言。
3. 每个角色保持自己的性格、背景和说话风格。
4. 不要求所有角色都发言，但至少输出 1 条回复。
5. 每条回复不要过长。
6. 只输出 JSON 数组，不要 Markdown 代码块。

输出格式：
[
  {"speaker":"角色名","content":"回复内容"}
]
''',
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

${_theaterNovelText(session, novelSummary)}

【群聊总结】
${session.theaterSummary.trim().isEmpty ? '暂无。' : session.theaterSummary}

【你只能扮演】
${_theaterParticipantText(participant)}

【其他参与者】
${session.participants.where((role) => role.id != participant.id).map((role) => '- ${role.name}').join('\n')}

要求：
1. 你只能作为「${participant.name}」发言。
2. 不要替其他角色或用户说话。
3. 不要输出旁白，除非用户明确要求。
4. 保持角色设定、语气和关系状态。
5. 直接输出回复正文，不要加角色名。
''',
      },
      {'role': 'user', 'content': _theaterMessagesText(messages)},
    ];
  }

  static String buildTheaterSummaryPrompt({
    required String previousSummary,
    required List<TheaterMessage> messages,
  }) {
    return '''
请把已有群聊总结和新增群聊内容合并成一份新的群聊总结。

【已有群聊总结】
${previousSummary.trim().isEmpty ? '暂无。' : previousSummary.trim()}

【新增群聊内容】
${_theaterMessagesText(messages)}

请输出：
1. 群聊目前发生了什么。
2. 用户说过的重要信息。
3. 各角色当前立场。
4. 各角色情绪变化。
5. 角色之间的关系变化。
6. 当前未结束的话题。
7. 后续对话应该如何自然接上。

要求：
- 不要编造对话中没有的信息。
- 保留重要冲突、暧昧、敌意、误会和关系变化。
- 尽量简洁，避免越来越长。
- 只输出总结正文。
''';
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

  static String _theaterNovelText(TheaterSession session, String novelSummary) {
    if (session.boundNovelId.isEmpty) return '【绑定小说】\n无';
    return '''
【绑定小说】
${session.boundNovelTitle}

【小说设定档】
${novelSummary.trim().isEmpty ? '暂无。' : novelSummary.trim()}
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
}
