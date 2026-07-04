import 'models/app_character.dart';
import 'models/chat_message.dart';
import 'models/novel_book.dart';

class PromptBuilder {
  const PromptBuilder._();

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
