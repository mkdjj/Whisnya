class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    required this.time,
    this.provider,
    this.model,
  });

  final String role;
  final String content;
  final DateTime time;
  final String? provider;
  final String? model;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  ChatMessage copyWith({
    String? role,
    String? content,
    DateTime? time,
    String? provider,
    String? model,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      time: time ?? this.time,
      provider: provider ?? this.provider,
      model: model ?? this.model,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      provider: json['provider'] as String?,
      model: json['model'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'time': time.toIso8601String(),
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
    };
  }
}
