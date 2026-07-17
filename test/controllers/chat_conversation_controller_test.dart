import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/controllers/chat_conversation_controller.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_summary.dart';

void main() {
  test('owns message and summary transitions without UI state', () {
    final controller = ChatConversationController(characterId: 'character');
    final messages = [
      _message('user', '第一句'),
      _message('assistant', '第一答'),
      _message('system', '系统提示'),
      _message('user', '第二句'),
      _message('assistant', ''),
    ];
    final summary = ChatSummary(
      characterId: 'character',
      summary: '旧总结',
      updatedAt: DateTime(2026),
      summarizedMessageCount: 2,
    );

    controller.load(messages: messages, summary: summary);
    expect(controller.lastUserMessageIndex, 3);
    expect(controller.chatMessagesOnly, hasLength(4));
    expect(controller.dropEmptyAssistantTail(), isTrue);
    expect(controller.messages.last.content, '第二句');

    controller.editUserMessageAndTruncate(0, '改写第一句', DateTime(2026, 2));
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.content, '改写第一句');
  });

  test('deleting summarized chat invalidates its summary', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.load(
      messages: [_message('user', '问题'), _message('assistant', '回答')],
      summary: ChatSummary(
        characterId: 'character',
        summary: '总结',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 2,
      ),
    );

    final result = controller.deleteAt(0);

    expect(result, ChatMessageDeletion.summaryInvalidated);
    expect(controller.summary.summary, isEmpty);
    expect(controller.messages.single.content, '回答');
  });
}

ChatMessage _message(String role, String content) =>
    ChatMessage(role: role, content: content, time: DateTime(2026));
