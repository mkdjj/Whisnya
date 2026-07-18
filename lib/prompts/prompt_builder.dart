import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/novel_book.dart';
import '../models/theater.dart';
import '../services/theater/theater_reply_engine.dart' as theater_engine;
import '../utils/chat_context_policy.dart';

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

【上下文使用规则】
1. 历史总结用于保存长期事实、关系和事件。
2. 后面的最近原始聊天优先级高于总结。
3. 必须继承最近原始聊天中的称呼、语气、句式长度、动作描写格式、括号格式、情绪强度和未完成话题。
4. 不要把总结的书面语气当成角色说话语气。
5. 如果总结与最近原始聊天冲突，以最近原始聊天为准。
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
        : chatContextStartIndex(
            summarizedMessageCount: summarizedMessageCount,
            messageCount: chatMessages.length,
          );
    final requestMessages = chatMessages.skip(startIndex);
    return [
      {'role': 'system', 'content': buildSystemPrompt(character)},
      if (!useFullContext)
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
- 总结不得把角色语气改写成总结者语气；只记录角色的语气规则，不要用总结语气模仿角色。
- 保留角色之间的固定称呼和最近输出的动作、对白、括号格式。
- 明确记录最后一个未完成动作和未完成话题，不要删除会影响下一句自然接续的信息。
- 最近状态比早期细节优先，不得把暧昧、冷淡、毒舌、礼貌等关系语气统一成中性描述。
- 删除重复、口水话和无关细节。
- 最终总结不超过约 $maxCharacters 个中文字符，超长时优先压缩旧细节。
- 输出时只按上面的总结项目组织内容，不要额外增加其他项目。
''';
  }

  static String limitSummary(String summary, int maxCharacters) {
    final text = summary.trim();
    final runes = text.runes.toList();
    if (runes.length <= maxCharacters) return text;
    final prefix = String.fromCharCodes(runes.take(maxCharacters));
    final minimumBoundary = (maxCharacters * 0.7).floor();
    for (final delimiter in const ['\n\n', '\n', '。', '？', '！', '?', '!']) {
      final index = prefix.lastIndexOf(delimiter);
      if (index < 0) continue;
      final end = index + delimiter.length;
      if (prefix.substring(0, end).runes.length >= minimumBoundary) {
        return prefix.substring(0, end).trim();
      }
    }
    return prefix.trim();
  }

  static int theaterSummaryEndIndex({
    required List<TheaterMessage> messages,
    required int summarizedMessageCount,
    int messageBatchSize = 20,
    int roundBatchSize = 5,
  }) {
    return theater_engine.theaterSummaryEndIndex(
      messages: messages,
      summarizedMessageCount: summarizedMessageCount,
      messageBatchSize: messageBatchSize,
      roundBatchSize: roundBatchSize,
    );
  }

  static List<Map<String, String>> buildTheaterSingleApiRequest({
    required TheaterSession session,
    required String novelSummary,
    required List<TheaterMessage> messages,
    List<TheaterParticipant>? allowedParticipants,
    TheaterGenerationIntent generationIntent =
        TheaterGenerationIntent.userReply,
    TheaterReplyPhase phase = TheaterReplyPhase.main,
  }) {
    final allowed = allowedParticipants ?? session.activeAiParticipants;
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
        'content': _theaterSummaryMemory(session, novelSummary),
      },
      ..._theaterHistoryMessages(messages),
      {
        'role': 'system',
        'content': _theaterTurnInstruction(
          session: session,
          allowed: allowed,
          generationIntent: generationIntent,
          phase: phase,
        ),
      },
    ];
  }

  static List<Map<String, String>> buildTheaterParticipantRequest({
    required TheaterSession session,
    required TheaterParticipant participant,
    required String novelSummary,
    required List<TheaterMessage> messages,
    TheaterGenerationIntent generationIntent =
        TheaterGenerationIntent.userReply,
    TheaterReplyPhase phase = TheaterReplyPhase.main,
    bool previousOutputInvalid = false,
  }) {
    return [
      {
        'role': 'system',
        'content':
            '''
你正在 Whisnya 的群聊剧场中扮演一个由动态状态指定的角色。

【群聊名称】
${session.title}

${_theaterNovelFixedText(session)}

【全部参与角色（固定顺序）】
${_theaterParticipantsText(session.participants)}

要求：
1. 你只能作为动态状态中的当前发言角色发言。
2. 不要替其他角色或用户说话。
3. 不要输出旁白，除非用户明确要求。
4. 保持角色设定、语气和关系状态。
5. 直接输出回复正文，不要加角色名。
''',
      },
      {
        'role': 'system',
        'content': _theaterSummaryMemory(session, novelSummary),
      },
      ..._theaterHistoryMessages(messages),
      {
        'role': 'system',
        'content': _theaterTurnInstruction(
          session: session,
          allowed: participant.isMuted ? const [] : [participant],
          currentParticipant: participant,
          generationIntent: generationIntent,
          phase: phase,
          previousOutputInvalid: previousOutputInvalid,
        ),
      },
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
- 总结不得把角色语气改写成总结者语气；只记录每个角色的语气规则。
- 保留角色之间的固定称呼和最近输出的动作、对白、括号格式。
- 明确记录最后一个未完成动作、未完成话题和下一步应接续的内容。
- 最近状态比早期细节优先，不得把暧昧、冷淡、毒舌、礼貌等关系语气统一成中性描述。
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

  static String _theaterNovelFixedText(TheaterSession session) {
    if (session.boundNovelId.isEmpty) return '【绑定小说】\n无';
    return '''
【绑定小说】
${session.boundNovelTitle}
''';
  }

  static String _theaterSummaryMemory(
    TheaterSession session,
    String novelSummary,
  ) {
    return '''
【小说总结】
${novelSummary.trim().isEmpty ? '暂无。' : novelSummary.trim()}

【群聊总结】
${session.theaterSummary.trim().isEmpty ? '暂无。' : session.theaterSummary.trim()}

【群聊上下文规则】
最近原始群聊优先决定角色当前语气，群聊总结只保存长期状态。
不要因为读到总结而把回复写成旁白、报告或剧情概述。
''';
  }

  static String _theaterTurnInstruction({
    required TheaterSession session,
    required List<TheaterParticipant> allowed,
    TheaterParticipant? currentParticipant,
    required TheaterGenerationIntent generationIntent,
    required TheaterReplyPhase phase,
    bool previousOutputInvalid = false,
  }) {
    final muted = session.allAiParticipants
        .where((participant) => participant.isMuted)
        .map((participant) => participant.name)
        .join('、');
    return '''
当前发言角色：${currentParticipant == null ? '单 API 多角色生成' : currentParticipant.name}

【当前用户身份】
${session.userParticipant?.name ?? '用户本人'}

【本轮允许发言】
${allowed.isEmpty ? '无' : allowed.map((participant) => participant.name).join('、')}

【当前禁言】
${muted.isEmpty ? '无' : muted}

【生成阶段】
${phase == TheaterReplyPhase.main ? '主要回复阶段' : '追加发言阶段'}

${currentParticipant == null ? '' : '''
【本轮唯一发言者】
${currentParticipant.name}

你只能输出“${currentParticipant.name}”这一名角色的一段回复正文。
严禁输出其他角色的台词、动作或心理活动，严禁替用户发言。
不要输出角色名、[角色名]、角色名冒号、WhisnyaSpeaker 标记或多个角色分段。
其他角色仅供理解关系，禁止代替发言。
最终只输出当前角色的回复正文，不要解释规则。
${previousOutputInvalid ? '''
【上次输出错误】
上次回复包含了其他角色内容或多个角色分段。
本次只能输出“${currentParticipant.name}”的回复正文，不要输出任何角色名、标签、冒号前缀或其他角色内容。
''' : ''}
'''}

${_theaterIntentText(generationIntent)}
''';
  }

  static String _theaterIntentText(TheaterGenerationIntent intent) {
    return switch (intent) {
      TheaterGenerationIntent.userReply =>
        '''
【本轮生成意图】
用户刚刚发言，请自然回应最新用户消息。''',
      TheaterGenerationIntent.continueConversation =>
        '''
【本轮生成意图】
本轮没有新的用户消息。
请优先回应群聊中最后一条非空角色消息，延续角色之间刚刚发生的对话。
不要重新回答更早的用户消息，除非最后一条角色消息明确重新提到了该问题。
回复应表现为自然接话，不要重新开启同一话题。''',
    };
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
    final valid = messages
        .where(theater_engine.isValidTheaterContextMessage)
        .toList();
    if (valid.isEmpty) return '暂无群聊记录。';
    return valid
        .map((message) => '${message.speakerName}：${message.content.trim()}')
        .join('\n\n');
  }

  static List<Map<String, String>> _theaterHistoryMessages(
    List<TheaterMessage> messages,
  ) {
    return [
      for (final message in messages.where(
        theater_engine.isValidTheaterContextMessage,
      ))
        {
          'role': message.speakerType == TheaterSpeakerType.user
              ? 'user'
              : 'assistant',
          'content': '[${message.speakerName}] ${message.content.trim()}',
        },
    ];
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
    final start = chatContextStartIndex(
      summarizedMessageCount: summarizedMessageCount,
      messageCount: chatMessages.length,
    );
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

【上下文使用规则】
历史总结只保存长期事实；后面的最近原始聊天优先级高于总结。
必须继承最近原始聊天中的称呼、语气、句式长度、动作描写格式、括号格式、情绪强度和未完成话题。
如果总结与最近原始聊天冲突，以最近原始聊天为准，不要把总结写成角色说话语气。
''',
      },
      for (final message in chatMessages.skip(start))
        {'role': message.role, 'content': message.content},
    ];
  }
}
