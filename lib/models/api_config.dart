String? endpointValidationError(AiEndpointConfig? endpoint) =>
    endpoint == null ? '请先到 API 设置添加配置。' : endpoint.validationError;

class AiEndpointConfig {
  const AiEndpointConfig({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String apiKey;
  final String baseUrl;
  final String model;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isComplete =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  String? get validationError {
    if (!enabled) return '当前 API 配置已禁用。';
    if (apiKey.trim().isEmpty) return 'API Key 为空，请先配置。';
    if (baseUrl.trim().isEmpty) return 'Base URL 为空，请先配置。';
    if (model.trim().isEmpty) return 'Model 为空，请先配置。';
    return null;
  }

  AiEndpointConfig copyWith({
    String? id,
    String? name,
    String? apiKey,
    String? baseUrl,
    String? model,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AiEndpointConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AiEndpointConfig.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return AiEndpointConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class ApiConfig {
  ApiConfig({
    List<AiEndpointConfig> endpoints = const [],
    String defaultEndpointId = '',
  }) : endpoints = _uniqueEndpoints(endpoints),
       defaultEndpointId = _normalizedDefaultEndpointId(
         _uniqueEndpoints(endpoints),
         defaultEndpointId,
       );

  final List<AiEndpointConfig> endpoints;
  final String defaultEndpointId;

  List<AiEndpointConfig> get enabledEndpoints =>
      endpoints.where((endpoint) => endpoint.enabled).toList();

  AiEndpointConfig? endpointById(String id) =>
      endpoints.where((endpoint) => endpoint.id == id).firstOrNull;

  AiEndpointConfig? effectiveEndpoint(String id) {
    final selected = endpointById(id);
    if (selected != null && selected.enabled) return selected;
    if (defaultEndpointId.isNotEmpty) {
      final endpoint = endpointById(defaultEndpointId);
      if (endpoint != null && endpoint.enabled) return endpoint;
    }
    return endpoints.where((endpoint) => endpoint.enabled).firstOrNull;
  }

  ApiConfig copyWith({
    List<AiEndpointConfig>? endpoints,
    String? defaultEndpointId,
  }) {
    return ApiConfig(
      endpoints: endpoints ?? this.endpoints,
      defaultEndpointId: defaultEndpointId ?? this.defaultEndpointId,
    );
  }

  ApiConfig upsertEndpoint(AiEndpointConfig endpoint) {
    final index = endpoints.indexWhere((item) => item.id == endpoint.id);
    final next = [...endpoints];
    if (index == -1) {
      next.add(endpoint);
    } else {
      next[index] = endpoint;
    }
    return ApiConfig(endpoints: next, defaultEndpointId: defaultEndpointId);
  }

  ApiConfig removeEndpoint(String id) {
    return ApiConfig(
      endpoints: endpoints.where((endpoint) => endpoint.id != id).toList(),
      defaultEndpointId: defaultEndpointId == id ? '' : defaultEndpointId,
    );
  }

  factory ApiConfig.fromJson(Map<String, dynamic>? json) {
    final rawEndpoints = json?['endpoints'];
    return ApiConfig(
      endpoints: rawEndpoints is List
          ? rawEndpoints
                .whereType<Map<String, dynamic>>()
                .map(AiEndpointConfig.fromJson)
                .toList()
          : const [],
      defaultEndpointId: json?['defaultEndpointId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
      'defaultEndpointId': defaultEndpointId,
    };
  }

  static List<AiEndpointConfig> _uniqueEndpoints(
    List<AiEndpointConfig> endpoints,
  ) {
    final seen = <String>{};
    return [
      for (final endpoint in endpoints)
        if (endpoint.id.trim().isNotEmpty && seen.add(endpoint.id)) endpoint,
    ];
  }

  static String _normalizedDefaultEndpointId(
    List<AiEndpointConfig> endpoints,
    String requested,
  ) {
    for (final endpoint in endpoints) {
      if (endpoint.id == requested && endpoint.enabled) return endpoint.id;
    }
    for (final endpoint in endpoints) {
      if (endpoint.enabled) return endpoint.id;
    }
    return '';
  }
}
