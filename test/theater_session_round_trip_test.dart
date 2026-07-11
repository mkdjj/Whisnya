import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/theater.dart';

void main() {
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
      bubbleOpacity: 0.8,
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
