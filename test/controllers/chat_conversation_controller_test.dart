import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/controllers/chat_conversation_controller.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
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
  test('deletes only the selected assistant variant while alternatives remain', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.append(
      ChatMessage(
        role: 'assistant',
        content: 'first',
        time: DateTime(2026),
        variants: [
          ChatReplyVariant(content: 'first', time: DateTime(2026)),
          ChatReplyVariant(content: 'second', time: DateTime(2026, 2)),
          ChatReplyVariant(content: 'third', time: DateTime(2026, 3)),
        ],
        selectedVariantIndex: 1,
      ),
    );

    expect(controller.deleteAt(0), ChatMessageDeletion.removed);
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.variantCount, 2);
    expect(
      controller.messages.single.variants.map((variant) => variant.content),
      ['first', 'third'],
    );
    expect(controller.messages.single.effectiveContent, 'third');
  });

  test('deleting the last assistant variant removes the message', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.append(
      ChatMessage(
        role: 'assistant',
        content: 'reply',
        time: DateTime(2026),
        variants: [
          ChatReplyVariant(content: 'reply', time: DateTime(2026)),
        ],
      ),
    );

    expect(controller.deleteAt(0), ChatMessageDeletion.removed);
    expect(controller.messages, isEmpty);
  });

  test('deleting a summarized variant clears the summary but keeps alternatives', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.load(
      messages: [
        ChatMessage(
          role: 'assistant',
          content: 'first',
          time: DateTime(2026),
          variants: [
            ChatReplyVariant(content: 'first', time: DateTime(2026)),
            ChatReplyVariant(content: 'second', time: DateTime(2026, 2)),
          ],
        ),
      ],
      summary: ChatSummary(
        characterId: 'character',
        sessionId: 'session',
        summary: 'summary',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 1,
      ),
    );

    expect(controller.deleteAt(0), ChatMessageDeletion.summaryInvalidated);
    expect(controller.summary.summary, isEmpty);
    expect(controller.messages.single.variantCount, 1);
  });

  test('adds a variant by preserving a legacy assistant reply first', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.append(_message('assistant', 'original reply'));

    final added = controller.addAssistantVariant(
      0,
      ChatReplyVariant(content: 'regenerated reply', time: DateTime(2026, 2)),
    );

    expect(added, isTrue);
    expect(controller.messages.single.variantCount, 2);
    expect(controller.messages.single.variants.first.content, 'original reply');
    expect(controller.messages.single.effectiveContent, 'regenerated reply');
  });

  test('switching a summarized assistant variant clears the summary', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.load(
      messages: [
        _message('user', 'question'),
        ChatMessage(
          role: 'assistant',
          content: 'first reply',
          time: DateTime(2026),
          variants: [
            ChatReplyVariant(content: 'first reply', time: DateTime(2026)),
            ChatReplyVariant(content: 'second reply', time: DateTime(2026, 2)),
          ],
        ),
        _message('user', 'follow up'),
      ],
      summary: ChatSummary(
        characterId: 'character',
        sessionId: 'session',
        summary: 'summary',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 2,
      ),
    );

    expect(controller.selectAssistantVariant(1, 1), isTrue);
    expect(controller.messages[1].effectiveContent, 'second reply');
    expect(controller.summary.summary, isEmpty);
    expect(controller.summary.sessionId, 'session');
  });

  test('truncating after a message clears a summary that it removes', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.load(
      messages: [
        _message('user', 'first'),
        _message('assistant', 'reply'),
        _message('user', 'later'),
      ],
      summary: ChatSummary(
        characterId: 'character',
        sessionId: 'session',
        summary: 'summary',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 3,
      ),
    );

    expect(controller.canRegenerateAssistantAt(1), isFalse);
    expect(controller.truncateAfter(1), isTrue);
    expect(controller.messages, hasLength(2));
    expect(controller.summary.summary, isEmpty);
    expect(controller.summary.sessionId, 'session');
    expect(controller.canRegenerateAssistantAt(1), isTrue);
  });

  test('keeps an assistant tail with a selected reply variant', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.append(
      ChatMessage(
        role: 'assistant',
        content: '',
        time: DateTime(2026),
        variants: [
          ChatReplyVariant(content: 'saved reply', time: DateTime(2026)),
        ],
      ),
    );

    expect(controller.dropEmptyAssistantTail(), isFalse);
    expect(controller.messages, hasLength(1));
  });

  test('deleting a summarized message preserves its summary session', () {
    final controller = ChatConversationController(characterId: 'character');
    controller.load(
      messages: [_message('user', 'question')],
      summary: ChatSummary(
        characterId: 'character',
        sessionId: 'session',
        summary: 'summary',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 1,
      ),
    );

    controller.deleteAt(0);

    expect(controller.summary.summary, isEmpty);
    expect(controller.summary.sessionId, 'session');
  });
}

ChatMessage _message(String role, String content) =>
    ChatMessage(role: role, content: content, time: DateTime(2026));
