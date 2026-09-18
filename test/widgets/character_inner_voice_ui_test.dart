import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
import 'package:whisnya/screens/chat/character_inner_voice_history_screen.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/chat/character_inner_voice_dialog.dart';
import 'package:whisnya/widgets/chat/character_inner_voice_preview.dart';

void main() {
  testWidgets('preview exposes two-line content and runtime states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: Column(
            children: [
              CharacterInnerVoicePreview(innerVoice: '藏在心里的话'),
              CharacterInnerVoicePreview(isGenerating: true),
              CharacterInnerVoicePreview(isFailed: true),
            ],
          ),
        ),
      ),
    );

    final content = tester.widget<Text>(find.textContaining('藏在心里的话'));
    expect(content.maxLines, 2);
    expect(content.overflow, TextOverflow.ellipsis);
    expect(find.text('心声生成中…'), findsOneWidget);
    expect(find.text('心声生成失败'), findsOneWidget);
  });

  testWidgets('dialog shows full selectable voice and opens session history', (
    tester,
  ) async {
    var messages = _messages();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCharacterInnerVoiceDialog(
              context: context,
              character: _character,
              innerVoice: '完整的此刻心声',
              messagesProvider: () => messages,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('角色心声'), findsOneWidget);
    expect(find.text('此刻心声'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('完整的此刻心声'), findsOneWidget);

    messages = [
      ...messages,
      ChatMessage(
        role: 'assistant',
        content: '刚生成的回复',
        innerVoice: '刚生成的心声',
        time: DateTime(2026, 8, 11),
      ),
    ];

    await tester.tap(find.text('查看历史心声'));
    await tester.pumpAndSettle();
    expect(find.text('历史心声'), findsOneWidget);
    expect(find.textContaining('刚生成的心声'), findsOneWidget);
    expect(find.textContaining('候选 B 心声'), findsOneWidget);
    expect(find.textContaining('旧心声'), findsOneWidget);
    expect(find.textContaining('候选 A 心声'), findsNothing);
    expect(find.textContaining('用户不该出现'), findsNothing);
    expect(
      tester.getTopLeft(find.textContaining('候选 B 心声')).dy,
      lessThan(tester.getTopLeft(find.textContaining('旧心声')).dy),
    );
  });

  testWidgets('history has a localized empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: CharacterInnerVoiceHistoryScreen(
          character: _character,
          messages: [],
        ),
      ),
    );

    expect(find.text('还没有角色心声'), findsOneWidget);
    expect(find.text('开启“显示角色心声”后，新生成的角色回复会记录在这里'), findsOneWidget);
  });
}

final _character = AppCharacter(
  id: 'character-1',
  name: '谢青云',
  avatar: '',
  backgroundImage: '',
  backgroundImageOpacity: 1,
  backgroundBlur: 0,
  inputOpacity: 1,
  description: '',
  personality: '',
  background: '',
  speakingStyle: '',
  openingMessage: '',
  extraPrompt: '',
  createdAt: DateTime(2026, 8, 10),
  updatedAt: DateTime(2026, 8, 10),
  lastUsedAt: DateTime(2026, 8, 10),
);

List<ChatMessage> _messages() => [
  ChatMessage(
    role: 'assistant',
    content: '旧回复',
    innerVoice: '旧心声',
    time: DateTime(2026, 8, 9),
  ),
  ChatMessage(
    role: 'user',
    content: '用户消息',
    innerVoice: '用户不该出现',
    time: DateTime(2026, 8, 10),
  ),
  ChatMessage(
    role: 'assistant',
    content: 'legacy',
    innerVoice: 'legacy voice',
    time: DateTime(2026, 8, 10),
    variants: [
      ChatReplyVariant(
        content: '候选 A',
        innerVoice: '候选 A 心声',
        time: DateTime(2026, 8, 10, 22),
      ),
      ChatReplyVariant(
        content: '候选 B',
        innerVoice: '候选 B 心声',
        time: DateTime(2026, 8, 10, 23),
      ),
    ],
    selectedVariantIndex: 1,
  ),
];
