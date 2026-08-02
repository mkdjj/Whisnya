import 'package:flutter/material.dart';

import '../../utils/app_i18n.dart';

class QqNotificationHelpScreen extends StatelessWidget {
  const QqNotificationHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('QQ 通知监听说明'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.t('Whisnya 只处理你通过通知捕获并明确绑定的 QQ 私聊联系人。')),
          const SizedBox(height: 12),
          Text(context.t('回复优先使用通知自带的快捷回复，成功时不会打开 QQ。')),
          const SizedBox(height: 12),
          Text(context.t('只有快捷回复不存在或失败，并且你明确开启无障碍兜底后，才会通过原通知打开对应会话。')),
          const SizedBox(height: 12),
          Text(
            context.t(
              '无障碍会精确核对联系人标题，使用 ACTION_SET_TEXT 填写并只点击一次发送；锁屏、标题不符或无法确认目标时绝不发送。',
            ),
          ),
          const SizedBox(height: 12),
          Text(context.t('通知内容会保存到本地聊天记录，并发送给你配置的 AI API。诊断日志不保存消息原文。')),
        ],
      ),
    );
  }
}
