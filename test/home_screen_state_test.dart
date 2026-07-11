import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home tabs remain mounted in one IndexedStack', () async {
    final source = await File('lib/screens/home_screen.dart').readAsString();
    expect(source, contains('IndexedStack('));
    expect(source, contains('NovelScreen('));
    expect(source, contains('TheaterListScreen('));
    expect(source, contains('SettingsScreen('));
    expect(source, contains('GlobalKey<NovelScreenState>'));
    expect(source, contains('GlobalKey<TheaterListScreenState>'));
  });

  test(
    'novel grid selection is state owned instead of rebuilt locally',
    () async {
      final source = await File('lib/screens/home_screen.dart').readAsString();
      expect(source, contains('var _novelGridView = false;'));
      expect(source, contains('useGridView: _novelGridView'));
    },
  );
}
