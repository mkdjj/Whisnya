import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/prompts/prompt_builder.dart';
import 'package:whisnya/services/ai/ai_conversation_runner.dart';

void main() {
  test('chat and summary context use only selected formal content', () {
    final message = ChatMessage.fromJson({
      'role': 'assistant',
      'content': 'old reply',
      'reasoningContent': 'secret reasoning',
      'innerVoice': 'secret voice',
      'variants': [
        {
          'content': 'selected reply',
          'reasoningContent': 'candidate reasoning',
          'innerVoice': 'candidate voice',
        },
      ],
    });
    final chat = PromptBuilder.buildChatRequestMessages(
      character: AppCharacter.fromJson({'id': 'c', 'name': 'name'}),
      historySummary: '',
      summarizedMessageCount: 0,
      messages: [message],
      useFullContext: true,
    );
    expect(chat.last['content'], 'selected reply');
    final summary = PromptBuilder.buildRollingSummaryPrompt(
      previousSummary: '',
      newMessages: [message],
      useCustomItems: false,
      customItems: const [],
    );
    expect(summary, contains('selected reply'));
    expect(summary, isNot(contains('reasoning')));
    expect(summary, isNot(contains('voice')));
    final copy = message.copyWith(
      reasoningContent: 'replacement',
      replyState: 'interrupted',
    );
    expect(copy.reasoningContent, 'replacement');
    expect(copy.effectiveReasoningContent, 'candidate reasoning');
    expect(copy.effectiveReplyState, 'completed');
    final variant = message.selectedVariant!.copyWith(content: 'edited');
    expect(variant.reasoningContent, 'candidate reasoning');
    expect(variant.innerVoice, 'candidate voice');
  });
  test(
    'service structured and text APIs preserve separation and report usage once',
    () async {
      final service = AiService(
        client: MockClient((request) async {
          if (request.body.contains('"stream":true')) {
            return http.Response(
              'data: {"choices":[{"delta":{"content":"hello","reasoning_content":"thought"}}]}\n\n'
              'data: {"choices":[],"usage":{"total_tokens":5}}\n\n'
              'data: {"choices":[],"usage":{"total_tokens":8}}\n\n'
              'data: [DONE]\n\n',
              200,
            );
          }
          return http.Response(
            '{"choices":[{"message":{"content":"hello","reasoning_content":"thought"}}],"usage":{"total_tokens":8}}',
            200,
          );
        }),
      );
      const request = AiRequest(
        apiKey: 'key',
        baseUrl: 'https://example.com',
        model: 'm',
        messages: [],
      );
      final response = await service.sendResponse(request);
      expect(response.content, 'hello');
      expect(response.reasoningContent, 'thought');
      final events = await service.streamResponse(request).toList();
      expect(events.map((e) => e.contentDelta).join(), 'hello');
      expect(events.map((e) => e.reasoningDelta).join(), 'thought');
      expect(events.where((e) => e.usage != null).single.usage?.totalTokens, 8);
      final usages = <AiUsage>[];
      expect(
        await service
            .streamMessage(
              apiKey: 'key',
              baseUrl: 'https://example.com',
              model: 'm',
              messages: [],
              includeReasoning: true,
              onUsage: usages.add,
            )
            .join(),
        'hello',
      );
      expect(usages.single.totalTokens, 8);
    },
  );
  test(
    'JSON round trip preserves selected reasoning and interruption state',
    () {
      final message = ChatMessage.fromJson({
        'role': 'assistant',
        'content': 'old',
        'reasoningContent': 'old thought',
        'innerVoice': 'old voice',
        'replyState': 'interrupted',
        'variants': [
          {
            'content': 'A',
            'reasoningContent': 'thought A',
            'innerVoice': 'voice A',
          },
          {
            'content': 'B',
            'reasoningContent': '',
            'innerVoice': 'voice B',
            'replyState': 'interrupted',
          },
        ],
        'selectedVariantIndex': 1,
      });
      final json = message.toJson();
      expect(json['content'], 'B');
      expect(json['reasoningContent'], '');
      expect(json['innerVoice'], 'voice B');
      expect(json['replyState'], 'interrupted');
      final variants = (json['variants'] as List).cast<Map<String, dynamic>>();
      expect(variants[0]['reasoningContent'], 'thought A');
      expect(ChatMessage.fromJson(json).toJson()['replyState'], 'interrupted');
    },
  );

  test('legacy JSON defaults completed without inventing reasoning', () {
    final json = ChatMessage.fromJson({'content': '分析：保留旧原文'}).toJson();
    expect(json['content'], '分析：保留旧原文');
    expect(json['reasoningContent'], '');
    expect(json['replyState'], 'completed');
  });

  test('reasoning-only candidates cannot become selected replies', () {
    final message = ChatMessage.fromJson({
      'content': 'original',
      'variants': [
        {'content': '', 'reasoningContent': 'thought'},
      ],
    });
    expect(message.variantCount, 0);
    expect(message.effectiveContent, 'original');
  });

  test('legacy stream parser never returns reasoning as reply text', () {
    const adapter = OpenAiCompatibleAdapter();
    expect(
      adapter.parseStream(
        'data: {"choices":[{"delta":{"reasoning_content":"thought"}}]}',
        includeReasoning: true,
      ),
      isNull,
    );
  });

  test('structured events retain both fields and usage without choices', () {
    const adapter = OpenAiCompatibleAdapter();
    final event = adapter.parseResponseDelta(
      'data: {"choices":[{"delta":{"content":"你好","reasoning_content":"说明"}}]}',
    );
    expect(event?.contentDelta, '你好');
    expect(event?.reasoningDelta, '说明');
    expect(
      adapter
          .parseResponseDelta('data: {"choices":[],"usage":{"total_tokens":4}}')
          ?.usage
          ?.totalTokens,
      4,
    );
    expect(adapter.parseResponseDelta('data: {"choices":[]}'), isNull);
    expect(adapter.parseResponseDelta('data: [DONE]'), isNull);
    expect(
      adapter
          .parseResponseDelta(
            'data: {"choices":[{"delta":{"reasoning_content":"思考"}}]}',
          )
          ?.reasoningDelta,
      '思考',
    );
    final response = adapter.parseStructuredResponse({
      'choices': [
        {
          'message': {'content': '你好', 'reasoning_content': '说明'},
        },
      ],
    });
    expect(response.content, '你好');
    expect(response.reasoningContent, '说明');
    expect(
      () => adapter.parseStructuredResponse({
        'choices': [
          {
            'message': {'reasoning_content': '说明'},
          },
        ],
      }),
      throwsA(isA<AiException>()),
    );
  });
}
