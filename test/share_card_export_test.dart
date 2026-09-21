import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/share_card_service.dart';

void main() {
  test('cancel never reports successful export', () async {
    final r = await saveSharePages(
      pageCount: 2,
      render: (_) async => Uint8List(1),
      save: (_, _) async => null,
    );
    expect(r.status, ShareExportStatus.cancelled);
    expect(r.paths, isEmpty);
  });
  test('second page failure reports only actual first saved path', () async {
    final r = await saveSharePages(
      pageCount: 3,
      render: (_) async => Uint8List(1),
      save: (i, _) async {
        if (i == 1) throw StateError('disk');
        return 'actual.png';
      },
    );
    expect(r.status, ShareExportStatus.partiallySaved);
    expect(r.paths, ['actual.png']);
  });
}
