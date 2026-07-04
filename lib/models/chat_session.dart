import 'chat_message.dart';

class ChatSession {
  const ChatSession({required this.characterId, required this.messages});

  final String characterId;
  final List<ChatMessage> messages;

  ChatSession copyWith({String? characterId, List<ChatMessage>? messages}) {
    return ChatSession(
      characterId: characterId ?? this.characterId,
      messages: messages ?? this.messages,
    );
  }

  factory ChatSession.empty(String characterId) {
    return ChatSession(characterId: characterId, messages: const []);
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    return ChatSession(
      characterId: json['characterId'] as String? ?? '',
      messages: rawMessages is List
          ? rawMessages
                .whereType<Map<String, dynamic>>()
                .map(ChatMessage.fromJson)
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characterId': characterId,
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }
}
