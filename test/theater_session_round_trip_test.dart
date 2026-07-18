import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/models/user_profile.dart';

void main() {
  test('creates an independent theater participant from user profile', () {
    const profile = UserProfile(
      name: '小明',
      avatar: 'avatar.png',
      description: '旅行者',
      personality: '开朗',
      speakingStyle: '简洁',
      extraPrompt: '喜欢猫',
    );

    final participant = TheaterParticipant.fromUserProfile(
      profile,
      id: 'user-1',
    );
    final changed = profile.copyWith(name: '后来修改');

    expect(participant.id, 'user-1');
    expect(participant.name, '小明');
    expect(participant.avatar, 'avatar.png');
    expect(participant.description, '旅行者');
    expect(participant.personality, '开朗');
    expect(participant.speakingStyle, '简洁');
    expect(participant.background, '喜欢猫');
    expect(participant.name, isNot(changed.name));
  });

  test('legacy sessions default missing reply counts', () {
    final json = {
      'id': 'session',
      'title': 'Legacy',
      'createdAt': DateTime(2026).toIso8601String(),
      'updatedAt': DateTime(2026).toIso8601String(),
    };

    final session = TheaterSession.fromJson(json);

    expect(session.mainReplyCount, 0);
    expect(session.extraReplyMode, 0);
  });

  test('session json round trip preserves every field', () {
    final session = TheaterSession(
      id: 'session',
      title: 'Round trip',
      avatar: 'avatar.png',
      backgroundImage: 'background.png',
      backgroundImageOpacity: 0.7,
      backgroundBlur: 4,
      bubbleTheme: ChatBubbleTheme.sameOpacity(0.8),
      inputOpacity: 0.9,
      topBarOpacity: 0.2,
      isHidden: true,
      isLocked: true,
      boundNovelId: 'novel',
      boundNovelTitle: 'Novel',
      apiMode: TheaterApiMode.multiApi,
      multiApiReplyMode: TheaterMultiApiReplyMode.parallel,
      singleEndpointId: 'endpoint',
      userParticipantId: 'user',
      keepRoundCount: 20,
      mainReplyCount: 2,
      extraReplyMode: 1,
      theaterSummary: 'summary',
      summarizedMessageCount: 12,
      nextSpeakerIndex: 1,
      lastOpenedAt: DateTime(2026, 2),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 3),
    );

    expect(
      TheaterSession.fromJson(session.toJson()).toJson(),
      session.toJson(),
    );
  });
}
