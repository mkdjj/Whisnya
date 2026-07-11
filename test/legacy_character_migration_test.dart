import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';

void main() {
  test('migrates legacy deepseek provider to its endpoint id', () {
    expect(
      AppCharacter.fromJson({
        'id': 'c',
        'defaultProvider': 'deepseek',
      }).defaultEndpointId,
      'deepseek',
    );
  });

  test('migrates legacy grok provider to its endpoint id', () {
    expect(
      AppCharacter.fromJson({
        'id': 'c',
        'defaultProvider': 'grok',
      }).defaultEndpointId,
      'grok',
    );
  });

  test('dynamic endpoint takes precedence over legacy provider', () {
    expect(
      AppCharacter.fromJson({
        'id': 'c',
        'defaultProvider': 'grok',
        'defaultEndpointId': 'custom',
      }).defaultEndpointId,
      'custom',
    );
  });

  test('custom endpoint id is preserved without enum mapping', () {
    const id = 'private-openai-compatible-node';
    expect(
      AppCharacter.fromJson({
        'id': 'c',
        'defaultEndpointId': id,
      }).defaultEndpointId,
      id,
    );
  });

  test('new JSON round trip writes only the dynamic endpoint field', () {
    final original = AppCharacter.fromJson({
      'id': 'c',
      'name': '角色',
      'defaultProvider': 'deepseek',
    });
    final json = original.toJson();
    final restored = AppCharacter.fromJson(json);

    expect(json, isNot(contains('defaultProvider')));
    expect(json['defaultEndpointId'], 'deepseek');
    expect(restored.defaultEndpointId, original.defaultEndpointId);
  });
}
