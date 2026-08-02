import 'dart:async';

import '../../models/qq_contact_binding.dart';
import '../../models/qq_diagnostic_event.dart';
import '../../models/qq_integration_settings.dart';
import '../../models/unified_qq_message.dart';
import '../../models/unified_qq_reply.dart';
import '../local_storage_service.dart';
import 'background_character_chat_service.dart';
import 'qq_command_service.dart';
import 'qq_contact_queue.dart';
import 'qq_diagnostic_service.dart';
import 'qq_message_debouncer.dart';
import 'qq_message_deduplicator.dart';

enum QqProcessStatus { ignored, reply, error }

class QqProcessResult {
  const QqProcessResult._({
    required this.status,
    this.reply,
    this.reason = '',
    this.message = '',
  });

  const QqProcessResult.ignored([String reason = ''])
    : this._(status: QqProcessStatus.ignored, reason: reason);

  const QqProcessResult.reply(UnifiedQqReply reply)
    : this._(status: QqProcessStatus.reply, reply: reply);

  const QqProcessResult.error(String message)
    : this._(status: QqProcessStatus.error, message: message);

  final QqProcessStatus status;
  final UnifiedQqReply? reply;
  final String reason;
  final String message;

  String get text => reply?.text ?? '';

  Map<String, dynamic> toNativeJson() => switch (status) {
    QqProcessStatus.ignored => {'status': 'ignored'},
    QqProcessStatus.reply => {
      'status': 'reply',
      'text': reply!.text,
      'bindingId': reply!.bindingId,
      'sessionId': reply!.sessionId,
    },
    QqProcessStatus.error => {'status': 'error', 'message': message},
  };
}

class QqMessageProcessor {
  QqMessageProcessor({
    required LocalStorageService storage,
    required QqCharacterReplyService chatService,
    QqMessageDeduplicator? deduplicator,
    QqMessageDebouncer? debouncer,
    QqContactQueue? queue,
  }) : _storage = storage,
       _chatService = chatService,
       _deduplicator = deduplicator ?? QqMessageDeduplicator(),
       _debouncer =
           debouncer ??
           QqMessageDebouncer(mergeWindow: const Duration(milliseconds: 1800)),
       _queue = queue ?? QqContactQueue(maxConcurrent: 2),
       _commands = QqCommandService(storage),
       _diagnostics = QqDiagnosticService(storage);

  final LocalStorageService _storage;
  final QqCharacterReplyService _chatService;
  final QqMessageDeduplicator _deduplicator;
  final QqMessageDebouncer _debouncer;
  final QqContactQueue _queue;
  final QqCommandService _commands;
  final QqDiagnosticService _diagnostics;
  final _pendingResults = <String, Completer<QqProcessResult>>{};
  var _paused = false;

  bool get paused => _paused;
  int get queuedCount => _queue.waiting;
  void setPaused(bool value) => _paused = value;

  Future<QqProcessResult> handle(
    UnifiedQqMessage message, {
    required QqIntegrationSettings settings,
  }) async {
    if (!settings.enabled ||
        settings.mode == QqIntegrationMode.disabled ||
        settings.mode != message.source ||
        _paused) {
      return const QqProcessResult.ignored('disabled');
    }
    final text = message.text.trim();
    if (text.isEmpty) return const QqProcessResult.ignored('empty');
    final normalized = message.copyWith(text: text);
    final binding = await _findBinding(normalized);
    if (binding == null) {
      await _diagnostics.record(
        settings: settings,
        mode: message.source,
        eventType: QqDiagnosticEventType.ignoredUnknownContact,
        success: true,
        messageId: message.messageId,
      );
      return const QqProcessResult.ignored('unknownContact');
    }
    if (_deduplicator.isDuplicate(normalized, now: message.timestamp)) {
      await _diagnostics.record(
        settings: settings,
        mode: message.source,
        eventType: QqDiagnosticEventType.ignoredDuplicate,
        success: true,
        contactDisplayName: binding.displayName,
        messageId: message.messageId,
      );
      return const QqProcessResult.ignored('duplicate');
    }

    final isCommand = QqCommandService.isCommand(text);
    if (text == '/继续' || (binding.enabled && isCommand)) {
      _debouncer.flush(message.externalUserId);
      return _queue.run(
        message.externalUserId,
        () => _handleCommand(text, binding),
      );
    }
    if (!binding.enabled) return const QqProcessResult.ignored('bindingPaused');
    if (settings.isQuietAt(message.timestamp)) {
      await _diagnostics.record(
        settings: settings,
        mode: message.source,
        eventType: QqDiagnosticEventType.ignoredQuietHours,
        success: true,
        contactDisplayName: binding.displayName,
        messageId: message.messageId,
      );
      return const QqProcessResult.ignored('quietHours');
    }

    final completer = Completer<QqProcessResult>();
    final previous = _pendingResults[message.externalUserId];
    if (previous != null && !previous.isCompleted) {
      previous.complete(const QqProcessResult.ignored('merged'));
    }
    _pendingResults[message.externalUserId] = completer;
    _debouncer.add(normalized, (merged) async {
      final result = await _queue.run(
        merged.externalUserId,
        () => _handleMerged(merged, settings),
      );
      final current = _pendingResults.remove(merged.externalUserId);
      if (current != null && !current.isCompleted) current.complete(result);
    });
    return completer.future;
  }

  Future<QqProcessResult> _handleMerged(
    UnifiedQqMessage message,
    QqIntegrationSettings settings,
  ) async {
    try {
      final binding = await _findBinding(message);
      if (binding == null || !binding.enabled) {
        return const QqProcessResult.ignored('bindingChanged');
      }
      final started = DateTime.now();
      await _diagnostics.record(
        settings: settings,
        mode: message.source,
        eventType: QqDiagnosticEventType.aiStarted,
        success: true,
        contactDisplayName: binding.displayName,
        messageId: message.messageId,
      );
      final reply = await _chatService.reply(
        binding: binding,
        message: message,
        settings: settings,
      );
      await _diagnostics.record(
        settings: settings,
        mode: message.source,
        eventType: QqDiagnosticEventType.aiCompleted,
        success: true,
        contactDisplayName: binding.displayName,
        messageId: message.messageId,
        durationMilliseconds: DateTime.now().difference(started).inMilliseconds,
        replyLength: reply.text.runes.length,
      );
      return QqProcessResult.reply(reply);
    } on Object catch (error) {
      final summary = error.toString();
      await _diagnostics.record(
        settings: settings,
        mode: message.source,
        eventType: QqDiagnosticEventType.replyFailed,
        success: false,
        messageId: message.messageId,
        errorCode: error.runtimeType.toString(),
        errorSummary: summary,
      );
      return QqProcessResult.error('QQ 自动回复失败，请查看诊断日志。');
    }
  }

  Future<QqProcessResult> _handleCommand(
    String command,
    QqContactBinding binding,
  ) async {
    try {
      final reply = await _commands.handle(command, binding);
      return reply == null
          ? const QqProcessResult.ignored('notCommand')
          : QqProcessResult.reply(reply);
    } on Object {
      return const QqProcessResult.error('QQ 命令处理失败，请查看诊断日志。');
    }
  }

  Future<QqContactBinding?> _findBinding(UnifiedQqMessage message) async {
    for (final binding in await _storage.loadQqContactBindings()) {
      if (binding.mode == message.source &&
          binding.externalUserId == message.externalUserId) {
        return binding;
      }
    }
    return null;
  }

  void dispose() {
    _debouncer.dispose();
    for (final completer in _pendingResults.values) {
      if (!completer.isCompleted) {
        completer.complete(const QqProcessResult.ignored('disposed'));
      }
    }
    _pendingResults.clear();
  }
}
