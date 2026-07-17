import '../models/theater.dart';

enum TheaterParticipantReplyStatus {
  ready,
  noMessages,
  missing,
  disabled,
  muted,
}

final class TheaterParticipantReply {
  const TheaterParticipantReply(this.status, [this.participant]);

  final TheaterParticipantReplyStatus status;
  final TheaterParticipant? participant;
}

final class TheaterChatController {
  TheaterChatController(this._session);

  TheaterSession _session;
  var _messages = <TheaterMessage>[];

  TheaterSession get session => _session;
  List<TheaterMessage> get messages => _messages;
  int get nextRound => _messages.isEmpty ? 1 : _messages.last.round + 1;

  void updateSession(TheaterSession session) => _session = session;

  void replaceMessages(List<TheaterMessage> messages) {
    _messages = [...messages];
  }

  void appendMessage(TheaterMessage message) {
    _messages = [..._messages, message];
  }

  bool replaceMessage(String id, TheaterMessage message) {
    final index = _messages.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final next = [..._messages];
    next[index] = message;
    _messages = next;
    return true;
  }

  bool removeMessage(String id) {
    final next = _messages.where((item) => item.id != id).toList();
    if (next.length == _messages.length) return false;
    _messages = next;
    return true;
  }

  void removeEmptyRoleMessages() {
    _messages = _messages
        .where(
          (message) =>
              message.speakerType != TheaterSpeakerType.role ||
              message.content.trim().isNotEmpty,
        )
        .toList();
  }

  void clearMessages() => _messages = [];

  TheaterParticipantReply resolveParticipantReply(String participantId) {
    TheaterParticipant? participant;
    for (final item in _session.participants) {
      if (item.id == participantId) {
        participant = item;
        break;
      }
    }
    if (participant == null) {
      return const TheaterParticipantReply(
        TheaterParticipantReplyStatus.missing,
      );
    }
    if (!participant.enabled) {
      return TheaterParticipantReply(
        TheaterParticipantReplyStatus.disabled,
        participant,
      );
    }
    if (participant.isMuted) {
      return TheaterParticipantReply(
        TheaterParticipantReplyStatus.muted,
        participant,
      );
    }
    if (_messages.isEmpty) {
      return TheaterParticipantReply(
        TheaterParticipantReplyStatus.noMessages,
        participant,
      );
    }
    return TheaterParticipantReply(
      TheaterParticipantReplyStatus.ready,
      participant,
    );
  }

  Iterable<TheaterParticipant> turnBasedParticipants({
    required bool oneParticipant,
  }) {
    final participants = _session.aiParticipants;
    if (participants.isEmpty) return const [];
    final start = _session.nextSpeakerIndex % participants.length;
    final ordered = [
      for (var offset = 0; offset < participants.length; offset++)
        participants[(start + offset) % participants.length],
    ];
    return ordered.take(oneParticipant ? 1 : ordered.length);
  }
}
