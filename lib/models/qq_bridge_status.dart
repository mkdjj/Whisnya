enum QqConnectionState {
  stopped,
  connecting,
  connected,
  reconnecting,
  authenticationFailed,
  error,
}

class QqBridgeStatus {
  const QqBridgeStatus({
    this.foregroundService = false,
    this.paused = false,
    this.connection = QqConnectionState.stopped,
    this.accountId = '',
    this.nickname = '',
    this.enabledContacts = 0,
    this.queuedMessages = 0,
    this.lastMessageAt,
    this.lastReplyAt,
    this.lastError = '',
  });

  final bool foregroundService;
  final bool paused;
  final QqConnectionState connection;
  final String accountId;
  final String nickname;
  final int enabledContacts;
  final int queuedMessages;
  final DateTime? lastMessageAt;
  final DateTime? lastReplyAt;
  final String lastError;
}
