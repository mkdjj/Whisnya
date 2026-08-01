class ChatReplyVariant {
  const ChatReplyVariant({
    required this.content,
    required this.time,
    this.endpointId,
    this.endpointName,
    this.model,
  });

  final String content;
  final DateTime time;
  final String? endpointId;
  final String? endpointName;
  final String? model;

  ChatReplyVariant copyWith({
    String? content,
    DateTime? time,
    String? endpointId,
    String? endpointName,
    String? model,
  }) => ChatReplyVariant(
    content: content ?? this.content,
    time: time ?? this.time,
    endpointId: endpointId ?? this.endpointId,
    endpointName: endpointName ?? this.endpointName,
    model: model ?? this.model,
  );

  factory ChatReplyVariant.fromJson(Map<String, dynamic> json) =>
      ChatReplyVariant(
        content: json['content'] is String ? json['content'] as String : '',
        time:
            DateTime.tryParse(
              json['time'] is String ? json['time'] as String : '',
            ) ??
            DateTime.now(),
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
    'time': time.toIso8601String(),
    if (endpointId != null) 'endpointId': endpointId,
    if (endpointName != null) 'endpointName': endpointName,
    if (model != null) 'model': model,
  };
}
