import '../../models/novel_book.dart';
import '../../models/theater.dart';
import '../../models/user_profile.dart';

class NovelTheaterFactory {
  const NovelTheaterFactory();

  TheaterSession createDraftFromNovel(
    NovelBook book, {
    UserProfile userProfile = const UserProfile(),
    NovelRoleCandidate? userRole,
    DateTime? now,
  }) {
    final created = now ?? DateTime.now();
    final sessionId = 'theater_${created.microsecondsSinceEpoch}';
    final selectedUserIndex = userRole == null
        ? -1
        : book.roles.indexWhere(
            (role) => identical(role, userRole) || role.name == userRole.name,
          );
    final user = selectedUserIndex < 0
        ? TheaterParticipant.fromUserProfile(userProfile, id: '$sessionId-user')
        : TheaterParticipant.fromNovelRole(
            book: book,
            role: book.roles[selectedUserIndex],
            id: '$sessionId-user',
          );
    final aiIndexes = [
      for (var index = 0; index < book.roles.length; index++) index,
    ]..remove(selectedUserIndex);
    return TheaterSession(
      id: sessionId,
      title: _title(book.title),
      boundNovelId: book.id,
      boundNovelTitle: book.title,
      userParticipantId: user.id,
      participants: [
        ..._aiParticipants(
          book,
          sessionId: sessionId,
          indexes: aiIndexes,
          fallbackWhenEmpty: book.roles.isEmpty,
        ),
        user,
      ],
      createdAt: created,
      updatedAt: created,
    );
  }

  List<TheaterParticipant> _aiParticipants(
    NovelBook book, {
    required String sessionId,
    List<int>? indexes,
    bool fallbackWhenEmpty = true,
  }) {
    final selected = indexes ?? [for (var i = 0; i < book.roles.length; i++) i];
    if (selected.isEmpty && fallbackWhenEmpty) {
      return [
        TheaterParticipant(
          id: '$sessionId-role-fallback',
          source: TheaterRoleSource.novelRole,
          sourceNovelId: book.id,
          sourceNovelTitle: book.title,
          sourceRoleId: '小说角色',
          name: '小说角色',
          avatar: '',
          description: '根据小说设定参与群聊。',
          personality: '参考小说设定档。',
          background: book.summary,
          speakingStyle: '参考小说原文。',
        ),
      ];
    }
    return [
      for (final index in selected)
        TheaterParticipant.fromNovelRole(
          book: book,
          role: book.roles[index],
          id: '$sessionId-role-$index',
        ),
    ];
  }

  String _title(String raw) {
    final title = raw.trim();
    return title.startsWith('《') && title.endsWith('》')
        ? '$title群聊'
        : '《$title》群聊';
  }
}
