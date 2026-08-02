import 'dart:async';

import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/app_character.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/qq_contact_binding.dart';
import '../../models/qq_integration_settings.dart';
import '../../models/unified_qq_message.dart';
import '../../models/unified_qq_reply.dart';
import '../../models/world_book.dart';
import '../../prompts/prompt_builder.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';
import '../chat/chat_summary_service.dart';
import '../chat/memory_context_service.dart';
import '../local_storage_service.dart';
import 'qq_exceptions.dart';

abstract interface class QqCharacterReplyService {
  Future<UnifiedQqReply> reply({
    required QqContactBinding binding,
    required UnifiedQqMessage message,
    required QqIntegrationSettings settings,
  });
}

class BackgroundCharacterChatService implements QqCharacterReplyService {
  BackgroundCharacterChatService({
    required LocalStorageService storage,
    required AiGateway aiGateway,
  }) : _storage = storage,
       _aiGateway = aiGateway;

  final LocalStorageService _storage;
  final AiGateway _aiGateway;

  Future<UnifiedQqReply> reply({
    required QqContactBinding binding,
    required UnifiedQqMessage message,
    required QqIntegrationSettings settings,
  }) async {
    var liveBinding = await _reloadBinding(binding.id);
    if (!liveBinding.enabled) {
      throw const QqBindingException('QQ 联系人绑定已暂停。');
    }
    var character = await _loadCharacter(liveBinding.characterId);
    final endpoint = await _loadEndpoint(character);
    var session = await _loadOrCreateSession(liveBinding, character);
    if (session.id != liveBinding.sessionId) {
      liveBinding = liveBinding.copyWith(
        sessionId: session.id,
        updatedAt: DateTime.now(),
      );
      await _storage.saveQqContactBinding(liveBinding);
    }

    var messages = await _storage.loadChatBySession(session);
    final userMessage = ChatMessage(
      role: 'user',
      content: message.text.trim(),
      time: message.timestamp,
    );
    messages = [...messages, userMessage];
    await _storage.saveChatBySession(session, messages);

    var summary = await _storage.loadSummaryBySession(session);
    final appSettings = await _storage.loadSettings();
    final summaryToken = AiCancelToken();
    final summaryUsage = <_UsageRequest>[];
    try {
      final updated =
          await updateChatSummary(
            _aiGateway,
            characterId: character.id,
            current: summary,
            messages: messages,
            summaryLimit: character.chatSummaryMessageLimit,
            settings: appSettings,
            endpoint: endpoint,
            cancelToken: summaryToken,
            onUsage: (usage, request) {
              summaryUsage.add(_UsageRequest(usage, request));
            },
          ).timeout(
            Duration(seconds: settings.requestTimeoutSeconds),
            onTimeout: () {
              summaryToken.cancel();
              throw TimeoutException('QQ 聊天总结请求超时');
            },
          );
      if (updated != null) {
        summary = updated;
        await _storage.saveSummaryBySession(updated);
      }
    } on Object {
      // A rolling-summary failure must not prevent this private reply.
    }
    for (final record in summaryUsage) {
      await _storage.recordAiUsage(
        requestType: 'qqCharacterSummary',
        model: endpoint.model,
        usage: record.usage,
        messages: record.messages,
        summaryUpdated: true,
      );
    }

    character = await _loadCharacter(liveBinding.characterId);
    final memories = await _storage.loadCharacterMemories(character.id);
    final worldBooks = await _storage.loadWorldBooks();
    final referencedBooks = worldBooks
        .where((book) => character.worldBookIds.contains(book.id))
        .toList();
    final worldBookEntries = <WorldBookEntry>[];
    for (final book in referencedBooks) {
      worldBookEntries.addAll(await _storage.loadWorldBookEntries(book.id));
    }
    final memoryContext = const MemoryContextService().build(
      entries: memories,
      characterId: character.id,
      sessionId: session.id,
      messages: messages,
      maxCharacters: appSettings.memoryContextMaxCharacters,
      worldBooks: referencedBooks,
      worldBookEntries: worldBookEntries,
      worldBookIds: character.worldBookIds,
    );
    final request = PromptBuilder.buildChatRequestMessages(
      character: character,
      userProfile: appSettings.userProfile,
      memoryPrompt: memoryContext.memoryPrompt,
      historySummary: summary.summary,
      summarizedMessageCount: summary.summarizedMessageCount,
      messages: messages,
      useFullContext: character.useFullChatContext,
    );

    AiUsage usage = const AiUsage();
    final replyToken = AiCancelToken();
    final text =
        (await _aiGateway
                .sendMessage(
                  apiKey: endpoint.apiKey,
                  baseUrl: endpoint.baseUrl,
                  model: endpoint.model,
                  messages: request,
                  cancelToken: replyToken,
                  onUsage: (value) => usage = value,
                )
                .timeout(
                  Duration(seconds: settings.requestTimeoutSeconds),
                  onTimeout: () {
                    replyToken.cancel();
                    throw TimeoutException('QQ AI 回复请求超时');
                  },
                ))
            .trim();
    if (text.isEmpty) {
      throw const QqIntegrationException('AI 返回了空回复。');
    }

    final assistant = ChatMessage(
      role: 'assistant',
      content: text,
      time: DateTime.now(),
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      model: endpoint.model,
    );
    messages = [...messages, assistant];
    await _storage.saveChatBySession(session, messages);
    await _storage.recordAiUsage(
      requestType: 'qqCharacterChat',
      model: endpoint.model,
      usage: usage,
      messages: request,
      summaryUpdated: false,
    );
    final now = DateTime.now();
    await _storage.saveCharacter(
      character.copyWith(updatedAt: now, lastUsedAt: now),
    );

    return UnifiedQqReply(
      externalUserId: liveBinding.externalUserId,
      bindingId: liveBinding.id,
      sessionId: session.id,
      text: text,
      createdAt: now,
    );
  }

  Future<QqContactBinding> _reloadBinding(String id) async {
    for (final binding in await _storage.loadQqContactBindings()) {
      if (binding.id == id) return binding;
    }
    throw const QqBindingException('QQ 联系人绑定不存在。');
  }

  Future<AppCharacter> _loadCharacter(String id) async {
    for (final character in await _storage.loadCharacters()) {
      if (character.id == id) return character;
    }
    throw const QqBindingException('绑定角色不存在。');
  }

  Future<AiEndpointConfig> _loadEndpoint(AppCharacter character) async {
    final config = await _storage.loadApiConfig();
    final endpoint = config.effectiveEndpoint(character.defaultEndpointId);
    final error = endpointValidationError(endpoint);
    if (error != null) throw QqConfigurationException(error);
    return endpoint!;
  }

  Future<ChatSession> _loadOrCreateSession(
    QqContactBinding binding,
    AppCharacter character,
  ) async {
    for (var session in await _storage.loadChatSessions(character.id)) {
      if (session.id != binding.sessionId) continue;
      if (!session.openingMessageInitialized) {
        session = await _storage.markOpeningMessageInitialized(
          sessionId: session.id,
          characterId: character.id,
        );
      }
      return session;
    }
    var session = await _storage.createChatSession(
      character.id,
      title: 'QQ · ${binding.displayName}',
    );
    session = await _storage.markOpeningMessageInitialized(
      sessionId: session.id,
      characterId: character.id,
    );
    return session;
  }
}

class _UsageRequest {
  const _UsageRequest(this.usage, this.messages);
  final AiUsage usage;
  final List<Map<String, String>> messages;
}
