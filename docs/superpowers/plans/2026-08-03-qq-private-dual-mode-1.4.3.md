# Whisnya 1.4.3 QQ 私聊双模式实施计划

> 依据 `F:\Whisnya_1.5.0_QQ私聊双模式_Codex完整方案.txt`，目标版本按用户最新指示覆盖为 1.4.3+21。每个行为先写会失败的测试，再写最小实现并回归。

## 阶段 0：保护与基线

- 保存既有热修复到备份分支并建立功能分支。
- 运行原有 Flutter 全测试，记录基线。
- 不 reset、不 clean、不删除旧测试。

## 阶段 1：模型与存储

- 新增 QQ mode、settings、binding、message、reply、status、diagnostic 模型测试。
- 覆盖默认值、范围收敛、JSON round trip、String ID、contact key、诊断脱敏。
- 实现模型与异常类型。
- 扩展 StoragePaths 和 LocalStorageService：设置、binding 锁内 CRUD、诊断 200 条、安全 token。
- 扩展备份验证/导入导出：包含设置与 binding，明确排除 token。

## 阶段 2：消息处理核心

- 为去重、通知弱去重、合并、命令不合并、数量/字数限制写失败测试。
- 为联系人严格串行、联系人间并行、全局最大并发 2 写失败测试。
- 为 rune 安全截断、优先边界拆分、通知单条回复写失败测试。
- 实现 deduplicator、debouncer、contact queue、splitter、diagnostic 与命令服务。

## 阶段 3：公共角色聊天

- 使用临时本地存储和 fake AiGateway 测试独立 session、无 openingMessage、用户/助手保存、记忆隔离、角色引用世界书、总结和 `/新对话`。
- 实现 BackgroundCharacterChatService，严格复用现有聊天、记忆、世界书、总结和 AI 组件。
- 实现 binding 重新读取、endpoint 校验、timeout、lastUsedAt 与 AI 用量。

## 阶段 4：OneBot

- 测试私聊/群聊过滤、超大 String ID、数组 text、非文本忽略。
- 用 Dart HttpServer+WebSocket 测试鉴权 header、get_login_info、echo、动作失败/超时和断线取消。
- 测试重连序列、稳定重置、认证失败不重连、安全 URL 校验。
- 实现 parser、action client、client 与 reconnect policy。

## 阶段 5：Android 后台基础

- 新增单 FlutterEngine holder、Application、channels 与 remoteMessaging 前台服务。
- 修改 MainActivity 共用 engine 且不随 Activity 销毁。
- 修改 Manifest 权限、服务与 QQ queries，保留 ACTION_PROCESS_TEXT。
- 建立 Flutter native bridge 和 runtime channel handler。
- 构建 Android debug 及早发现 Kotlin/Manifest 问题。

## 阶段 6：通知快捷回复

- 为包名、ongoing、group summary、群聊、系统通知、联系人/文本提取写 Kotlin 测试。
- 实现 NotificationListener、捕获 60 秒、pending context TTL 3 分钟/最多 20。
- 实现 RemoteInput 查找优先级、发送、异常捕获以及成功后清除 context。
- 保证捕获、未知联系人和非 QQ 通知不回复。

## 阶段 7：无障碍兜底

- 为标题精确规范化、输入框/发送按钮选择和最多点击一次写 Kotlin 测试。
- 实现内存 pending reply store（TTL 30 秒、最多 5）。
- 实现 contentIntent 打开、解锁检查、严格标题复核、ACTION_SET_TEXT、单次点击、可选单次返回。
- 实现锁屏提示和所有安全中止条件；不使用剪贴板、坐标或手势。

## 阶段 8：统一 runtime

- 测试模式互斥、白名单、命令、跨午夜静默时段、陌生人静默、单消息失败不中止服务。
- 实现 QqMessageProcessor 与 QqIntegrationRuntime，把 OneBot 和通知送入相同公共管线。
- 实现启动前检查、暂停/继续/停止、切换模式清理、状态事件和回复传输。

## 阶段 9：设置与文案

- Widget 测试 Android 入口、Windows 提示、模式互斥、风险警告、权限披露、binding CRUD 和启动校验。
- 实现 QQ 设置、bindings、编辑、诊断、Termux 帮助和通知帮助页面。
- 在设置主页面“连续气泡输出”后插入入口。
- 增加中英文 i18n 文案，不硬编码平台通道调用到 Windows。

## 阶段 10：发布准备与验证

- 修改 pubspec 为 1.4.3+21，更新中英文 README。
- 扫描 TODO/TBD、敏感 token/key、构建产物和意外绝对路径。
- 运行：pub get、format check、analyze、flutter test、Gradle test、Android debug、Windows debug、diff check。
- 生成 arm64-v8a release 小包体并计算 SHA-256。
- 提交实现；确认工作区状态与备份分支。
- 只有所有文档要求完成且验证结果可交付时，安排延时关机。
