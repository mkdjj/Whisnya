import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports the first endpoint usability error', () {
    final now = DateTime(2026);
    final endpoint = AiEndpointConfig(
      id: 'endpoint',
      name: 'Endpoint',
      apiKey: 'key',
      baseUrl: 'https://example.test/v1',
      model: 'model',
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );

    expect(endpoint.validationError, isNull);
    expect(endpoint.copyWith(enabled: false).validationError, '当前 API 配置已禁用。');
    expect(endpoint.copyWith(apiKey: ' ').validationError, 'API Key 为空，请先配置。');
    expect(
      endpoint.copyWith(baseUrl: ' ').validationError,
      'Base URL 为空，请先配置。',
    );
    expect(endpoint.copyWith(model: ' ').validationError, 'Model 为空，请先配置。');
  });

  test('replaces deleted or disabled default with first enabled endpoint', () {
    final now = DateTime(2026);
    final a = AiEndpointConfig(
      id: 'a',
      name: 'A',
      apiKey: 'key',
      baseUrl: 'https://a.test/v1',
      model: 'a',
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );
    final b = a.copyWith(id: 'b', name: 'B');

    final config = ApiConfig(endpoints: [a, b], defaultEndpointId: 'b');

    expect(config.removeEndpoint('b').defaultEndpointId, 'a');
    expect(
      config.upsertEndpoint(b.copyWith(enabled: false)).defaultEndpointId,
      'a',
    );
  });

  test('redacts api keys from exported backup config', () {
    final original = {
      'endpoints': [
        {'id': 'a', 'apiKey': 'secret', 'baseUrl': 'https://a.test'},
      ],
    };

    final redacted = redactApiKeysForExport(original);

    final redactedEndpoint =
        (redacted['endpoints'] as List<dynamic>).single as Map<String, dynamic>;
    expect(redactedEndpoint['apiKey'], isEmpty);
    final originalEndpoint =
        (original['endpoints'] as List<Map<String, String>>).single;
    expect(originalEndpoint['apiKey'], 'secret');
  });
}
