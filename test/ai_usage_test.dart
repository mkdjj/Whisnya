import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/ai_usage.dart';

void main() {
  test('parses OpenAI and Anthropic cache usage fields', () {
    final openAi = AiUsage.fromJson({
      'prompt_tokens': 100,
      'completion_tokens': 20,
      'total_tokens': 120,
      'prompt_tokens_details': {'cached_tokens': 80},
    });
    final anthropic = AiUsage.fromJson({
      'input_tokens': 30,
      'output_tokens': 10,
      'cache_read_input_tokens': 60,
      'cache_creation_input_tokens': 10,
    });

    expect(openAi.promptTokens, 100);
    expect(openAi.cacheHitTokens, 80);
    expect(openAi.cacheMissTokens, 20);
    expect(openAi.cacheHitRate, 0.8);
    expect(openAi.supportsCacheStats, isTrue);
    expect(anthropic.cacheHitTokens, 60);
    expect(anthropic.cacheMissTokens, 10);
    expect(anthropic.promptTokens, 100);
    expect(anthropic.totalTokens, 110);
  });

  test('round trips usage records with prompt layer sizes', () {
    final record = AiUsageRecord.fromRequest(
      requestType: '角色聊天',
      model: 'model',
      usage: AiUsage.fromJson({
        'prompt_tokens': 12,
        'completion_tokens': 3,
        'total_tokens': 15,
      }),
      messages: const [
        {'role': 'system', 'content': 'fixed'},
        {'role': 'system', 'content': 'memory'},
        {'role': 'user', 'content': 'chat'},
      ],
      summaryUpdated: true,
      createdAt: DateTime(2026),
    );
    final restored = AiUsageRecord.fromJson(record.toJson());

    expect(restored.fixedPromptCharacters, 5);
    expect(restored.dynamicMemoryCharacters, 6);
    expect(restored.chatCharacters, 4);
    expect(restored.summaryUpdated, isTrue);
    expect(restored.usage.supportsCacheStats, isFalse);
  });

  test('keeps only the newest one hundred usage records', () {
    AiUsageRecord record(int index) => AiUsageRecord(
      requestType: 'chat',
      model: '$index',
      usage: const AiUsage(),
      fixedPromptCharacters: 0,
      dynamicMemoryCharacters: 0,
      chatCharacters: 0,
      summaryUpdated: false,
      createdAt: DateTime(2026),
    );

    final records = appendAiUsageRecord([
      for (var i = 0; i < 100; i++) record(i),
    ], record(100));

    expect(records, hasLength(100));
    expect(records.first.model, '100');
    expect(records.last.model, '98');
  });

  test('ignores malformed optional usage fields', () {
    final usage = AiUsage.fromJson({
      'prompt_tokens': '100',
      'prompt_tokens_details': {'cached_tokens': '80'},
    });

    expect(usage.promptTokens, 0);
    expect(usage.cacheHitTokens, 0);
  });

  test('summarizes usage by chat category', () {
    AiUsageRecord record(String type, AiUsage usage) => AiUsageRecord(
      requestType: type,
      model: 'model',
      usage: usage,
      fixedPromptCharacters: 0,
      dynamicMemoryCharacters: 0,
      chatCharacters: 0,
      summaryUpdated: false,
      createdAt: DateTime(2026),
    );
    final records = [
      record(
        'characterChat',
        AiUsage.fromJson({
          'prompt_tokens': 100,
          'completion_tokens': 20,
          'total_tokens': 120,
          'prompt_cache_hit_tokens': 80,
          'prompt_cache_miss_tokens': 20,
        }),
      ),
      record(
        'characterSummary',
        AiUsage.fromJson({
          'prompt_tokens': 50,
          'completion_tokens': 10,
          'total_tokens': 60,
          'prompt_cache_hit_tokens': 0,
          'prompt_cache_miss_tokens': 50,
        }),
      ),
      record(
        'novelChat',
        AiUsage.fromJson({
          'prompt_tokens': 500,
          'completion_tokens': 50,
          'total_tokens': 550,
        }),
      ),
    ];

    final totals = summarizeAiUsage(records, AiUsageCategory.character);

    expect(totals.requestCount, 2);
    expect(totals.promptTokens, 150);
    expect(totals.completionTokens, 30);
    expect(totals.totalTokens, 180);
    expect(totals.cacheHitTokens, 80);
    expect(totals.cacheMissTokens, 70);
    expect(totals.cacheHitRate, closeTo(80 / 150, 0.0001));
  });
}
