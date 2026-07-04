import 'ai_provider.dart';

class ApiProviderConfig {
  const ApiProviderConfig({
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
  });

  final String apiKey;
  final String baseUrl;
  final String model;

  bool get isComplete =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  ApiProviderConfig copyWith({String? apiKey, String? baseUrl, String? model}) {
    return ApiProviderConfig(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }

  factory ApiProviderConfig.fromJson(Map<String, dynamic>? json) {
    return ApiProviderConfig(
      apiKey: json?['apiKey'] as String? ?? '',
      baseUrl: json?['baseUrl'] as String? ?? '',
      model: json?['model'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'apiKey': apiKey, 'baseUrl': baseUrl, 'model': model};
  }
}

class ApiConfig {
  ApiConfig({Map<AiProvider, ApiProviderConfig>? providers})
    : providers = {
        for (final provider in AiProvider.values)
          provider: providers?[provider] ?? const ApiProviderConfig(),
      };

  final Map<AiProvider, ApiProviderConfig> providers;

  ApiProviderConfig get(AiProvider provider) {
    return providers[provider] ?? const ApiProviderConfig();
  }

  ApiConfig copyWithProvider(
    AiProvider provider,
    ApiProviderConfig providerConfig,
  ) {
    return ApiConfig(providers: {...providers, provider: providerConfig});
  }

  factory ApiConfig.defaults() {
    return ApiConfig();
  }

  factory ApiConfig.fromJson(Map<String, dynamic>? json) {
    return ApiConfig(
      providers: {
        for (final provider in AiProvider.values)
          provider: ApiProviderConfig.fromJson(
            json?[provider.id] as Map<String, dynamic>?,
          ),
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      for (final provider in AiProvider.values)
        provider.id: get(provider).toJson(),
    };
  }
}
