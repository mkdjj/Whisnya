import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_i18n.dart';

class QqTermuxHelpScreen extends StatelessWidget {
  const QqTermuxHelpScreen({super.key});

  static const command =
      'curl -o napcat.termux.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.termux.sh && bash napcat.termux.sh';

  @override
  Widget build(BuildContext context) {
    const steps = [
      '安装 Termux。',
      '用下方命令安装 NapCat。',
      '登录一个不重要的 QQ 小号。',
      '在 WebUI 启用 OneBot 11 正向 WebSocket。',
      '绑定 127.0.0.1，设置端口和随机 token；不要监听 0.0.0.0。',
      '回到 Whisnya 测试连接。',
      '添加白名单联系人并绑定角色。',
      '启动 QQ 自动回复。',
      '为 Termux 和 Whisnya 关闭电池优化。',
      '手机重启后手动重新启动 Termux 和 Whisnya。',
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('NapCat / Termux 帮助'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.t('NapCat 是非官方 QQ 接入，可能掉线、失效或触发账号风险。')),
          const SizedBox(height: 16),
          SelectableText(command),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(const ClipboardData(text: command)),
              icon: const Icon(Icons.copy),
              label: Text(context.t('复制安装命令')),
            ),
          ),
          for (var index = 0; index < steps.length; index++)
            ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(context.t(steps[index])),
            ),
        ],
      ),
    );
  }
}
