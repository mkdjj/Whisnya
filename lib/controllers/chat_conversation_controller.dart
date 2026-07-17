import '../models/chat_message.dart';
import '../models/chat_summary.dart';
import '../services/chat/chat_summary_service.dart';

enum ChatMessageDeletion { ignored, removed, summaryInvalidated }

final class ChatConversationController {
  ChatConversationController({required String characterId})
    : _summary = ChatSummary.empty(characterId);

  var _messages = <ChatMessage>[];
  ChatSummary _summary;

  List<ChatMessage> get messages => _messages;
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
    _messages = [...messages];
  }

  void setSummary(ChatSummary summary) => _summary = summary;

  void append(ChatMessage message) => _messages = [..._messages, message];

  void replaceLast(ChatMessage message) {
    if (_messages.isEmpty) return;
    _messages = [..._messages.take(_messages.length - 1), message];
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
        _messages.last.content.trim().isNotEmpty) {
      return false;
    }
    _messages = _messages.sublist(0, _messages.length - 1);
    return true;
  }

  ChatMessageDeletion deleteAt(int index) {
    if (index < 0 || index >= _messages.length) {
      return ChatMessageDeletion.ignored;
    }
    final nextSummary = chatSummaryAfterMessageDeletion(
      summary: _summary,
      messages: _messages,
      index: index,
    );
    final summaryInvalidated = !identical(nextSummary, _summary);
    _summary = nextSummary;
    _messages = [..._messages]..removeAt(index);
    return summaryInvalidated
        ? ChatMessageDeletion.summaryInvalidated
        : ChatMessageDeletion.removed;
  }

  void clearMessages() => _messages = [];
}
