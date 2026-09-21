import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'chat_message.dart';

String newStoryId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String logicalVariantId(ChatMessage message) => message.isAssistant
    ? message.selectedVariant?.id ?? 'original_${message.id}'
    : '';

/// Identity of a saved formal prefix. Auxiliary content is intentionally absent.
class MessageAnchor {
  const MessageAnchor({
    required this.sessionId,
    required this.messageId,
    this.variantId,
    required this.prefixDigest,
  });
  final String sessionId;
  final String messageId;
  final String? variantId;
  final String prefixDigest;

  static MessageAnchor capture(
    String sessionId,
    List<ChatMessage> messages,
    int index,
  ) {
    if (sessionId.isEmpty ||
        index < 0 ||
        index >= messages.length ||
        messages.take(index + 1).any((m) => m.id.isEmpty)) {
      throw StateError('Only persisted messages can be anchored');
    }
    final message = messages[index];
    return MessageAnchor(
      sessionId: sessionId,
      messageId: message.id,
      variantId: message.isAssistant ? logicalVariantId(message) : null,
      prefixDigest: digest(messages.take(index + 1)),
    );
  }

  static String digest(Iterable<ChatMessage> messages) => sha256
      .convert(
        utf8.encode(
          jsonEncode(
            messages
                .map(
                  (m) => <String, dynamic>{
                    'messageId': m.id,
                    'selectedVariantId': logicalVariantId(m),
                    'role': m.role,
                    'effectiveContent': m.effectiveContent,
                    'effectiveReplyState': m.effectiveReplyState,
                  },
                )
                .toList(),
          ),
        ),
      )
      .toString();

  bool matches(List<ChatMessage> messages) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return false;
    final target = messages[index];
    return (target.isAssistant ? logicalVariantId(target) : null) ==
            variantId &&
        digest(messages.take(index + 1)) == prefixDigest;
  }

  MessageAnchor inSession(String id) => MessageAnchor(
    sessionId: id,
    messageId: messageId,
    variantId: variantId,
    prefixDigest: prefixDigest,
  );
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'messageId': messageId,
    'variantId': variantId,
    'prefixDigest': prefixDigest,
  };
  factory MessageAnchor.fromJson(Map<String, dynamic> json) => MessageAnchor(
    sessionId: json['sessionId'] as String,
    messageId: json['messageId'] as String,
    variantId: json['variantId'] as String?,
    prefixDigest: json['prefixDigest'] as String,
  );
}

/// Called only at mutation boundaries, never by serialization or UI getters.
List<ChatMessage> assignMessageIds(List<ChatMessage> messages) {
  final used = <String>{};
  String unique(Set<String> ids) {
    var id = newStoryId();
    while (!ids.add(id)) {
      id = newStoryId();
    }
    return id;
  }

  return messages.map((message) {
    final id = message.id.isNotEmpty && used.add(message.id)
        ? message.id
        : unique(used);
    final variants = <String>{};
    return message.copyWith(
      id: id,
      variants: message.variants
          .map(
            (v) => v.copyWith(
              id: v.id.isNotEmpty && variants.add(v.id)
                  ? v.id
                  : unique(variants),
            ),
          )
          .toList(),
    );
  }).toList();
}
