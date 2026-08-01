import 'dart:convert';

import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/character_memory_entry.dart';
import '../../models/chat_message.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';

typedef MemoryExtractionUsageCallback =
    void Function(AiUsage usage, List<Map<String, String>> request);

class MemoryExtractionException implements Exception {
  const MemoryExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MemoryExtractionService {
  const MemoryExtractionService(this._gateway);

  final AiGateway _gateway;

  Future<List<CharacterMemoryEntry>> extract({
    required String characterId,
    required String sessionId,
    required List<ChatMessage> messages,
    required AiEndpointConfig endpoint,
    AiCancelToken? cancelToken,
    MemoryExtractionUsageCallback? onUsage,
    DateTime? now,
  }) async {
    if (characterId.trim().isEmpty || sessionId.trim().isEmpty) {
      throw const MemoryExtractionException('角色和会话不能为空。');
    }
    final endpointError = endpoint.validationError;
    if (endpointError != null) throw MemoryExtractionException(endpointError);

    final transcript = messages
        .where((message) => message.isUser || message.isAssistant)
        .toList()
        .reversed
        .take(50)
        .toList()
        .reversed
        .map(
          (message) =>
              '${message.isUser ? '用户' : '助手'}：${message.effectiveContent}',
        )
        .join('\n');
    final request = <Map<String, String>>[
      {'role': 'system', 'content': _extractionPrompt},
      {
        'role': 'user',
        'content': transcript.isEmpty ? '当前会话没有可提取的消息。' : transcript,
      },
    ];
    final raw = await _gateway.sendMessage(
      apiKey: endpoint.apiKey,
      baseUrl: endpoint.baseUrl,
      model: endpoint.model,
      messages: request,
      temperature: 0.2,
      cancelToken: cancelToken,
      onUsage: onUsage == null ? null : (usage) => onUsage(usage, request),
    );
    return _parse(
      raw,
      characterId: characterId.trim(),
      sessionId: sessionId.trim(),
      now: now ?? DateTime.now(),
    );
  }
}

List<CharacterMemoryEntry> _parse(
  String raw, {
  required String characterId,
  required String sessionId,
  required DateTime now,
}) {
  final start = raw.indexOf('[');
  final end = raw.lastIndexOf(']');
  if (start < 0 || end < start) {
    throw const MemoryExtractionException('AI 返回内容中没有有效的 JSON 数组。');
  }
  late final Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } on FormatException catch (error) {
    throw MemoryExtractionException('AI 返回的 JSON 无法解析：${error.message}');
  }
  if (decoded is! List) {
    throw const MemoryExtractionException('AI 返回的 JSON 必须是数组。');
  }

  final result = <CharacterMemoryEntry>[];
  for (final value in decoded) {
    if (result.length == 10) break;
    if (value is! Map) continue;
    final title = value['title'] is String
        ? (value['title'] as String).trim()
        : '';
    final content = value['content'] is String
        ? (value['content'] as String).trim()
        : '';
    if (title.isEmpty || content.isEmpty) continue;
    final scope = value['scope'] == MemoryScope.character.name
        ? MemoryScope.character
        : MemoryScope.session;
    result.add(
      CharacterMemoryEntry(
        id: 'memory_${now.microsecondsSinceEpoch}_${result.length}',
        characterId: characterId,
        scope: scope,
        sessionId: scope == MemoryScope.session ? sessionId : null,
        title: title,
        content: content,
        keywords: const [],
        priority: value['priority'] is num
            ? (value['priority'] as num).toInt()
            : 50,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  return result;
}

const _extractionPrompt = '''从聊天记录中提取最多 10 条对未来对话有持续价值的记忆，只输出 JSON 数组。
只提取已确认的事实、关系、承诺、偏好、固定称呼和重要事件，不要提取寒暄、重复内容、一次性动作或推测，不得编造。
scope 使用 character 表示跨会话长期记忆，使用 session 表示当前剧情记忆。不要创建世界书或关键词词条，priority 必须为 0-100。
格式：[{"title":"标题","content":"内容","scope":"character","priority":50}]''';
