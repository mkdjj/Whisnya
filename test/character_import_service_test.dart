import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/utils/character_import_flow.dart';

void main() {
  test('imported characters do not assume a built-in API endpoint', () async {
    final storage = _ImportStorage();
    final result = await CharacterImportService(storage).importSources([
      CharacterImportSource(
        name: 'role.json',
        bytes: Uint8List.fromList(
          utf8.encode('{"name":"Imported","description":"Description"}'),
        ),
      ),
    ]);

    expect(result.failures, isEmpty);
    expect(result.imported.single.defaultEndpointId, isEmpty);
    expect(storage.saved.single.defaultEndpointId, isEmpty);
  });
}

final class _ImportStorage extends LocalStorageService {
  final saved = <AppCharacter>[];

  @override
  Future<List<AppCharacter>> loadCharacters() async => const [];

  @override
  Future<void> saveCharacter(AppCharacter character) async {
    saved.add(character);
  }
}
