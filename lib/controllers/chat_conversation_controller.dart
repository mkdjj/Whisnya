import 'dart:collection';

import '../models/chat_message.dart';
import '../models/message_anchor.dart';
import '../models/chat_reply_variant.dart';
import '../models/chat_summary.dart';
import '../services/chat/chat_summary_service.dart';

enum ChatMessageDeletion { ignored, removed, summaryInvalidated }

final class ChatConversationController {
  ChatConversationController({required String characterId})
    : _summary = ChatSummary.empty(characterId);

  var _messages = <ChatMessage>[];
  ChatSummary _summary;

  List<ChatMessage> get messages => UnmodifiableListView(_messages);
  ChatSummary get summary => _summary;
  List<ChatMessage> get chatMessagesOnly => _messages
      .where((message) => message.isUser || message.isAssistant)
      .toList();

  int get lastUserMessageIndex {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isUser) return i;
    }
    return -1;
  }

  void load({
    required List<ChatMessage> messages,
    required ChatSummary summary,
  }) {
    replaceMessages(messages);
    _summary = summary;
  }

  void replaceMessages(List<ChatMessage> messages) {
    _messages = assignMessageIds(messages);
  }

  void setSummary(ChatSummary summary) => _summary = summary;

  void append(ChatMessage message) =>
      _messages = assignMessageIds([..._messages, message]);

  void replaceLast(ChatMessage message) {
    if (_messages.isEmpty) return;
    _messages = [
      ..._messages.take(_messages.length - 1),
      message.copyWith(id: _messages.last.id),
    ];
  }

  bool addAssistantVariant(int messageIndex, ChatReplyVariant variant) {
    if (!_isAssistantIndex(messageIndex) || variant.content.trim().isEmpty) {
      return false;
    }
    final message = _messages[messageIndex];
    final variants = [
      ...message.variants.where((item) => item.content.trim().isNotEmpty),
    ];
    if (variants.isEmpty && message.content.trim().isNotEmpty) {
      variants.add(
        ChatReplyVariant(
          id: 'original_${message.id}',
          content: message.content,
          time: message.time,
          innerVoice: message.innerVoice,
          reasoningContent: message.reasoningContent,
          replyState: message.replyState,
          endpointId: message.endpointId,
          endpointName: message.endpointName,
          model: message.model,
        ),
      );
    }
    variants.add(variant.copyWith(id: newStoryId()));
    _replaceAt(
      messageIndex,
      message.copyWith(
        variants: variants,
        selectedVariantIndex: variants.length - 1,
      ),
    );
    return true;
  }

  bool setAssistantInnerVoice({
    required int messageIndex,
    required String replySnapshot,
    required String innerVoice,
    int? variantIndex,
  }) {
    final normalized = innerVoice.trim();
    if (!_isAssistantIndex(messageIndex) || normalized.isEmpty) return false;
    final message = _messages[messageIndex];
    final variants = message.variants
        .where((variant) => variant.content.trim().isNotEmpty)
        .toList();

    if (variantIndex != null) {
      if (variantIndex < 0 || variantIndex >= variants.length) return false;
      if (variants[variantIndex].content != replySnapshot) return false;
      variants[variantIndex] = variants[variantIndex].copyWith(
        innerVoice: normalized,
      );
      _replaceAt(messageIndex, message.copyWith(variants: variants));
      return true;
    }

    // A base reply can be converted to candidate 0 while its voice is pending.
    if (variants.isNotEmpty) {
      if (variants.first.content != replySnapshot) return false;
      variants[0] = variants.first.copyWith(innerVoice: normalized);
      _replaceAt(messageIndex, message.copyWith(variants: variants));
      return true;
    }

    if (message.content != replySnapshot) return false;
    _replaceAt(messageIndex, message.copyWith(innerVoice: normalized));
    return true;
  }

  String? assistantInnerVoiceAt({
    required int messageIndex,
    required String replySnapshot,
    int? variantIndex,
  }) {
    if (!_isAssistantIndex(messageIndex)) return null;
    final message = _messages[messageIndex];
    final variants = message.variants
        .where((variant) => variant.content.trim().isNotEmpty)
        .toList();
    if (variantIndex != null) {
      if (variantIndex < 0 || variantIndex >= variants.length) return null;
      return variants[variantIndex].content == replySnapshot
          ? variants[variantIndex].innerVoice
          : null;
    }
    if (variants.isNotEmpty) {
      return variants.first.content == replySnapshot
          ? variants.first.innerVoice
          : null;
    }
    return message.content == replySnapshot ? message.innerVoice : null;
  }

  bool restoreAssistantInnerVoice({
    required int messageIndex,
    required String replySnapshot,
    required String expectedInnerVoice,
    required String previousInnerVoice,
    int? variantIndex,
  }) {
    if (!_isAssistantIndex(messageIndex)) return false;
    final message = _messages[messageIndex];
    final variants = message.variants
        .where((variant) => variant.content.trim().isNotEmpty)
        .toList();
    final expected = expectedInnerVoice.trim();
    final previous = previousInnerVoice;

    if (variantIndex != null) {
      if (variantIndex < 0 || variantIndex >= variants.length) return false;
      final variant = variants[variantIndex];
      if (variant.content != replySnapshot ||
          variant.innerVoice.trim() != expected) {
        return false;
      }
      variants[variantIndex] = variant.copyWith(
        innerVoice: previous,
        clearInnerVoice: previous.trim().isEmpty,
      );
      _replaceAt(messageIndex, message.copyWith(variants: variants));
      return true;
    }

    if (variants.isNotEmpty) {
      final variant = variants.first;
      if (variant.content != replySnapshot ||
          variant.innerVoice.trim() != expected) {
        return false;
      }
      variants[0] = variant.copyWith(
        innerVoice: previous,
        clearInnerVoice: previous.trim().isEmpty,
      );
      _replaceAt(messageIndex, message.copyWith(variants: variants));
      return true;
    }

    if (message.content != replySnapshot ||
        message.innerVoice.trim() != expected) {
      return false;
    }
    _replaceAt(
      messageIndex,
      message.copyWith(
        innerVoice: previous,
        clearInnerVoice: previous.trim().isEmpty,
      ),
    );
    return true;
  }

  bool selectAssistantVariant(int messageIndex, int variantIndex) {
    if (!_isAssistantIndex(messageIndex)) return false;
    final message = _messages[messageIndex];
    final variants = message.variants
        .where((variant) => variant.content.trim().isNotEmpty)
        .toList();
    if (variantIndex < 0 || variantIndex >= variants.length) return false;
    _replaceAt(
      messageIndex,
      message.copyWith(variants: variants, selectedVariantIndex: variantIndex),
    );
    if (summaryIncludesMessageAt(messageIndex)) {
      _summary = ChatSummary.empty(_summary.characterId, _summary.sessionId);
    }
    return true;
  }

  bool canRegenerateAssistantAt(int messageIndex) =>
      messageIndex == _messages.length - 1 &&
      _isAssistantIndex(messageIndex) &&
      _messages[messageIndex].effectiveContent.trim().isNotEmpty;

  bool hasMessagesAfter(int messageIndex) =>
      messageIndex >= 0 && messageIndex < _messages.length - 1;

  bool summaryIncludesMessageAt(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _messages.length) return false;
    if (_summary.summary.trim().isEmpty ||
        _summary.summarizedMessageCount <= 0 ||
        (!_messages[messageIndex].isUser &&
            !_messages[messageIndex].isAssistant)) {
      return false;
    }
    final chatIndex = _messages
        .take(messageIndex)
        .where((message) => message.isUser || message.isAssistant)
        .length;
    return chatIndex < _summary.summarizedMessageCount;
  }

  bool truncateAfter(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _messages.length - 1) return false;
    final nextMessages = _messages.take(messageIndex + 1).toList();
    final retainedChatCount = nextMessages
        .where((message) => message.isUser || message.isAssistant)
        .length;
    if (_summary.summary.trim().isNotEmpty &&
        retainedChatCount < _summary.summarizedMessageCount) {
      _summary = ChatSummary.empty(_summary.characterId, _summary.sessionId);
    }
    _messages = nextMessages;
    return true;
  }

  void editUserMessageAndTruncate(int index, String content, DateTime time) {
    if (index < 0 || index >= _messages.length || !_messages[index].isUser) {
      return;
    }
    _messages = [
      ..._messages.take(index),
      _messages[index].copyWith(content: content, time: time),
    ];
  }

  bool dropEmptyAssistantTail() {
    if (_messages.isEmpty ||
        !_messages.last.isAssistant ||
        _messages.last.effectiveContent.trim().isNotEmpty) {
      return false;
    }
    _messages = _messages.sublist(0, _messages.length - 1);
    return true;
  }

  ChatMessageDeletion deleteAt(int index) {
    if (index < 0 || index >= _messages.length) {
      return ChatMessageDeletion.ignored;
    }
    final message = _messages[index];
    if (message.isAssistant && message.variantCount > 1) {
      final variants = message.variants
          .where((variant) => variant.content.trim().isNotEmpty)
          .toList();
      final selectedIndex = message.selectedVariantIndex;
      variants.removeAt(selectedIndex);
      final summaryInvalidated = summaryIncludesMessageAt(index);
      if (summaryInvalidated) {
        _summary = ChatSummary.empty(_summary.characterId, _summary.sessionId);
      }
      final nextSelectedIndex = selectedIndex
          .clamp(0, variants.length - 1)
          .toInt();
      _replaceAt(
        index,
        message.copyWith(
          variants: variants,
          selectedVariantIndex: nextSelectedIndex,
        ),
      );
      return summaryInvalidated
          ? ChatMessageDeletion.summaryInvalidated
          : ChatMessageDeletion.removed;
    }
    final nextSummary = chatSummaryAfterMessageDeletion(
      summary: _summary,
      messages: _messages,
      index: index,
    );
    final summaryInvalidated = !identical(nextSummary, _summary);
    _summary = summaryInvalidated
        ? ChatSummary.empty(_summary.characterId, _summary.sessionId)
        : nextSummary;
    _messages = [..._messages]..removeAt(index);
    return summaryInvalidated
        ? ChatMessageDeletion.summaryInvalidated
        : ChatMessageDeletion.removed;
  }

  void clearMessages() => _messages = [];

  bool _isAssistantIndex(int index) =>
      index >= 0 && index < _messages.length && _messages[index].isAssistant;

  void _replaceAt(int index, ChatMessage message) {
    _messages = [..._messages]..[index] = message;
  }
}
