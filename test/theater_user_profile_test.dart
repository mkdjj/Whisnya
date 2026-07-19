import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/screens/theater/theater_screens.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets('new ordinary theater starts with a user profile copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TheaterEditScreen(
          storage: _Storage(),
          aiService: _aiService(),
          initialUserProfile: const UserProfile(name: '小明'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('小明'), findsOneWidget);
  });

  testWidgets('theater editor reports an empty AI participant list', (
    tester,
  ) async {
    final user = TheaterParticipant.fromUserProfile(
      const UserProfile(name: '小明'),
      id: 'user',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TheaterEditScreen(
          storage: _Storage(),
          aiService: _aiService(),
          session: TheaterSession(
            id: 'theater',
            title: '群聊',
            userParticipantId: user.id,
            participants: [user],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.check),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining(RegExp('至少添加一个 AI 角色|Add at least one AI role')),
      findsOneWidget,
    );
  });

  testWidgets('theater user identity can be edited as a session copy', (
    tester,
  ) async {
    final user = TheaterParticipant.fromUserProfile(
      const UserProfile(name: '小明'),
      id: 'user',
    );
    final ai = TheaterParticipant(
      id: 'ai',
      source: TheaterRoleSource.appCharacter,
      name: '角色',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TheaterEditScreen(
          storage: _Storage(),
          aiService: _aiService(),
          session: TheaterSession(
            id: 'theater',
            title: '群聊',
            userParticipantId: user.id,
            participants: [ai, user],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final edit = find.byKey(const ValueKey('edit-theater-user-profile'));
    await tester.scrollUntilVisible(
      edit,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('user-profile-name')),
      '新名字',
    );
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(find.text('新名字'), findsOneWidget);
  });
}

AiService _aiService() => AiService(
  client: MockClient((request) async => throw UnimplementedError()),
);

final class _Storage extends LocalStorageService {
  @override
  Future<ChatBubblePresetSettings> loadChatBubblePresets() async =>
      const ChatBubblePresetSettings();

  @override
  Future<List<AppCharacter>> loadCharacters() async => const [];

  @override
  Future<List<NovelBook>> loadNovels() async => const [];

  @override
  Future<ApiConfig> loadApiConfig() async => ApiConfig();
}
