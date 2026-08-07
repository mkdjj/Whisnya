import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_i18n.dart';

class QqTermuxHelpScreen extends StatelessWidget {
  const QqTermuxHelpScreen({super.key});

  static const environmentCommand =
      'pkg update -y\npkg install -y nodejs git nano curl';
  static const napcatCommand =
      'curl -o napcat.termux.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.termux.sh && bash napcat.termux.sh';
  static const bridgeCommand =
      'git clone https://github.com/mkdjj/Whisnya.git\n'
      'cd Whisnya/qq_bridge\n'
      'npm install\n'
      'cp config.example.json config.json\n'
      'nano config.json\n'
      'npm run build\n'
      'npm start';

  @override
  Widget build(BuildContext context) {
    const steps = [
      '安装 Termux。',
      '安装 Node.js、git、nano 和 curl。',
      '安装 NapCat，并登录一个不重要的 QQ 小号。',
      '在 NapCat WebUI 启用 OneBot 11 正向 WebSocket，地址使用 ws://127.0.0.1:3001。',
      'clone Whisnya，进入 qq_bridge 并安装依赖。',
      '复制 Whisnya 设置页中的 Bridge Token，粘贴到 config.json 的 whisnya.token。',
      '在 config.json 填写 NapCat OneBot URL 和 access token。',
      '构建并启动 qq_bridge，再回到 Whisnya 查看 Bridge 与 NapCat 状态。',
      '在 Whisnya 添加白名单联系人、绑定角色并启动 QQ 自动回复。',
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
          for (var index = 0; index < steps.length; index++)
            ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(context.t(steps[index])),
            ),
          const SizedBox(height: 8),
          _command(context, context.t('安装 Termux 依赖'), environmentCommand),
          _command(context, context.t('安装 NapCat'), napcatCommand),
          _command(context, context.t('安装并启动 QQ Bridge'), bridgeCommand),
        ],
      ),
    );
  }

  Widget _command(BuildContext context, String title, String command) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SelectableText(command),
      TextButton.icon(
        onPressed: () => Clipboard.setData(ClipboardData(text: command)),
        icon: const Icon(Icons.copy_outlined),
        label: Text(context.t('复制命令')),
      ),
      const SizedBox(height: 16),
    ],
  );
}
