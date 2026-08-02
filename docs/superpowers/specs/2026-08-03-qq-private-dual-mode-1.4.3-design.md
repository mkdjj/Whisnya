# Whisnya 1.4.3 QQ 私聊双模式设计

## 目标与边界

Whisnya 1.4.3 在 Android 增加两种互斥的 QQ 私聊入口：NapCat/OneBot 11 正向 WebSocket，以及 QQ 通知监听。两种入口只负责收发，统一进入同一套白名单、去重、合并、联系人队列、角色聊天、记忆、世界书、总结、诊断和错误处理。Windows 保持可编译、可运行，并仅展示 Android 支持说明。

第一版只处理一对一文字私聊。群聊、媒体消息、主动定时发送、多账号、Root/Hook/ADB、坐标点击、剪贴板输入、开机自启和 Google Play 发布均不在范围内。

## 工作区保护

原有聊天生成交互热修复先提交到 `codex/backup-before-1.4.3-qq`，功能开发在 `codex/qq-private-dual-mode-1.4.3` 进行。禁止 reset、clean 或覆盖原改动。

## 公共 Dart 核心

`UnifiedQqMessage` 是两个入口的唯一输入，`UnifiedQqReply` 是唯一输出。`QqMessageProcessor` 按以下顺序处理：命令前置判断、总开关/暂停、白名单、去重、静默时段、合并、联系人串行队列、全局双并发限制、`BackgroundCharacterChatService`、回复截断和传输。

联系人 binding 保存模式、外部字符串 ID、显示名、角色和独立 ChatSession。保存时禁止两个 binding 复用同一 session。通知 contact key 由包名、规范化标题和 shortcut ID 计算，不能使用系统通知 key 作为永久 ID。

后台聊天服务只编排现有 `LocalStorageService`、`ChatSessionService`、`MemoryContextService`、`PromptBuilder`、`ChatSummaryService` 和 `AiGateway`。它先保存用户消息，再滚动总结和构建上下文，使用角色最新引用的世界书与对应 endpoint 非流式请求，最后保存助手消息、更新时间与 AI 用量。QQ session 从不插入 openingMessage。

## OneBot

使用 `dart:io WebSocket`。客户端连接前校验 URL：默认只允许 loopback，远程明文 ws 只有在明确开启危险选项后允许。token 只从安全存储读取并通过 Bearer header 发送。

事件解析只接受 `post_type=message` 且 `message_type=private`。所有 QQ ID 保持 String；数组消息只合并 text segment。Action 通过 UUID echo 对应 Completer，15 秒超时，断线取消全部 pending。自动重连退避为 1、2、5、10、30 秒，认证失败、配置错误、用户停止、模式切换或关闭总开关时不重连。

## Android 单 Engine 与后台

`WhisnyaApplication` 持有 `QqFlutterEngineHolder`。Activity 和前台服务使用同一个缓存 engine，Dart entrypoint 与插件只初始化一次，Activity 销毁不销毁 engine。用户主动启动 `remoteMessaging` 前台服务后才运行；服务 `START_STICKY`，但不做开机自启或绕过 force stop。

Flutter 与 Android 使用一个 MethodChannel 和一个 EventChannel。原生通知服务把消息交给同一 engine 中的 Dart runtime，等待异步结果后执行传输。任何原生通道或诊断都不得带 token、API key、完整消息、完整回复或原始 extras/OneBot JSON。

## 通知与无障碍

通知解析严格限制 QQ 包、非 ongoing、非 group summary、非群聊和非系统类通知。捕获模式持续 60 秒，下一条有效私聊通知只用于生成 contact key，不触发回复；捕获后的原文不持久化。

回复优先查找 RemoteInput。成功即删除内存 pending context，绝不进入无障碍。只有 RemoteInput 不存在/失败、用户明确开启兜底、服务可用、设备解锁、任务未过期、binding 仍启用且当前无发送任务时，才创建最多 5 条、TTL 30 秒的无障碍任务。

无障碍只通过原通知 contentIntent 打开 QQ；页面标题 trim 并合并空格后必须精确匹配 aliases。使用可见、启用、支持 ACTION_SET_TEXT 的 EditText；点击前再次核对标题，发送按钮只点击一次。禁止剪贴板、坐标和手势。锁屏、过期、标题不符或目标不明确时绝不发送。

## 设置、权限与诊断

设置主页面在“连续气泡输出”之后增加“QQ 私聊自动回复”。详情页包含风险、总开关、互斥模式、状态、运行控制、联系人绑定、模式配置、回复配置、权限披露、帮助和诊断。进入通知或无障碍系统设置前必须点击“我已了解”。

诊断最多保存 200 条，只保存时间、模式、联系人显示名、消息 ID 后缀、事件类型、结果、传输、耗时、回复长度和脱敏错误。备份包含设置和 bindings，不包含 OneBot token。

## 版本与验证

方案原标题中的 1.5.0 全部由用户明确覆盖为 `1.4.3+21`。完成后必须通过 pub get、Dart format、analyze、全部 Flutter 测试、Android Gradle 单元测试、Android debug build、Windows debug build、git diff check，并另外生成 Android arm64-v8a 小包体。任何失败都必须如实报告且不关机。
