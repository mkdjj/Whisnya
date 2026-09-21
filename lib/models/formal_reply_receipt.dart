import 'api_config.dart';
import 'app_character.dart';
import 'chat_message.dart';
import 'message_anchor.dart';
import '../services/storage/session_operation_coordinator.dart';

/// Published once, only after the selected formal response is durable.
class FormalReplyReceipt {
  FormalReplyReceipt({
    required this.operationId,
    required this.anchor,
    required this.epoch,
    this.sessionToken,
    required this.endpointSnapshot,
    required this.characterSnapshot,
    required List<ChatMessage> messages,
    required this.persisted,
  }) : messages = List.unmodifiable(
         messages.map((m) => ChatMessage.fromJson(m.toJson())),
       );
  final String operationId;
  final MessageAnchor anchor;
  final int epoch;
  final SessionOperationToken? sessionToken;
  final AiEndpointConfig endpointSnapshot;
  final AppCharacter characterSnapshot;
  final List<ChatMessage> messages;
  final bool persisted;
  String get contentSnapshot => messages.last.effectiveContent;
  String get replyState => messages.last.effectiveReplyState;
}
