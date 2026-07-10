class AiUsage {
  const AiUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.cacheHitTokens = 0,
    this.cacheMissTokens = 0,
    this.hasUsage = false,
    this.supportsCacheStats = false,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int cacheHitTokens;
  final int cacheMissTokens;
  final bool hasUsage;
  final bool supportsCacheStats;

  double get cacheHitRate {
    final total = cacheHitTokens + cacheMissTokens;
    return total == 0 ? 0 : cacheHitTokens / total;
  }

  factory AiUsage.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return const AiUsage();
    int read(String key) {
      final value = json[key];
      return value is num ? value.toInt() : 0;
    }

    final details = json['prompt_tokens_details'];
    final detailMap = details is Map<String, dynamic> ? details : null;
    final detailCached = detailMap?['cached_tokens'];
    final cacheHit = read('prompt_cache_hit_tokens') != 0
        ? read('prompt_cache_hit_tokens')
        : read('cache_read_input_tokens') != 0
        ? read('cache_read_input_tokens')
        : read('cached_tokens') != 0
        ? read('cached_tokens')
        : detailCached is num
        ? detailCached.toInt()
        : 0;
    final explicitMiss = read('prompt_cache_miss_tokens') != 0
        ? read('prompt_cache_miss_tokens')
        : read('cache_creation_input_tokens');
    final supportsCache =
        json.containsKey('prompt_cache_hit_tokens') ||
        json.containsKey('prompt_cache_miss_tokens') ||
        json.containsKey('cache_read_input_tokens') ||
        json.containsKey('cache_creation_input_tokens') ||
        json.containsKey('cached_tokens') ||
        detailMap?.containsKey('cached_tokens') == true;
    final basePrompt = read('prompt_tokens') != 0
        ? read('prompt_tokens')
        : read('input_tokens');
    final anthropicCache =
        read('cache_read_input_tokens') + read('cache_creation_input_tokens');
    final prompt =
        basePrompt + (json.containsKey('prompt_tokens') ? 0 : anthropicCache);
    final completion = read('completion_tokens') != 0
        ? read('completion_tokens')
        : read('output_tokens');
    final miss = explicitMiss != 0
        ? explicitMiss
        : supportsCache && prompt >= cacheHit
        ? prompt - cacheHit
        : 0;
    final total = read('total_tokens');
    return AiUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total == 0 ? prompt + completion : total,
      cacheHitTokens: cacheHit,
      cacheMissTokens: miss,
      hasUsage: json.isNotEmpty,
      supportsCacheStats: supportsCache,
    );
  }

  factory AiUsage.fromStoredJson(dynamic json) {
    if (json is! Map<String, dynamic>) return const AiUsage();
    return AiUsage(
      promptTokens: json['prompt_tokens'] as int? ?? 0,
      completionTokens: json['completion_tokens'] as int? ?? 0,
      totalTokens: json['total_tokens'] as int? ?? 0,
      cacheHitTokens: json['prompt_cache_hit_tokens'] as int? ?? 0,
      cacheMissTokens: json['prompt_cache_miss_tokens'] as int? ?? 0,
      hasUsage: json['hasUsage'] as bool? ?? false,
      supportsCacheStats: json['supportsCacheStats'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
    'prompt_cache_hit_tokens': cacheHitTokens,
    'prompt_cache_miss_tokens': cacheMissTokens,
    'hasUsage': hasUsage,
    'supportsCacheStats': supportsCacheStats,
  };
}

class AiUsageRecord {
  const AiUsageRecord({
    required this.requestType,
    required this.model,
    required this.usage,
    required this.fixedPromptCharacters,
    required this.dynamicMemoryCharacters,
    required this.chatCharacters,
    required this.summaryUpdated,
    required this.createdAt,
  });

  final String requestType;
  final String model;
  final AiUsage usage;
  final int fixedPromptCharacters;
  final int dynamicMemoryCharacters;
  final int chatCharacters;
  final bool summaryUpdated;
  final DateTime createdAt;

  factory AiUsageRecord.fromRequest({
    required String requestType,
    required String model,
    required AiUsage usage,
    required List<Map<String, String>> messages,
    required bool summaryUpdated,
    DateTime? createdAt,
  }) {
    final fixed = messages.isEmpty ? 0 : messages.first['content']?.length ?? 0;
    final hasMemory = messages.length > 1 && messages[1]['role'] == 'system';
    final memory = hasMemory ? messages[1]['content']?.length ?? 0 : 0;
    final chat = messages
        .skip(hasMemory ? 2 : 1)
        .fold<int>(0, (sum, item) => sum + (item['content']?.length ?? 0));
    return AiUsageRecord(
      requestType: requestType,
      model: model,
      usage: usage,
      fixedPromptCharacters: fixed,
      dynamicMemoryCharacters: memory,
      chatCharacters: chat,
      summaryUpdated: summaryUpdated,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  factory AiUsageRecord.fromJson(Map<String, dynamic> json) => AiUsageRecord(
    requestType: json['requestType'] as String? ?? '',
    model: json['model'] as String? ?? '',
    usage: AiUsage.fromStoredJson(json['usage']),
    fixedPromptCharacters: json['fixedPromptCharacters'] as int? ?? 0,
    dynamicMemoryCharacters: json['dynamicMemoryCharacters'] as int? ?? 0,
    chatCharacters: json['chatCharacters'] as int? ?? 0,
    summaryUpdated: json['summaryUpdated'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'requestType': requestType,
    'model': model,
    'usage': usage.toJson(),
    'fixedPromptCharacters': fixedPromptCharacters,
    'dynamicMemoryCharacters': dynamicMemoryCharacters,
    'chatCharacters': chatCharacters,
    'summaryUpdated': summaryUpdated,
    'createdAt': createdAt.toIso8601String(),
  };
}

List<AiUsageRecord> appendAiUsageRecord(
  List<AiUsageRecord> records,
  AiUsageRecord record,
) => [record, ...records].take(100).toList();

enum AiUsageCategory { character, novel, theater }

class AiUsageTotals {
  const AiUsageTotals({
    required this.requestCount,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.cacheHitTokens,
    required this.cacheMissTokens,
    required this.supportsCacheStats,
  });

  final int requestCount;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int cacheHitTokens;
  final int cacheMissTokens;
  final bool supportsCacheStats;

  double get cacheHitRate {
    final total = cacheHitTokens + cacheMissTokens;
    return total == 0 ? 0 : cacheHitTokens / total;
  }
}

List<AiUsageRecord> filterAiUsage(
  List<AiUsageRecord> records,
  AiUsageCategory category,
) => records.where((record) {
  return switch (category) {
    AiUsageCategory.character => record.requestType.startsWith('character'),
    AiUsageCategory.novel => record.requestType.startsWith('novel'),
    AiUsageCategory.theater => record.requestType.startsWith('theater'),
  };
}).toList();

AiUsageTotals summarizeAiUsage(
  List<AiUsageRecord> records,
  AiUsageCategory category,
) {
  final filtered = filterAiUsage(records, category);
  var prompt = 0;
  var completion = 0;
  var total = 0;
  var hit = 0;
  var miss = 0;
  var supportsCache = false;
  for (final record in filtered) {
    final usage = record.usage;
    prompt += usage.promptTokens;
    completion += usage.completionTokens;
    total += usage.totalTokens;
    if (!usage.supportsCacheStats) continue;
    supportsCache = true;
    hit += usage.cacheHitTokens;
    miss += usage.cacheMissTokens;
  }
  return AiUsageTotals(
    requestCount: filtered.length,
    promptTokens: prompt,
    completionTokens: completion,
    totalTokens: total,
    cacheHitTokens: hit,
    cacheMissTokens: miss,
    supportsCacheStats: supportsCache,
  );
}
