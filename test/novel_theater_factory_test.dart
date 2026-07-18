import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/novel_book.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/services/theater/novel_theater_factory.dart';

void main() {
  const factory = NovelTheaterFactory();

  test(
    'creates a bound draft with all roles and the selected default user',
    () {
      final session = factory.createDraftFromNovel(
        _book(),
        userProfile: const UserProfile(name: '小明', extraPrompt: '喜欢猫'),
        now: DateTime(2026),
      );
      expect(session.boundNovelId, 'novel');
      expect(session.boundNovelTitle, '书名');
      expect(session.title, '《书名》群聊');
      expect(session.aiParticipants.map((item) => item.name), ['甲', '乙']);
      expect(session.userParticipantId, isNotEmpty);
      expect(session.userParticipant?.name, '小明');
      expect(session.userParticipant?.background, '喜欢猫');
      expect(session.participants.map((item) => item.id).toSet(), hasLength(3));
      expect(session.singleEndpointId, isEmpty);
      expect(
        session.participants.every((item) => item.endpointId.isEmpty),
        isTrue,
      );
    },
  );

  test(
    'legacy session promotes selected role and removes user role from AI',
    () {
      final session = factory.createLegacySession(
        _book(selectedRoleIndex: 1, userRoleIndex: 0),
        sessionId: 'theater_legacy_novel_novel',
        theaterSummary: 'summary',
        summarizedMessageCount: 4,
        now: DateTime(2026),
      );
      expect(session.aiParticipants.map((item) => item.name), ['乙']);
      expect(session.userParticipant?.name, '甲');
      expect(session.theaterSummary, 'summary');
      expect(session.summarizedMessageCount, 4);
    },
  );

  test('novel role selected as user is not also an AI participant', () {
    final book = _book();
    final session = factory.createDraftFromNovel(
      book,
      userRole: book.roles.first,
      now: DateTime(2026),
    );

    expect(session.userParticipant?.name, '甲');
    expect(session.aiParticipants.map((item) => item.name), ['乙']);
    expect(session.participants.map((item) => item.id).toSet(), hasLength(2));
  });

  test('single novel role selected as user leaves AI list empty', () {
    final book = _book(roles: [_role('甲')]);
    final session = factory.createDraftFromNovel(
      book,
      userRole: book.roles.single,
      now: DateTime(2026),
    );

    expect(session.userParticipant?.name, '甲');
    expect(session.aiParticipants, isEmpty);
  });

  test('novel without roles gets a fallback AI role', () {
    final session = factory.createDraftFromNovel(
      _book(roles: const []),
      now: DateTime(2026),
    );
    expect(session.aiParticipants.single.name, '小说角色');
    expect(session.aiParticipants.single.background, 'novel summary');
  });
}

NovelBook _book({
  List<NovelRoleCandidate> roles = const [
    NovelRoleCandidate(
      name: '甲',
      description: '',
      personality: '',
      speakingStyle: '',
      background: '',
    ),
    NovelRoleCandidate(
      name: '乙',
      description: '',
      personality: '',
      speakingStyle: '',
      background: '',
    ),
  ],
  int selectedRoleIndex = -1,
  int userRoleIndex = -1,
}) => NovelBook(
  id: 'novel',
  title: '书名',
  textPath: 'novel.txt',
  summary: 'novel summary',
  roles: roles,
  selectedRoleIndex: selectedRoleIndex,
  userRoleIndex: userRoleIndex,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

NovelRoleCandidate _role(String name) => NovelRoleCandidate(
  name: name,
  description: '',
  personality: '',
  speakingStyle: '',
  background: '',
);
