import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/app_settings.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_reply_variant.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/character_memory_entry.dart';
import 'package:whisnya/models/world_book.dart';
import 'package:whisnya/screens/chat/chat_screen.dart';
import 'package:whisnya/screens/chat/chat_session_list_screen.dart';
import 'package:whisnya/screens/chat/memory_edit_screen.dart';
import 'package:whisnya/screens/chat/memory_manager_screen.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/storage/session_operation_coordinator.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/widgets/message_bubble_parts.dart';
import 'package:whisnya/widgets/chat_bubble.dart';

void main() {
  testWidgets('network failure flushes and persists the interrupted reply', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);
    await _send(tester, 'question');
    await _pumpUntil(tester, () => gateway.callCount == 1);
    gateway.controllers.single.add('first');
    gateway.controllers.single.add(' second');
    gateway.controllers.single.addError(StateError('network disconnected'));
    await gateway.controllers.single.close();
    await tester.pumpAndSettle();
    expect(storage.chats['session']!.last.content, 'first second');
    expect(storage.chats['session']!.last.replyState, 'interrupted');
    expect(find.text('回复中断'), findsOneWidget);
  });

  testWidgets(
    'completed reply with storage error has retry without duplication',
    (tester) async {
      final character = _character();
      final storage = _SessionStorage(
        character: character,
        sessions: [_session(openingMessageInitialized: true)],
      );
      final gateway = _ControlledGateway();
      addTearDown(gateway.close);
      await _pumpChat(tester, storage, character, gateway: gateway);
      await _send(tester, 'question');
      await _pumpUntil(tester, () => gateway.callCount == 1);
      storage.safeSaveError = StateError('disk full');
      gateway.controllers.single.add('completed reply');
      await gateway.controllers.single.close();
      await tester.pumpAndSettle();
      expect(find.textContaining('未保存'), findsWidgets);
      expect(find.text('completed reply'), findsOneWidget);
      storage.safeSaveError = null;
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(storage.chats['session'], hasLength(2));
      expect(storage.chats['session']!.last.replyState, 'completed');
    },
  );

  testWidgets('inner voice off makes no extra AI request', (tester) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '你好');
    await _pumpUntil(tester, () => storage.chats['session']!.length == 2);

    expect(gateway.voiceCallCount, 0);
    expect(find.text('心声生成中…'), findsNothing);
  });

  testWidgets('main reply is saved before inner voice and success updates it', (
    tester,
  ) async {
    final character = _character();
    const settings = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      settings: settings,
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: settings,
    );

    await _send(tester, '你好');
    await _pumpUntil(tester, () => gateway.voiceCallCount == 1);

    expect(storage.chats['session']!.last.effectiveContent, '主回复');
    expect(storage.chats['session']!.last.effectiveInnerVoice, isEmpty);
    expect(find.text('心声生成中…'), findsOneWidget);
    expect(gateway.voiceModels.single, 'model');
    expect(
      gateway.voiceMessages.single.map((item) => item['content']).join('\n'),
      isNot(contains('reasoning_content')),
    );

    gateway.completeVoice('角色心声：其实我很开心。');
    await _pumpUntil(
      tester,
      () => storage.chats['session']!.last.effectiveInnerVoice == '其实我很开心。',
    );

    expect(find.textContaining('其实我很开心。'), findsOneWidget);
    expect(storage.usageTypes, contains('characterInnerVoice'));
  });

  testWidgets('inner voice failure preserves the completed reply', (
    tester,
  ) async {
    final character = _character();
    const settings = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      settings: settings,
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: settings,
    );

    await _send(tester, '你好');
    await _pumpUntil(tester, () => gateway.voiceCallCount == 1);
    gateway.failVoice(StateError('network'));
    await _pumpUntil(tester, () => find.text('心声生成失败').evaluate().isNotEmpty);

    expect(storage.chats['session']!.last.effectiveContent, '主回复');
    expect(storage.chats['session']!.last.effectiveInnerVoice, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('心声生成失败'), findsNothing);
  });

  testWidgets(
    'inner voice settings load failure stays inside background task',
    (tester) async {
      final character = _character();
      const settings = AppSettings(showCharacterInnerVoice: true);
      final storage = _SessionStorage(
        character: character,
        sessions: [_session(openingMessageInitialized: true)],
        settings: settings,
      )..settingsLoadFailures.add(2);
      final gateway = _InnerVoiceGateway();
      await _pumpChat(
        tester,
        storage,
        character,
        gateway: gateway,
        settings: settings,
      );

      await _send(tester, '你好');
      await _pumpUntil(tester, () => storage.chats['session']!.length == 2);
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(gateway.voiceCallCount, 0);
      expect(storage.chats['session']!.last.effectiveContent, '主回复');
    },
  );

  testWidgets('failed inner voice persistence rolls back the in-memory value', (
    tester,
  ) async {
    final character = _character();
    const enabled = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      settings: enabled,
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: enabled,
    );

    await _send(tester, '你好');
    await _pumpUntil(tester, () => gateway.voiceCallCount == 1);
    storage.safeSaveError = StateError('心声保存失败');
    gateway.completeVoice('不应留在内存');
    await _pumpUntil(tester, () => find.text('心声生成失败').evaluate().isNotEmpty);

    storage.safeSaveError = null;
    storage.settings = const AppSettings();
    await _pumpChat(tester, storage, character, settings: storage.settings);
    storage.settings = enabled;
    await _pumpChat(tester, storage, character, settings: enabled);

    expect(find.textContaining('不应留在内存'), findsNothing);
    expect(storage.chats['session']!.last.effectiveInnerVoice, isEmpty);
  });

  testWidgets('deleting while inner voice saves cannot resurrect the reply', (
    tester,
  ) async {
    final character = _character();
    const settings = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      settings: settings,
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: settings,
    );

    await _send(tester, '你好');
    await _pumpUntil(tester, () => gateway.voiceCallCount == 1);
    storage.safeSaveGate = Completer<void>();
    final safeSavesBeforeVoice = storage.safeSaveCallCount;
    gateway.completeVoice('晚到的心声');
    await _pumpUntil(
      tester,
      () => storage.safeSaveCallCount > safeSavesBeforeVoice,
    );

    final replyBubble = find.ancestor(
      of: find.text('主回复'),
      matching: find.byType(ChatBubble),
    );
    await tester.tap(
      find.descendant(of: replyBubble, matching: find.byTooltip('删除消息')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pump();

    storage.safeSaveGate!.complete();
    await tester.pumpAndSettle();

    expect(storage.chats['session'], hasLength(1));
    expect(storage.chats['session']!.single.role, 'user');
  });

  testWidgets('turning off latest setting discards a late inner voice', (
    tester,
  ) async {
    final character = _character();
    const enabled = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      settings: enabled,
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: enabled,
    );

    await _send(tester, '你好');
    await _pumpUntil(tester, () => gateway.voiceCallCount == 1);
    storage.settings = const AppSettings();
    gateway.completeVoice('不应写入');
    await tester.pump(const Duration(milliseconds: 100));

    expect(storage.chats['session']!.last.effectiveInnerVoice, isEmpty);
    expect(find.textContaining('不应写入'), findsNothing);
  });

  testWidgets('late inner voice from session A cannot enter session B', (
    tester,
  ) async {
    final character = _character();
    const settings = AppSettings(showCharacterInnerVoice: true);
    final sessionA = _session(
      id: 'session-a',
      title: '对话 A',
      openingMessageInitialized: true,
    );
    final sessionB = _session(
      id: 'session-b',
      title: '对话 B',
      openingMessageInitialized: true,
    );
    final storage = _SessionStorage(
      character: character,
      sessions: [sessionA, sessionB],
      settings: settings,
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      session: sessionA,
      settings: settings,
    );

    await _send(tester, 'A 的问题');
    await _pumpUntil(tester, () => gateway.voiceCallCount == 1);
    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('对话 B'));
    await tester.pumpAndSettle();
    gateway.completeVoice('A 的晚到心声');
    await tester.pump(const Duration(milliseconds: 100));

    expect(storage.chats['session-a']!.last.effectiveInnerVoice, isEmpty);
    expect(storage.chats['session-b'], isEmpty);
    expect(find.textContaining('A 的晚到心声'), findsNothing);
  });

  testWidgets('regenerated candidate owns its generated inner voice', (
    tester,
  ) async {
    final character = _character();
    const settings = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [_message('user', '问题'), _message('assistant', '候选 A')],
      settings: settings,
    );
    final gateway = _InnerVoiceGateway(mainReply: '候选 B');
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: settings,
    );

    await tester.tap(find.text('重新生成'));
    await _pumpUntil(tester, () => gateway.voiceCallCount == 1);
    gateway.completeVoice('候选 B 心声');
    await _pumpUntil(
      tester,
      () => storage.chats['session']!.last.effectiveInnerVoice == '候选 B 心声',
    );

    final message = storage.chats['session']!.last;
    expect(message.variantCount, 2);
    expect(message.variants[0].innerVoice, isEmpty);
    expect(message.variants[1].innerVoice, '候选 B 心声');
  });

  testWidgets(
    'stored inner voice is hidden while off and split shows it once',
    (tester) async {
      final character = _character();
      final message = ChatMessage(
        role: 'assistant',
        content: '第一行\n\n第二行',
        innerVoice: '保留的心声',
        time: DateTime(2026),
      );
      final storage = _SessionStorage(
        character: character,
        sessions: [_session(openingMessageInitialized: true)],
        chat: [message],
      );

      await _pumpChat(tester, storage, character);
      expect(find.textContaining('保留的心声'), findsNothing);

      const enabled = AppSettings(
        showCharacterInnerVoice: true,
        splitRoleMessages: true,
      );
      storage.settings = enabled;
      await _pumpChat(tester, storage, character, settings: enabled);
      expect(
        find.byKey(const ValueKey('character-inner-voice-preview')),
        findsOneWidget,
      );
      expect(find.textContaining('保留的心声'), findsOneWidget);
    },
  );

  testWidgets('switching candidates changes voice without another request', (
    tester,
  ) async {
    final character = _character();
    const settings = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [
        _message('user', '问题'),
        ChatMessage(
          role: 'assistant',
          content: '候选 A',
          time: DateTime(2026),
          variants: [
            ChatReplyVariant(
              content: '候选 A',
              innerVoice: 'A 的心声',
              time: DateTime(2026),
            ),
            ChatReplyVariant(
              content: '候选 B',
              innerVoice: 'B 的心声',
              time: DateTime(2026),
            ),
          ],
          selectedVariantIndex: 1,
        ),
      ],
      settings: settings,
    );
    final gateway = _InnerVoiceGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: settings,
    );

    expect(find.textContaining('B 的心声'), findsOneWidget);
    await tester.tap(find.byTooltip('上一个候选'));
    await tester.pumpAndSettle();

    expect(find.textContaining('A 的心声'), findsOneWidget);
    expect(find.textContaining('B 的心声'), findsNothing);
    expect(gateway.voiceCallCount, 0);
  });

  testWidgets('opening and loaded history never backfill inner voice', (
    tester,
  ) async {
    final character = _character(openingMessage: '开场白');
    const settings = AppSettings(showCharacterInnerVoice: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session()],
      chat: [_message('assistant', '已有历史')],
      settings: settings,
    );
    final gateway = _InnerVoiceGateway();

    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      settings: settings,
    );

    expect(gateway.voiceCallCount, 0);
    expect(storage.chats['session']!.single.content, '已有历史');
  });

  testWidgets(
    'a cleared initialized session does not insert its opening again',
    (tester) async {
      final character = _character(openingMessage: '唯一开场白');
      final storage = _SessionStorage(
        character: character,
        sessions: [_session()],
      );

      await _pumpChat(tester, storage, character);

      expect(find.text('唯一开场白'), findsOneWidget);
      expect(storage.sessions.single.openingMessageInitialized, isTrue);
      expect(storage.chats['session']!.single.content, '唯一开场白');

      storage.chats['session'] = [];
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpChat(tester, storage, character);

      expect(find.text('唯一开场白'), findsNothing);
      expect(find.text('当前还没有聊天记录。'), findsOneWidget);
      expect(storage.chats['session'], isEmpty);
    },
  );

  testWidgets('first opening marks an empty opening message as initialized', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session()],
    );

    await _pumpChat(tester, storage, character);

    expect(storage.sessions.single.openingMessageInitialized, isTrue);
    expect(storage.chats['session'], isEmpty);
  });

  testWidgets(
    'opening initialization preserves newer stored session metadata',
    (tester) async {
      final character = _character();
      final stale = _session(title: '旧标题');
      final latest = stale.copyWith(title: '新标题', isArchived: true);
      final storage = _SessionStorage(character: character, sessions: [latest]);

      await _pumpChat(tester, storage, character, session: stale);

      final saved = storage.sessions.single;
      expect(saved.title, '新标题');
      expect(saved.isArchived, isTrue);
      expect(saved.createdAt, stale.createdAt);
      expect(saved.openingMessageInitialized, isTrue);
    },
  );

  testWidgets(
    'latest initialized state prevents opening replay from a stale session',
    (tester) async {
      final character = _character(openingMessage: '唯一开场白');
      final stale = _session();
      final latest = stale.copyWith(openingMessageInitialized: true);
      final storage = _SessionStorage(character: character, sessions: [latest]);

      await _pumpChat(tester, storage, character, session: stale);

      expect(find.text('唯一开场白'), findsNothing);
      expect(storage.chats['session'], isEmpty);
      expect(storage.sessions.single.openingMessageInitialized, isTrue);
    },
  );

  testWidgets('returning from session management refreshes the same session', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(title: '旧标题', openingMessageInitialized: true)],
    );
    await _pumpChat(tester, storage, character);

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    storage.sessions[0] = storage.sessions[0].copyWith(title: '新标题');
    Navigator.of(tester.element(find.byType(ChatSessionListScreen))).pop();
    await tester.pumpAndSettle();

    expect(find.text('新标题'), findsOneWidget);
    expect(find.text('旧标题'), findsNothing);
  });

  testWidgets('chat reads entries only for referenced enabled world books', (
    tester,
  ) async {
    final character = _character(worldBookIds: const ['book_b']);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      worldBooks: [_book('book_a'), _book('book_b'), _book('book_c')],
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '普通消息');
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(storage.loadedWorldBookEntryIds, ['book_b']);
  });

  testWidgets('chat with no world book references reads no entry files', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      worldBooks: [_book('book_a'), _book('book_b')],
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '普通消息');
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(storage.loadedWorldBookEntryIds, isEmpty);
  });

  testWidgets('chat skips entry files for referenced disabled world books', (
    tester,
  ) async {
    final character = _character(worldBookIds: const ['book_b']);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      worldBooks: [_book('book_b', enabled: false)],
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '普通消息');
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(storage.loadedWorldBookEntryIds, isEmpty);
    expect(
      gateway.messages!.map((message) => message['content']).join('\n'),
      isNot(contains('世界书命中内容')),
    );
  });

  testWidgets(
    'regeneration excludes the old assistant from world book matching',
    (tester) async {
      final character = _character(worldBookIds: const ['book_b']);
      final storage = _SessionStorage(
        character: character,
        sessions: [_session(openingMessageInitialized: true)],
        chat: [_message('user', '普通问题'), _message('assistant', '旧回复提到了天剑宗')],
        worldBooks: [_book('book_b')],
        worldBookEntries: {
          'book_b': [_worldEntry('book_b')],
        },
      );
      final gateway = _RecordingGateway();
      await _pumpChat(tester, storage, character, gateway: gateway);

      await tester.tap(find.text('重新生成'));
      await _pumpUntil(tester, () => gateway.messages != null);

      final request = gateway.messages!
          .map((message) => message['content'])
          .join('\n');
      expect(request, contains('普通问题'));
      expect(request, isNot(contains('旧回复提到了天剑宗')));
      expect(request, isNot(contains('世界书命中内容')));
    },
  );

  testWidgets('regeneration still matches a keyword from the user context', (
    tester,
  ) async {
    final character = _character(worldBookIds: const ['book_b']);
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [_message('user', '请介绍天剑宗'), _message('assistant', '旧回复')],
      worldBooks: [_book('book_b')],
      worldBookEntries: {
        'book_b': [_worldEntry('book_b')],
      },
    );
    final gateway = _RecordingGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    await tester.tap(find.text('重新生成'));
    await _pumpUntil(tester, () => gateway.messages != null);

    expect(
      gateway.messages!.map((message) => message['content']).join('\n'),
      contains('世界书命中内容'),
    );
  });

  testWidgets('an old request cannot detach the newer buffer from stop', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '请求 A');
    await _pumpUntil(tester, () => gateway.callCount == 1);
    gateway.controllers[0].add('A 的片段');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    await _send(tester, '请求 B');
    await _pumpUntil(tester, () => gateway.callCount == 2);
    await gateway.controllers[0].close();
    await tester.pump();
    await tester.pump();

    gateway.controllers[1].add('B 待刷新片段');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => storage.chats['session']?.last.content == 'B 待刷新片段',
    );

    expect(storage.chats['session']!.last.role, 'assistant');
    expect(storage.chats['session']!.last.content, isNot(contains('A 的片段')));
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('an old variant request cannot clear a newer typing state', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [_message('user', '问题'), _message('assistant', '原回复')],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await tester.tap(find.text('重新生成'));
    await _pumpUntil(tester, () => gateway.callCount == 1);
    expect(find.byType(TypingBubble), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    await tester.tap(find.text('重新生成'));
    await _pumpUntil(tester, () => gateway.callCount == 2);
    expect(find.byType(TypingBubble), findsOneWidget);

    await gateway.controllers[0].close();
    await tester.pump();
    await tester.pump();

    expect(find.byType(TypingBubble), findsOneWidget);

    gateway.controllers[1].add('新回复');
    await gateway.controllers[1].close();
    await tester.pumpAndSettle();
    expect(storage.chats['session']!.last.effectiveContent, '新回复');
  });

  testWidgets('session management does not force partial reply persistence', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    storage.safeSaveGate = Completer<void>();
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '长回复');
    await _pumpUntil(tester, () => gateway.callCount == 1);
    gateway.controllers.single.add('已输出的部分');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('对话管理'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatSessionListScreen), findsOneWidget);
    expect(storage.chats['session']!.last.content, '长回复');
    Navigator.of(tester.element(find.byType(ChatSessionListScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.textContaining('已输出的部分'), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('management waits for a save already started by Stop', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    storage.safeSaveGate = Completer<void>();
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '长回复');
    await _pumpUntil(tester, () => gateway.callCount == 1);
    gateway.controllers.single.add('停止前片段');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    await tester.tap(find.byTooltip('对话管理'));
    await tester.pump();

    expect(find.byType(ChatSessionListScreen), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isFalse,
    );
    storage.safeSaveGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ChatSessionListScreen), findsOneWidget);
    expect(storage.chats['session']!.last.content, '停止前片段');
  });

  testWidgets('rapid regeneration starts only one request after API reload', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [_message('user', '问题'), _message('assistant', '旧回复')],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);
    storage.apiLoadGate = Completer<void>();

    final regenerate = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '重新生成'))
        .onPressed!;
    regenerate();
    regenerate();
    await tester.pump();
    storage.apiLoadGate!.complete();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.callCount, 1);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'partial reply save failure after Stop is shown and management still opens',
    (tester) async {
      final character = _character();
      final storage = _SessionStorage(
        character: character,
        sessions: [_session(openingMessageInitialized: true)],
      );
      storage.safeSaveError = StateError('部分回复保存失败');
      final gateway = _ControlledGateway();
      addTearDown(gateway.close);
      await _pumpChat(tester, storage, character, gateway: gateway);

      await _send(tester, '长回复');
      await _pumpUntil(tester, () => gateway.callCount == 1);
      gateway.controllers.single.add('片段');
      await tester.pump(const Duration(milliseconds: 50));
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.stop))
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(storage.safeSaveCallCount, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect((snackBar.content as Text).data, contains('部分回复保存失败'));
      await tester.tap(find.byTooltip('对话管理'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatSessionListScreen), findsOneWidget);
      expect(find.byTooltip('新建对话'), findsWidgets);
    },
  );

  testWidgets('generation keeps non-destructive controls available', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [_message('user', '已有消息')],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '新消息');
    await _pumpUntil(tester, () => gateway.callCount == 1);

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.settings_outlined),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.summarize_outlined),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.menu_book_outlined),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline).first,
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.bookmark_add_outlined).first,
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('chat-clear-history-setting')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('chat-clear-history-setting')),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('chat-export-history-setting')),
          )
          .onTap,
      isNotNull,
    );
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryManagerScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(MemoryManagerScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ChatSessionListScreen), findsOneWidget);
    gateway.controllers.single.add('still streaming');
    await tester.pump(const Duration(milliseconds: 50));
    Navigator.of(tester.element(find.byType(ChatSessionListScreen))).pop();
    await tester.pumpAndSettle();

    expect(find.textContaining('still streaming'), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
  });

  testWidgets('sending keeps the keyboard and opacity-aware input visible', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    final input = find.byType(TextField).last;
    await tester.tap(input);
    await tester.enterText(input, 'next message');
    expect(tester.testTextInput.isVisible, isTrue);
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
        .onPressed!();
    await _pumpUntil(tester, () => gateway.callCount == 1);

    final field = tester.widget<TextField>(input);
    expect(field.enabled, isTrue);
    expect(field.focusNode, isNotNull);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    final borders = [
      field.decoration?.border,
      field.decoration?.enabledBorder,
      field.decoration?.focusedBorder,
      field.decoration?.disabledBorder,
    ];
    for (final border in borders) {
      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderSide.color.a,
        closeTo(character.inputOpacity, 0.001),
      );
    }

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
  });

  testWidgets('session switching waits for generation without cancelling it', (
    tester,
  ) async {
    final character = _character();
    final sessionA = _session(
      id: 'session_a',
      title: 'Session A',
      openingMessageInitialized: true,
    );
    final sessionB = _session(
      id: 'session_b',
      title: 'Session B',
      openingMessageInitialized: true,
    );
    final storage = _SessionStorage(
      character: character,
      sessions: [sessionA, sessionB],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      session: sessionA,
    );

    await _send(tester, 'long reply');
    await _pumpUntil(tester, () => gateway.callCount == 1);
    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session B'));
    await tester.pump();

    expect(find.text('Session A'), findsWidgets);
    expect(find.byIcon(Icons.stop), findsOneWidget);

    gateway.controllers.single.add('completed in A');
    await gateway.controllers.single.close();
    await tester.pumpAndSettle();

    expect(find.text('Session B'), findsOneWidget);
    expect(storage.chats['session_a']!.last.content, 'completed in A');
  });

  testWidgets('regenerate waits for the active reply without cancelling it', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
    );
    final gateway = _ControlledGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, 'question');
    await _pumpUntil(tester, () => gateway.callCount == 1);
    gateway.controllers.first.add('first reply');
    await tester.pump(const Duration(milliseconds: 50));

    final regenerate = find.widgetWithText(TextButton, '重新生成');
    expect(regenerate, findsOneWidget);
    tester.widget<TextButton>(regenerate).onPressed!();
    await tester.pump();
    expect(gateway.callCount, 1);

    await gateway.controllers.first.close();
    await _pumpUntil(tester, () => gateway.callCount == 2);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
  });

  testWidgets('manual summary owns the busy state until its request finishes', (
    tester,
  ) async {
    final character = _character();
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [
        for (var index = 0; index < 12; index++)
          _message(index.isEven ? 'user' : 'assistant', '消息 $index'),
      ],
    );
    final gateway = _SummaryGateway();
    await _pumpChat(tester, storage, character, gateway: gateway);

    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '结束并总结'))
        .onPressed!();
    await tester.pump();
    await _pumpUntil(tester, () => gateway.summaryCallCount == 1);

    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline).first,
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.forum_outlined),
          )
          .onPressed,
      isNotNull,
    );

    gateway.completeSummary('新总结');
    await tester.pumpAndSettle();
    expect(find.text('历史总结'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isTrue,
    );
    expect(storage.savedSummaries.single.sessionId, 'session');
  });

  testWidgets('an old rolling summary finally cannot clear a newer one', (
    tester,
  ) async {
    final character = _character(
      useFullChatContext: false,
      chatSummaryMessageLimit: 30,
    );
    final storage = _SessionStorage(
      character: character,
      sessions: [_session(openingMessageInitialized: true)],
      chat: [
        for (var index = 0; index < 30; index++)
          _message(index.isEven ? 'user' : 'assistant', '历史 $index'),
      ],
    );
    final gateway = _RollingSummaryGateway();
    addTearDown(gateway.close);
    await _pumpChat(tester, storage, character, gateway: gateway);

    await _send(tester, '请求 A');
    await _pumpUntil(tester, () => gateway.summaryCallCount == 1);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    await _send(tester, '请求 B');
    await _pumpUntil(tester, () => gateway.summaryCallCount == 2);
    gateway.completeSummary('旧总结', 0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
      Offset.zero,
    );
    gateway.completeSummary('新总结', 1);
    await _pumpUntil(tester, () => gateway.callCount == 1);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    expect(storage.savedSummaries.single.summary, '新总结');
  });

  testWidgets('a disposed manual summary cannot write stale session data', (
    tester,
  ) async {
    final character = _character();
    final sessionA = _session(id: 'session_a', openingMessageInitialized: true);
    final sessionB = _session(id: 'session_b', openingMessageInitialized: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [sessionA, sessionB],
      chat: [_message('user', 'A 的消息')],
    );
    final gateway = _SummaryGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      session: sessionA,
    );
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '结束并总结'))
        .onPressed!();
    await _pumpUntil(tester, () => gateway.summaryCallCount == 1);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: ChatScreen(
          key: const ValueKey('replacement-chat'),
          storage: storage,
          aiService: gateway,
          character: character,
          settings: const AppSettings(),
          session: sessionB,
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.completeSummary('A 的旧总结');
    await tester.pumpAndSettle();

    expect(storage.savedSummaries, isEmpty);
    expect(storage.summaries['session_b']!.summary, isEmpty);
  });

  testWidgets('session management cancels summary A before switching to B', (
    tester,
  ) async {
    final character = _character();
    final sessionA = _session(
      id: 'session_a',
      title: 'A 对话',
      openingMessageInitialized: true,
    );
    final sessionB = _session(
      id: 'session_b',
      title: 'B 对话',
      openingMessageInitialized: true,
    );
    final storage = _SessionStorage(
      character: character,
      sessions: [sessionA, sessionB],
      chat: [_message('user', 'A 的消息')],
    );
    final gateway = _SummaryGateway();
    await _pumpChat(
      tester,
      storage,
      character,
      gateway: gateway,
      session: sessionA,
    );
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '结束并总结'))
        .onPressed!();
    await _pumpUntil(tester, () => gateway.summaryCallCount == 1);

    await tester.tap(find.byTooltip('对话管理'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatSessionListScreen), findsOneWidget);
    await tester.tap(find.text('B 对话'));
    await tester.pumpAndSettle();
    gateway.completeSummary('A 的旧总结');
    await tester.pumpAndSettle();

    expect(find.text('B 对话'), findsOneWidget);
    expect(storage.savedSummaries, isEmpty);
    expect(storage.summaries['session_b']!.summary, isEmpty);
  });

  testWidgets('summary dialog refuses to save after the session changes', (
    tester,
  ) async {
    final character = _character();
    final sessionA = _session(
      id: 'session_a',
      title: 'A 对话',
      openingMessageInitialized: true,
    );
    final sessionB = _session(
      id: 'session_b',
      title: 'B 对话',
      openingMessageInitialized: true,
    );
    final storage = _SessionStorage(
      character: character,
      sessions: [sessionA, sessionB],
      chat: [_message('user', '消息')],
      summary: ChatSummary(
        characterId: character.id,
        sessionId: sessionA.id,
        summary: 'A 的总结',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 1,
      ),
    );
    storage.summaries[sessionB.id] = ChatSummary.empty(
      character.id,
      sessionB.id,
    );
    await _pumpChat(tester, storage, character, session: sessionA);
    final openSessions = tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.forum_outlined),
        )
        .onPressed!;
    await tester.tap(find.byTooltip('查看历史总结'));
    await tester.pumpAndSettle();
    expect(find.text('A 的总结'), findsOneWidget);

    openSessions();
    await tester.pumpAndSettle();
    await tester.tap(find.text('B 对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('当前对话已切换，请重新打开历史总结'), findsOneWidget);
    expect(storage.savedSummaries, isEmpty);
  });

  testWidgets('swiping memory tabs keeps the add action in sync', (
    tester,
  ) async {
    final character = _character();
    final session = _session(openingMessageInitialized: true);
    final storage = _SessionStorage(character: character, sessions: [session]);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MemoryManagerScreen(
          storage: storage,
          aiService: _RecordingGateway(),
          character: character,
          session: session,
          selectedEndpointId: 'endpoint',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加长期记忆'), findsWidgets);
    await tester.drag(find.byType(TabBarView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('添加当前对话记忆'), findsWidgets);

    await tester.drag(find.byType(TabBarView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('添加世界书'), findsWidgets);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('引用已有世界书'), findsOneWidget);
    expect(find.text('新建世界书'), findsOneWidget);
  });

  testWidgets(
    'deleting an old selected candidate truncates its dependent timeline',
    (tester) async {
      final character = _character();
      final summary = ChatSummary(
        characterId: character.id,
        sessionId: 'session',
        summary: '包含后续消息的总结',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 4,
      );
      final storage = _SessionStorage(
        character: character,
        sessions: [_session(openingMessageInitialized: true)],
        chat: [
          _message('user', '问题'),
          _variantMessage(),
          _message('user', '基于候选 B 的追问'),
          _message('assistant', '基于候选 B 的回答'),
        ],
        summary: summary,
      );
      await _pumpChat(tester, storage, character);

      final candidateBubble = find.ancestor(
        of: find.text('候选 B'),
        matching: find.byType(Card),
      );
      final deleteButton = candidateBubble.evaluate().isEmpty
          ? find.byTooltip('删除消息').at(2)
          : find.descendant(
              of: candidateBubble,
              matching: find.byTooltip('删除消息'),
            );
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('删除它之后的消息'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('基于候选 B 的追问'), findsOneWidget);

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(storage.chats['session'], hasLength(2));
      expect(storage.chats['session']!.last.effectiveContent, '候选 A');
      expect(storage.savedSummaries.single.summary, isEmpty);
      expect(storage.saveOrder, ['summary', 'chat']);
    },
  );

  testWidgets('memory editor never exposes keyword input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MemoryEditScreen(
          character: _character(),
          session: _session(),
          initialContent: '需要审核的内容',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<MemoryScope>), findsOneWidget);
    expect(find.text('关键词'), findsNothing);
  });

  testWidgets('memory scope changes keep sessionId consistent', (tester) async {
    final character = _character();
    final session = _session();
    final result = Completer<CharacterMemoryEntry?>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result.complete(
                await Navigator.of(context).push<CharacterMemoryEntry>(
                  MaterialPageRoute(
                    builder: (_) => MemoryEditScreen(
                      character: character,
                      session: session,
                      entry: CharacterMemoryEntry(
                        id: 'memory',
                        characterId: character.id,
                        scope: MemoryScope.character,
                        title: '标题',
                        content: '内容',
                        createdAt: DateTime(2026),
                        updatedAt: DateTime(2026),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<MemoryScope>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当前对话记忆').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await result.future;
    expect(saved?.scope, MemoryScope.session);
    expect(saved?.sessionId, session.id);
    expect(saved?.keywords, isEmpty);
  });

  testWidgets('changing a session memory to long-term clears sessionId', (
    tester,
  ) async {
    final character = _character();
    final session = _session();
    final result = Completer<CharacterMemoryEntry?>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result.complete(
                await Navigator.of(context).push<CharacterMemoryEntry>(
                  MaterialPageRoute(
                    builder: (_) => MemoryEditScreen(
                      character: character,
                      session: session,
                      entry: CharacterMemoryEntry(
                        id: 'session_memory',
                        characterId: character.id,
                        scope: MemoryScope.session,
                        sessionId: session.id,
                        title: '标题',
                        content: '内容',
                        createdAt: DateTime(2026),
                        updatedAt: DateTime(2026),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<MemoryScope>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('长期记忆').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await result.future;
    expect(saved?.scope, MemoryScope.character);
    expect(saved?.sessionId, isNull);
    expect(saved?.keywords, isEmpty);
  });

  testWidgets('ordinary memory editor keeps scope fixed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MemoryEditScreen(
          character: _character(),
          session: _session(),
          initialScope: MemoryScope.character,
          allowScopeChange: false,
          initialContent: '普通记忆',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<MemoryScope>), findsNothing);
    expect(find.text('关键词'), findsNothing);
  });

  testWidgets('AI memory review keeps selection and returns edited scope', (
    tester,
  ) async {
    final character = _character();
    final session = _session(openingMessageInitialized: true);
    final storage = _SessionStorage(
      character: character,
      sessions: [session],
      chat: [_message('user', '请记住称呼')],
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MemoryManagerScreen(
          storage: storage,
          aiService: _ExtractionGateway(),
          character: character,
          session: session,
          selectedEndpointId: 'endpoint',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.text('审核提取记忆'), findsOneWidget);
    expect(find.textContaining('长期记忆'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<MemoryScope>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当前对话记忆').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前对话记忆'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await tester.tap(find.text('保存选中项'));
    await tester.pumpAndSettle();

    expect(storage.savedMemories, hasLength(1));
    expect(storage.savedMemories.single.scope, MemoryScope.session);
    expect(storage.savedMemories.single.sessionId, session.id);
    expect(storage.savedMemories.single.keywords, isEmpty);
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  _SessionStorage storage,
  AppCharacter character, {
  AiGateway? gateway,
  ChatSession? session,
  AppSettings? settings,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: ChatScreen(
        storage: storage,
        aiService: gateway ?? _RecordingGateway(),
        character: character,
        settings: settings ?? storage.settings,
        session: session ?? storage.sessions.first,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
      .onPressed
      ?.call();
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 100 && !condition(); index++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

AppCharacter _character({
  String openingMessage = '',
  List<String> worldBookIds = const [],
  bool useFullChatContext = true,
  int chatSummaryMessageLimit = 50,
}) => AppCharacter.fromJson({
  'id': 'character',
  'name': '角色',
  'openingMessage': openingMessage,
  'defaultEndpointId': 'endpoint',
  'worldBookIds': worldBookIds,
  'useFullChatContext': useFullChatContext,
  'chatSummaryMessageLimit': chatSummaryMessageLimit,
});

ChatSession _session({
  String id = 'session',
  String title = '对话',
  bool openingMessageInitialized = false,
}) {
  final now = DateTime(2026);
  return ChatSession(
    id: id,
    characterId: 'character',
    title: title,
    createdAt: now,
    updatedAt: now,
    lastUsedAt: now,
    openingMessageInitialized: openingMessageInitialized,
  );
}

ChatMessage _message(String role, String content) =>
    ChatMessage(role: role, content: content, time: DateTime(2026));

ChatMessage _variantMessage() => ChatMessage(
  role: 'assistant',
  content: '候选 A',
  time: DateTime(2026),
  variants: [
    ChatReplyVariant(content: '候选 A', time: DateTime(2026)),
    ChatReplyVariant(content: '候选 B', time: DateTime(2026)),
  ],
  selectedVariantIndex: 1,
);

WorldBook _book(String id, {bool enabled = true}) => WorldBook(
  id: id,
  name: id,
  enabled: enabled,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

WorldBookEntry _worldEntry(String worldBookId) => WorldBookEntry(
  id: 'entry',
  worldBookId: worldBookId,
  title: '宗门',
  content: '世界书命中内容',
  keywords: const ['天剑宗'],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ApiConfig _apiConfig() => ApiConfig(
  endpoints: [
    AiEndpointConfig(
      id: 'endpoint',
      name: 'Endpoint',
      apiKey: 'key',
      baseUrl: 'https://example.test/v1',
      model: 'model',
      enabled: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ],
  defaultEndpointId: 'endpoint',
);

final class _SessionStorage extends LocalStorageService {
  _SessionStorage({
    required this.character,
    required List<ChatSession> sessions,
    List<ChatMessage> chat = const [],
    ChatSummary? summary,
    this.worldBooks = const [],
    this.worldBookEntries = const {},
    this.settings = const AppSettings(),
  }) : sessions = [...sessions],
       chats = {
         for (final session in sessions) session.id: [...chat],
       },
       summaries = {
         for (final session in sessions)
           session.id:
               summary ?? ChatSummary.empty(session.characterId, session.id),
       },
       super();

  AppCharacter character;
  final List<ChatSession> sessions;
  final Map<String, List<ChatMessage>> chats;
  final Map<String, ChatSummary> summaries;
  final savedSummaries = <ChatSummary>[];
  final savedMemories = <CharacterMemoryEntry>[];
  final saveOrder = <String>[];
  final List<WorldBook> worldBooks;
  final Map<String, List<WorldBookEntry>> worldBookEntries;
  final loadedWorldBookEntryIds = <String>[];
  Completer<void>? apiLoadGate;
  Completer<void>? safeSaveGate;
  Object? safeSaveError;
  AppSettings settings;
  final usageTypes = <String>[];
  var safeSaveCallCount = 0;
  var settingsLoadCallCount = 0;
  final settingsLoadFailures = <int>{};

  @override
  bool get usesSessionStorage => true;

  @override
  Future<SessionOperationToken> captureSessionToken(
    ChatSession session,
  ) async => SessionOperationToken(session.id, datasetEpoch, 0);

  @override
  Future<ChatSummary> clearChatPreservingSummary(ChatSession session) async {
    final previous = await loadSummaryBySession(session);
    final summary = ChatSummary(
      characterId: session.characterId,
      sessionId: session.id,
      summary: previous.summary,
      updatedAt: DateTime.now(),
      summarizedMessageCount: 0,
    );
    await saveSummaryBySession(summary);
    await saveChatBySession(session, []);
    return summary;
  }

  @override
  Future<void> backfillMessageCounts(
    List<ChatSession> sessions, {
    void Function(ChatSession session)? onUpdated,
    void Function(String session, Object error)? onError,
  }) async {}

  @override
  Future<ApiConfig> loadApiConfig() async {
    if (apiLoadGate != null) await apiLoadGate!.future;
    return _apiConfig();
  }

  @override
  Future<AppSettings> loadSettings() async {
    settingsLoadCallCount++;
    if (settingsLoadFailures.contains(settingsLoadCallCount)) {
      throw StateError('设置读取失败');
    }
    return settings;
  }

  @override
  Future<List<AppCharacter>> loadCharacters() async => [character];

  @override
  Future<void> saveCharacter(AppCharacter value) async => character = value;

  @override
  Future<List<ChatSession>> loadChatSessions(String characterId) async =>
      sessions.where((session) => session.characterId == characterId).toList();

  @override
  Future<ChatSession> getOrCreateRecentChatSession(String characterId) async =>
      sessions.first;

  @override
  Future<void> saveChatSession(ChatSession session) async {
    final index = sessions.indexWhere((item) => item.id == session.id);
    index < 0 ? sessions.add(session) : sessions[index] = session;
  }

  @override
  Future<ChatSession> markOpeningMessageInitialized({
    required String sessionId,
    required String characterId,
  }) async {
    final index = sessions.indexWhere(
      (session) =>
          session.id == sessionId && session.characterId == characterId,
    );
    if (index < 0) throw StateError('对话不存在');
    final updated = sessions[index].copyWith(
      openingMessageInitialized: true,
      updatedAt: DateTime.now(),
    );
    sessions[index] = updated;
    return updated;
  }

  @override
  Future<List<ChatMessage>> loadChatBySession(ChatSession session) async => [
    ...chats[session.id] ?? const <ChatMessage>[],
  ];

  @override
  Future<void> saveChatBySession(
    ChatSession session,
    List<ChatMessage> messages,
  ) async {
    chats[session.id] = [...messages];
    saveOrder.add('chat');
  }

  @override
  Future<bool> saveChatBySessionIfExists(
    ChatSession session,
    List<ChatMessage> messages, {
    SessionOperationToken? token,
  }) async {
    safeSaveCallCount++;
    if (safeSaveGate != null) await safeSaveGate!.future;
    if (safeSaveError != null) throw safeSaveError!;
    if (!sessions.any((item) => item.id == session.id)) return false;
    await saveChatBySession(session, messages);
    return true;
  }

  @override
  Future<ChatSummary> loadSummaryBySession(ChatSession session) async =>
      summaries[session.id] ??
      ChatSummary.empty(session.characterId, session.id);

  @override
  Future<void> saveSummaryBySession(
    ChatSummary summary, {
    SessionOperationToken? token,
  }) async {
    summaries[summary.sessionId] = summary;
    savedSummaries.add(summary);
    saveOrder.add('summary');
  }

  @override
  Future<List<CharacterMemoryEntry>> loadCharacterMemories(
    String characterId,
  ) async => [...savedMemories];

  @override
  Future<void> saveCharacterMemory(CharacterMemoryEntry entry) async {
    final index = savedMemories.indexWhere((item) => item.id == entry.id);
    index < 0 ? savedMemories.add(entry) : savedMemories[index] = entry;
  }

  @override
  Future<List<WorldBook>> loadWorldBooks() async => [...worldBooks];

  @override
  Future<List<WorldBookEntry>> loadWorldBookEntries(String worldBookId) async {
    loadedWorldBookEntryIds.add(worldBookId);
    return [...worldBookEntries[worldBookId] ?? const <WorldBookEntry>[]];
  }

  @override
  Future<void> recordAiUsage({
    required String requestType,
    required String model,
    required AiUsage usage,
    required List<Map<String, String>> messages,
    required bool summaryUpdated,
  }) async {
    usageTypes.add(requestType);
  }
}

final class _InnerVoiceGateway extends _RecordingGateway {
  _InnerVoiceGateway({this.mainReply = '主回复'});

  final String mainReply;
  final voiceMessages = <List<Map<String, String>>>[];
  final voiceModels = <String>[];
  final _voices = <Completer<String>>[];

  int get voiceCallCount => _voices.length;

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) async* {
    this.messages = messages;
    yield mainReply;
  }

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) {
    voiceMessages.add(messages);
    voiceModels.add(model);
    onUsage?.call(const AiUsage(promptTokens: 5, completionTokens: 2));
    final completer = Completer<String>();
    _voices.add(completer);
    return completer.future;
  }

  void completeVoice(String value, [int index = 0]) =>
      _voices[index].complete(value);

  void failVoice(Object error, [int index = 0]) =>
      _voices[index].completeError(error);
}

class _RecordingGateway implements AiGateway {
  List<Map<String, String>>? messages;

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) async => '回复';

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) async* {
    this.messages = messages;
    yield '回复';
  }
}

class _ControlledGateway extends _RecordingGateway {
  final controllers = <StreamController<String>>[];

  int get callCount => controllers.length;

  @override
  Stream<String> streamMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(AiUsage usage)? onUsage,
  }) {
    this.messages = messages;
    final controller = StreamController<String>();
    controllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    for (final controller in controllers) {
      if (!controller.isClosed) await controller.close();
    }
  }
}

final class _SummaryGateway extends _RecordingGateway {
  final _summaries = <Completer<String>>[];

  int get summaryCallCount => _summaries.length;

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) {
    final completer = Completer<String>();
    _summaries.add(completer);
    return completer.future;
  }

  void completeSummary(String value, [int index = 0]) {
    _summaries[index].complete(value);
  }
}

final class _ExtractionGateway extends _RecordingGateway {
  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) async =>
      '[{"title":"称呼","content":"称呼用户为星星","scope":"character","priority":60}]';
}

final class _RollingSummaryGateway extends _ControlledGateway {
  final _summaries = <Completer<String>>[];

  int get summaryCallCount => _summaries.length;

  @override
  Future<String> sendMessage({
    required String apiKey,
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    AiCancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) {
    final completer = Completer<String>();
    _summaries.add(completer);
    return completer.future;
  }

  void completeSummary(String value, int index) {
    _summaries[index].complete(value);
  }
}
