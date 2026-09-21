import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import '../../utils/chat_text_export.dart';

/// Consumes the validated, persisted document; never a streaming draft.
String formatAutoStoryText(
  Map<String, dynamic> document, {
  bool includePlan = false,
  bool english = false,
}) {
  final config = document['config'] as Map<String, dynamic>;
  final actors = (document['actors'] as List).cast<Map<String, dynamic>>();
  final turns = (document['turns'] as List).cast<Map<String, dynamic>>();
  final events = (document['events'] as List).cast<Map<String, dynamic>>();
  String tr(String zh, String en) => english ? en : zh;
  String statusLabel(String? value) {
    const labels = {
      'draft': ('草稿', 'Draft'),
      'ready': ('准备就绪', 'Ready'),
      'running': ('演绎中', 'Running'),
      'paused': ('已暂停', 'Paused'),
      'completed': ('已完成', 'Completed'),
      'userPause': ('用户暂停', 'User paused'),
      'userStop': ('立即停止', 'Stopped'),
      'background': ('切到后台', 'Backgrounded'),
      'leftPage': ('离开页面', 'Left page'),
      'requestError': ('请求失败', 'Request failed'),
      'storageError': ('保存失败', 'Save failed'),
      'lengthLimit': ('达到轮数上限', 'Round limit reached'),
      'requestLimit': ('达到请求上限', 'Request limit reached'),
      'tokenLimit': ('达到 Token 阈值', 'Token limit reached'),
      'stagnation': ('剧情停滞', 'Story stalled'),
      'interruptedRestart': ('中断后恢复', 'Recovered after interruption'),
      'datasetChanged': ('数据集更换', 'Dataset changed'),
    };
    final label = labels[value];
    return label == null ? (value ?? '') : tr(label.$1, label.$2);
  }

  String speaker(String id) {
    final actor = actors.where((a) => a['actorId'] == id).firstOrNull;
    final name = actor?['name'] ?? id;
    return id == 'B' ? '$name${tr('（AI代演）', ' (AI portrayal)')}' : '$name';
  }

  final parts = <String>[
    config['title'] as String,
    for (final actor in actors)
      '${tr('演员', 'Actor')} ${actor['actorId']}：${speaker(actor['actorId'] as String)}',
    '${tr('状态', 'Status')}：${statusLabel(document['status'] as String?)}'
        '${document['pauseReason'] == null ? '' : ' / ${statusLabel(document['pauseReason'] as String?)}'}',
    '${tr('已完成轮数', 'Completed rounds')}：${turns.length ~/ 2} / ${config['plannedRounds']}',
  ];
  void scenesAfter(int ordinal) {
    for (final event in events) {
      if (event['kind'] == 'sceneTransition' &&
          event['status'] == 'applied' &&
          event['effectiveAfterOrdinal'] == ordinal) {
        parts.add('[${tr('场景', 'Scene')}] ${event['content']}');
      }
    }
  }

  scenesAfter(-1);
  for (final turn in turns) {
    final ordinal = turn['ordinal'] as int;
    final name = turn['source'] == 'manual'
        ? '${speaker(turn['speakerId'] as String)} · ${tr('本人接管', 'Manual takeover')}'
        : speaker(turn['speakerId'] as String);
    parts.add(
      '[${tr('第', 'Round ')}${ordinal ~/ 2 + 1}${tr('轮', '')} · $name]\n${turn['content']}',
    );
    scenesAfter(ordinal);
  }
  if (includePlan) {
    parts.add('[${tr('目标结局', 'Target ending')}]\n${config['targetEnding']}');
    for (final stage
        in (document['plan'] as List).cast<Map<String, dynamic>>()) {
      parts.add('[${stage['title']}]\n${stage['objective']}');
    }
  }
  return '${parts.join('\n\n')}\n';
}

Future<bool> exportAutoStoryText(
  Map<String, dynamic> document, {
  bool includePlan = false,
  bool english = false,
}) async {
  final title = (document['config'] as Map<String, dynamic>)['title'] as String;
  final result = await FilePicker.platform.saveFile(
    dialogTitle: english ? 'Export story' : '导出演绎',
    fileName: chatTextFileName(title, DateTime.now()),
    type: FileType.custom,
    allowedExtensions: const ['txt'],
    bytes: Uint8List.fromList(
      utf8.encode(
        formatAutoStoryText(
          document,
          includePlan: includePlan,
          english: english,
        ),
      ),
    ),
  );
  return result != null;
}
