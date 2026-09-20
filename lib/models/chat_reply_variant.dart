class ChatReplyVariant {
  const ChatReplyVariant({
    required this.content,
    required this.time,
    this.innerVoice = '',
    this.reasoningContent = '',
    this.replyState = 'completed',
    this.endpointId,
    this.endpointName,
    this.model,
  });

  final String content;
  final DateTime time;
  final String innerVoice;
  final String reasoningContent;
  final String replyState;
  final String? endpointId;
  final String? endpointName;
  final String? model;

  ChatReplyVariant copyWith({
    String? content,
    DateTime? time,
    String? innerVoice,
    String? reasoningContent,
    String? replyState,
    bool clearInnerVoice = false,
    String? endpointId,
    String? endpointName,
    String? model,
  }) => ChatReplyVariant(
    content: content ?? this.content,
    time: time ?? this.time,
    innerVoice: clearInnerVoice ? '' : innerVoice ?? this.innerVoice,
    reasoningContent: reasoningContent ?? this.reasoningContent,
    replyState: replyState ?? this.replyState,
    endpointId: endpointId ?? this.endpointId,
    endpointName: endpointName ?? this.endpointName,
    model: model ?? this.model,
  );

  factory ChatReplyVariant.fromJson(Map<String, dynamic> json) =>
      ChatReplyVariant(
        content: json['content'] is String ? json['content'] as String : '',
        reasoningContent: json['reasoningContent'] is String
            ? json['reasoningContent'] as String
            : '',
        replyState: json['replyState'] == 'interrupted'
            ? 'interrupted'
            : 'completed',
        time:
            DateTime.tryParse(
              json['time'] is String ? json['time'] as String : '',
            ) ??
            DateTime.now(),
        innerVoice: json['innerVoice'] is String
            ? json['innerVoice'] as String
            : '',
        endpointId: json['endpointId'] is String
            ? json['endpointId'] as String
            : json['provider'] is String
            ? json['provider'] as String
            : null,
        endpointName: json['endpointName'] is String
            ? json['endpointName'] as String
            : null,
        model: json['model'] is String ? json['model'] as String : null,
      );

  Map<String, dynamic> toJson() => {
    'content': content,
    'reasoningContent': reasoningContent,
    'replyState': replyState == 'interrupted' ? 'interrupted' : 'completed',
    'time': time.toIso8601String(),
    if (innerVoice.trim().isNotEmpty) 'innerVoice': innerVoice,
    if (endpointId != null) 'endpointId': endpointId,
    if (endpointName != null) 'endpointName': endpointName,
    if (model != null) 'model': model,
  };
}
