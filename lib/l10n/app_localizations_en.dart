// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get send => 'Send';

  @override
  String get stop => 'Stop';

  @override
  String get reload => 'Reload';

  @override
  String get theaterReplyOnce => 'Reply once';

  @override
  String get theaterReplyOnceTooltip => 'Only let this character reply once';

  @override
  String get theaterParticipantMissing =>
      'The character no longer exists or was removed';

  @override
  String get theaterParticipantDisabled => 'This character is disabled';

  @override
  String get theaterParticipantMuted => 'This character is muted';

  @override
  String chatCount(int count) {
    return '$count chats';
  }

  @override
  String summarizingProgress(int current, int total) {
    return 'Summarizing $current/$total';
  }

  @override
  String apiHttpError(int code) {
    return 'API HTTP error: $code';
  }

  @override
  String importResult(int succeeded, int failed) {
    return 'Imported $succeeded; $failed failed';
  }
}
