import '../../../models/qq_integration_settings.dart';
import '../../../models/unified_qq_message.dart';

class OneBotEventParser {
  const OneBotEventParser._();

  static UnifiedQqMessage? parse(Object? event, {DateTime? receivedAt}) {
    if (event is! Map<String, dynamic> ||
        event['post_type'] != 'message' ||
        event['message_type'] != 'private') {
      return null;
    }
    final text = _text(event).trim();
    final userId = _id(event['user_id']);
    final messageId = _id(event['message_id']);
    if (text.isEmpty || userId.isEmpty || messageId.isEmpty) return null;
    final sender = event['sender'];
    final senderMap = sender is Map<String, dynamic>
        ? sender
        : const <String, dynamic>{};
    final displayName = _firstNonEmpty([
      senderMap['card'],
      senderMap['nickname'],
      userId,
    ]);
    final rawTime = event['time'];
    final timestamp = rawTime is num
        ? DateTime.fromMillisecondsSinceEpoch(
            rawTime.toInt() * 1000,
            isUtc: true,
          ).toLocal()
        : receivedAt ?? DateTime.now();
    return UnifiedQqMessage(
      source: QqIntegrationMode.oneBot,
      messageId: messageId,
      externalUserId: userId,
      senderDisplayName: displayName,
      text: text,
      timestamp: timestamp,
      rawConversationTitle: displayName,
    );
  }

  static String _text(Map<String, dynamic> event) {
    final message = event['message'];
    if (message is String) {
      final raw = event['raw_message'];
      return raw is String ? raw : message;
    }
    if (message is! List) return '';
    final buffer = StringBuffer();
    for (final segment in message.whereType<Map<String, dynamic>>()) {
      if (segment['type'] != 'text') continue;
      final data = segment['data'];
      if (data is! Map<String, dynamic>) continue;
      final text = data['text'];
      if (text is String) buffer.write(text);
    }
    return buffer.toString();
  }

  static String _id(Object? value) => value?.toString().trim() ?? '';

  static String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }
}
