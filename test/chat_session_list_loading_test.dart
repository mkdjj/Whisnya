import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/screens/chat/chat_session_list_screen.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets(
    'index appears while count backfill waits and failures remain per row',
    (tester) async {
      final storage = ListStorage();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatSessionListScreen(
            storage: storage,
            character: AppCharacter.fromJson({'id': 'c1', 'name': 'C'}),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Known'), findsOneWidget);
      expect(find.textContaining('42'), findsOneWidget);
      expect(find.textContaining('统计中'), findsOneWidget);
      storage.gate.complete();
      await tester.pump();
      expect(find.textContaining('数量暂不可用'), findsOneWidget);
      expect(find.text('Known'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late backfill after disposal never calls setState', (
    tester,
  ) async {
    final storage = ListStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatSessionListScreen(
          storage: storage,
          character: AppCharacter.fromJson({'id': 'c1'}),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    storage.gate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class ListStorage extends LocalStorageService {
  final gate = Completer<void>();
  @override
  Future<List<ChatSession>> loadChatSessions(String characterId) async => [
    ChatSession.fromJson({
      'id': 'known',
      'characterId': 'c1',
      'title': 'Known',
      'messageCount': 42,
    }),
    ChatSession.fromJson({
      'id': 'unknown',
      'characterId': 'c1',
      'title': 'Unknown',
    }),
  ];
  @override
  Future<List<ChatMessage>> loadChatBySession(ChatSession session) =>
      throw StateError('List must not read entire chats');
  @override
  Future<void> backfillMessageCounts(
    List<ChatSession> sessions, {
    void Function(ChatSession)? onUpdated,
    void Function(String, Object)? onError,
  }) async {
    await gate.future;
    onError?.call('unknown', const FormatException('damaged chat'));
  }
}
