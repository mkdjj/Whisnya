import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/controllers/theater_chat_controller.dart';
import 'package:whisnya/models/theater.dart';

void main() {
  test('validates participant replies against current session state', () {
    final controller = TheaterChatController(_session);

    expect(
      controller.resolveParticipantReply('missing').status,
      TheaterParticipantReplyStatus.missing,
    );
    expect(
      controller.resolveParticipantReply('disabled').status,
      TheaterParticipantReplyStatus.disabled,
    );
    expect(
      controller.resolveParticipantReply('muted').status,
      TheaterParticipantReplyStatus.muted,
    );
    expect(
      controller.resolveParticipantReply('ready').status,
      TheaterParticipantReplyStatus.noMessages,
    );

    controller.replaceMessages([_message('old', 'ready', round: 2)]);
    final result = controller.resolveParticipantReply('ready');
    expect(result.status, TheaterParticipantReplyStatus.ready);
    expect(result.participant?.name, '可用');
    expect(controller.nextRound, 3);
  });

  test('owns message reduction and deterministic turn order', () {
    final controller = TheaterChatController(_session);
    controller.replaceMessages([_message('old', 'ready')]);
    controller.appendMessage(_message('draft', 'ready', content: ''));
    expect(
      controller.replaceMessage(
        'draft',
        _message('draft', 'ready', content: '完成'),
      ),
      isTrue,
    );
    expect(controller.messages.last.content, '完成');
    expect(controller.removeMessage('old'), isTrue);

    expect(
      controller.turnBasedParticipants(oneParticipant: true).single.id,
      'other',
    );
    expect(
      controller
          .turnBasedParticipants(oneParticipant: false)
          .map((item) => item.id),
      ['other', 'ready'],
    );
  });
}

final _session = TheaterSession(
  id: 'session',
  title: '群聊',
  nextSpeakerIndex: 1,
  participants: const [
    TheaterParticipant(
      id: 'disabled',
      source: TheaterRoleSource.appCharacter,
      name: '禁用',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
      enabled: false,
    ),
    TheaterParticipant(
      id: 'muted',
      source: TheaterRoleSource.appCharacter,
      name: '禁言',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
      isMuted: true,
    ),
    TheaterParticipant(
      id: 'ready',
      source: TheaterRoleSource.appCharacter,
      name: '可用',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
    ),
    TheaterParticipant(
      id: 'other',
      source: TheaterRoleSource.appCharacter,
      name: '另一个',
      avatar: '',
      description: '',
      personality: '',
      background: '',
      speakingStyle: '',
    ),
  ],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

TheaterMessage _message(
  String id,
  String speakerId, {
  int round = 1,
  String content = '内容',
}) => TheaterMessage(
  id: id,
  sessionId: 'session',
  round: round,
  speakerType: TheaterSpeakerType.role,
  speakerId: speakerId,
  speakerName: speakerId,
  content: content,
  time: DateTime(2026),
);
