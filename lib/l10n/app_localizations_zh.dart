// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get save => '保存';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get retry => '重试';

  @override
  String get send => '发送';

  @override
  String get stop => '停止';

  @override
  String get reload => '重新加载';

  @override
  String get theaterReplyOnce => '让TA回复';

  @override
  String get theaterReplyOnceTooltip => '只让当前角色回复一次';

  @override
  String get theaterParticipantMissing => '角色不存在或已被移除';

  @override
  String get theaterParticipantDisabled => '该角色已禁用';

  @override
  String get theaterParticipantMuted => '该角色已被禁言';

  @override
  String chatCount(int count) {
    return '$count 条聊天';
  }

  @override
  String summarizingProgress(int current, int total) {
    return '正在总结 $current/$total';
  }

  @override
  String apiHttpError(int code) {
    return 'API HTTP 错误：$code';
  }

  @override
  String importResult(int succeeded, int failed) {
    return '导入成功 $succeeded 项，失败 $failed 项';
  }
}
