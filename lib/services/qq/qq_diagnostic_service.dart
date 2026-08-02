import '../../models/qq_diagnostic_event.dart';
import '../../models/qq_integration_settings.dart';
import '../local_storage_service.dart';

class QqDiagnosticService {
  const QqDiagnosticService(this.storage);

  final LocalStorageService storage;

  Future<void> record({
    required QqIntegrationSettings settings,
    required QqIntegrationMode mode,
    required QqDiagnosticEventType eventType,
    required bool success,
    String contactDisplayName = '',
    String messageId = '',
    String transport = '',
    int durationMilliseconds = 0,
    int replyLength = 0,
    String errorCode = '',
    String errorSummary = '',
  }) async {
    if (!settings.diagnosticLoggingEnabled) return;
    await storage.appendQqDiagnosticEvent(
      QqDiagnosticEvent(
        time: DateTime.now(),
        mode: mode,
        contactDisplayName: contactDisplayName,
        messageIdSuffix: messageId,
        eventType: eventType,
        success: success,
        transport: transport,
        durationMilliseconds: durationMilliseconds,
        replyLength: replyLength,
        errorCode: errorCode,
        errorSummary: errorSummary,
      ),
    );
  }
}
