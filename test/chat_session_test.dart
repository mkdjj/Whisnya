import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_session.dart';
import 'package:whisnya/models/chat_summary.dart';

void main() {
  test('chat session normalizes titles and round trips archive state', () {
    final session = ChatSession.fromJson({
      'id': 's1',
      'characterId': 'c1',
      'title': '  First chat  ',
      'createdAt': '2026-01-01T00:00:00.000',
      'updatedAt': '2026-01-02T00:00:00.000',
      'lastUsedAt': '2026-01-03T00:00:00.000',
      'isArchived': true,
    });

    expect(session.title, 'First chat');
    expect(ChatSession.fromJson(session.toJson()).isArchived, isTrue);
    expect(
      ChatSession.fromJson({...session.toJson(), 'title': '   '}).title,
      '未命名对话',
    );
  });

  test('chat session sorting keeps active and recent sessions first', () {
    final old = DateTime(2026, 1, 1);
    final recent = DateTime(2026, 1, 2);
    final sessions = [
      _session('archived', recent, archived: true),
      _session('old', old),
      _session('recent', recent),
    ]..sort(ChatSession.compare);

    expect(sessions.map((session) => session.id), [
      'recent',
      'old',
      'archived',
    ]);
  });

  test('chat summary accepts legacy json and writes its session id', () {
    final legacy = ChatSummary.fromJson({
      'characterId': 'c1',
      'summary': 'old',
      'updatedAt': '2026-01-01T00:00:00.000',
    });
    final current = ChatSummary.empty('c1', 's1');

    expect(legacy.sessionId, isEmpty);
    expect(current.toJson()['sessionId'], 's1');
  });
}

ChatSession _session(String id, DateTime lastUsedAt, {bool archived = false}) {
  return ChatSession(
    id: id,
    characterId: 'c1',
    title: id,
    createdAt: lastUsedAt,
    updatedAt: lastUsedAt,
    lastUsedAt: lastUsedAt,
    isArchived: archived,
  );
}
