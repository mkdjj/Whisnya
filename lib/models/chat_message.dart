// The raw index remains private so the public getter can clamp it dynamically.
// ignore_for_file: prefer_initializing_formals

import 'chat_reply_variant.dart';

class ChatMessage {
  const ChatMessage({
    this.id = '',
    required this.role,
    required this.content,
    required this.time,
    this.innerVoice = '',
    this.reasoningContent = '',
    this.replyState = 'completed',
    this.endpointId,
    this.endpointName,
    this.model,
    this.variants = const [],
    int selectedVariantIndex = 0,
  }) : _selectedVariantIndex = selectedVariantIndex;

  final String id;
  final String role;
  final String content;
  final DateTime time;
  final String innerVoice;
  final String reasoningContent;
  final String replyState;
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
    final count = variantCount;
    return count == 0 ? 0 : _selectedVariantIndex.clamp(0, count - 1).toInt();
  }

  ChatReplyVariant? get selectedVariant {
    final target = _selectedVariantIndex < 0 ? 0 : _selectedVariantIndex;
    var index = 0;
    ChatReplyVariant? last;
    for (final variant in variants) {
      if (variant.content.trim().isEmpty) continue;
      last = variant;
      if (index++ == target) return variant;
    }
    return last;
  }

  String get effectiveContent => selectedVariant?.content ?? content;
  String get effectiveReasoningContent =>
      selectedVariant?.reasoningContent ?? reasoningContent;
  String get effectiveReplyState => selectedVariant?.replyState ?? replyState;
  String get effectiveInnerVoice {
    final selected = selectedVariant;
    return selected == null ? innerVoice : selected.innerVoice;
  }

  DateTime get effectiveTime => selectedVariant?.time ?? time;
  String? get effectiveEndpointId => selectedVariant?.endpointId ?? endpointId;
  String? get effectiveEndpointName =>
      selectedVariant?.endpointName ?? endpointName;
  String? get effectiveModel => selectedVariant?.model ?? model;
  int get variantCount {
    var count = 0;
    for (final variant in variants) {
      if (variant.content.trim().isNotEmpty) count++;
    }
    return count;
  }

  ChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? time,
    String? innerVoice,
    String? reasoningContent,
    String? replyState,
    bool clearInnerVoice = false,
    String? endpointId,
    String? endpointName,
    String? model,
    List<ChatReplyVariant>? variants,
    int? selectedVariantIndex,
  }) => ChatMessage(
    id: id ?? this.id,
    role: role ?? this.role,
    content: content ?? this.content,
    time: time ?? this.time,
    innerVoice: clearInnerVoice ? '' : innerVoice ?? this.innerVoice,
    reasoningContent: reasoningContent ?? this.reasoningContent,
    replyState: replyState ?? this.replyState,
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
      id: json['id'] is String ? json['id'] as String : '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      innerVoice: json['innerVoice'] as String? ?? '',
      reasoningContent: json['reasoningContent'] is String
          ? json['reasoningContent'] as String
          : '',
      replyState: json['replyState'] == 'interrupted'
          ? 'interrupted'
          : 'completed',
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
      'id': id,
      'role': role,
      'content': effectiveContent,
      'reasoningContent': effectiveReasoningContent,
      'replyState': effectiveReplyState == 'interrupted'
          ? 'interrupted'
          : 'completed',
      'time': effectiveTime.toIso8601String(),
      if (effectiveInnerVoice.trim().isNotEmpty)
        'innerVoice': effectiveInnerVoice,
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
