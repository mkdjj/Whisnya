import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/l10n/app_localizations.dart';

void main() {
  test('common Chinese and English copy comes from ARB resources', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(zh.save, '保存');
    expect(en.save, 'Save');
    expect(zh.retry, '重试');
    expect(en.retry, 'Retry');
  });

  test(
    'one-placeholder copy is localized without punctuation matching',
    () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(zh.chatCount(3), '3 条聊天');
      expect(en.chatCount(3), '3 chats');
      expect(en.apiHttpError(429), 'API HTTP error: 429');
    },
  );

  test('two-placeholder copy is localized independently', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(zh.summarizingProgress(2, 5), '正在总结 2/5');
    expect(en.summarizingProgress(2, 5), 'Summarizing 2/5');
    expect(en.importResult(4, 1), 'Imported 4; 1 failed');
  });
}
