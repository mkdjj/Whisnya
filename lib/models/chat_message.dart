// The raw index remains private so the public getter can clamp it dynamically.
// ignore_for_file: prefer_initializing_formals

import 'chat_reply_variant.dart';

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    required this.time,
    this.endpointId,
    this.endpointName,
    this.model,
    this.variants = const [],
    int selectedVariantIndex = 0,
  }) : _selectedVariantIndex = selectedVariantIndex;

  final String role;
  final String content;
  final DateTime time;
  final String? endpointId;
  final String? endpointName;
  final String? model;
  final List<ChatReplyVariant> variants;
  final int _selectedVariantIndex;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  List<ChatReplyVariant> get _validVariants =>
      variants.where((variant) => variant.content.trim().isNotEmpty).toList();

  int get selectedVariantIndex {
    final count = _validVariants.length;
    return count == 0 ? 0 : _selectedVariantIndex.clamp(0, count - 1).toInt();
  }

  ChatReplyVariant? get selectedVariant {
    final validVariants = _validVariants;
    return validVariants.isEmpty ? null : validVariants[selectedVariantIndex];
  }

  String get effectiveContent => selectedVariant?.content ?? content;
  DateTime get effectiveTime => selectedVariant?.time ?? time;
  String? get effectiveEndpointId => selectedVariant?.endpointId ?? endpointId;
  String? get effectiveEndpointName =>
      selectedVariant?.endpointName ?? endpointName;
  String? get effectiveModel => selectedVariant?.model ?? model;
  int get variantCount => _validVariants.length;

  ChatMessage copyWith({
    String? role,
    String? content,
    DateTime? time,
    String? endpointId,
    String? endpointName,
    String? model,
    List<ChatReplyVariant>? variants,
    int? selectedVariantIndex,
  }) => ChatMessage(
    role: role ?? this.role,
    content: content ?? this.content,
    time: time ?? this.time,
    endpointId: endpointId ?? this.endpointId,
    endpointName: endpointName ?? this.endpointName,
    model: model ?? this.model,
    variants: variants ?? this.variants,
    selectedVariantIndex: selectedVariantIndex ?? _selectedVariantIndex,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawVariants = json['variants'];
    final variants = <ChatReplyVariant>[];
    if (rawVariants is List) {
      for (final item in rawVariants.whereType<Map<dynamic, dynamic>>()) {
        try {
          final variant = ChatReplyVariant.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (variant.content.trim().isNotEmpty) variants.add(variant);
        } on Object {
          // A malformed candidate must not hide the legacy top-level reply.
        }
      }
    }
    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      endpointId: json['endpointId'] as String? ?? json['provider'] as String?,
      endpointName: json['endpointName'] as String?,
      model: json['model'] as String?,
      variants: variants,
      selectedVariantIndex: json['selectedVariantIndex'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final selected = selectedVariant;
    return {
      'role': role,
      'content': effectiveContent,
      'time': effectiveTime.toIso8601String(),
      if (effectiveEndpointId != null) 'endpointId': effectiveEndpointId,
      if (effectiveEndpointName != null) 'endpointName': effectiveEndpointName,
      if (effectiveModel != null) 'model': effectiveModel,
      if (selected != null) ...{
        'variants': _validVariants.map((variant) => variant.toJson()).toList(),
        'selectedVariantIndex': selectedVariantIndex,
      },
    };
  }
}
