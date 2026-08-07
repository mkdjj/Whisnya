# Whisnya QQ 私聊接入

Whisnya 1.5.0 提供两种互斥的 QQ 私聊文字接入方式。两种方式均为非官方接入，可能因 QQ 或 NapCat 更新而失效，也可能带来账号风险。只建议使用不重要的小号。

## Termux / NapCat Sidecar

链路为：QQ -> NapCat -> OneBot v11 正向 WebSocket -> Termux 中的 `qq_bridge` -> Whisnya 本地 HTTP -> 公共聊天核心 -> `qq_bridge` -> NapCat -> QQ。

Whisnya 不再由 Flutter 直接连接 NapCat。Node.js 20+ Sidecar 负责 WebSocket 生命周期、随机 `echo` action 对应、15 秒 action 超时、断开时清理 pending action、1/2/5/10/30 秒重连、30 分钟/1000 条内存去重和脱敏日志。第一版只处理私聊文字；群聊、图片、语音、视频、文件和其他非文字段均静默忽略。

白名单以 Whisnya 联系人绑定为唯一来源。Sidecar 启动及之后每 60 秒读取一次，读取失败会清空内存白名单，不回复任何联系人。状态每 30 秒上报一次，Whisnya 连续 90 秒收不到心跳后显示 Bridge 离线。

## 本地 API

Whisnya 仅在 `127.0.0.1:17891` 启动 `dart:io` HttpServer，不监听局域网地址。首次进入 QQ 设置时生成 32 个随机字节的 Bridge Token，使用安全存储保存，不写普通配置文件、不进入备份。除健康检查外，请求必须同时带：

```text
Authorization: Bearer <Bridge Token>
X-Whisnya-Bridge-Version: 1
```

端点：

- `GET /health`：只返回服务名和协议版本，不返回 Token、联系人或聊天信息。
- `GET /v1/qq/config`：返回开关和允许的 QQ ID 字符串列表。
- `POST /v1/qq/message`：接收标准化私聊文字；未绑定或已停用返回 204，成功返回回复及 session/binding ID，AI 失败返回 500。
- `POST /v1/qq/status`：接收 NapCat 连接状态、QQ 账号/昵称、最后消息时间和错误摘要。状态只放内存。

请求体必须为 `application/json`，最大 64KB。鉴权失败返回 401，协议不支持返回 426，超限返回 413。

## 通知监听模式

Android `NotificationListenerService` 只处理配置包名（默认 `com.tencent.mobileqq`）的文字通知，过滤 ongoing 和 group summary，并优先解析 MessagingStyle、会话标题、标题、正文及大文本。联系人通过“捕获下一条 QQ 私聊通知”生成，捕获窗口为 60 秒，捕获消息不会触发回复。

回复优先使用通知 action 的 `RemoteInput`，成功时不打开 QQ。只有 RemoteInput 不存在或失败且用户明确开启无障碍兜底时，才通过原通知的 `contentIntent` 打开会话。无障碍会核对标题，使用 `ACTION_SET_TEXT`，再次核对后最多点击一次可见、启用且可点击的“发送/Send”按钮；锁屏、超时或无法确认目标时终止。

App 恢复和原生配置更新时会请求系统重新绑定通知监听服务，避免每次重新打开 App 都需要手动关闭再开启通知读取权限。

## 公共聊天核心

两种模式最终都进入 `BackgroundCharacterChatService` 和 `QqMessageProcessor`，共同使用联系人绑定、独立 `ChatSession`、角色、长期记忆、当前会话记忆、角色引用世界书、历史总结、PromptBuilder、AI 请求、消息保存、去重、连续消息合并、按联系人排队和最多 200 条脱敏诊断。Termux 与通知模式不会同时运行，也不会各自复制一套聊天逻辑。

## 手工验收

1. Termux 模式：启动 Whisnya、本地 Bridge 和 NapCat，确认 Bridge 在线、NapCat 已连接、QQ 账号和心跳均显示正常。
2. 用白名单联系人发送两条连续私聊，确认只生成一次合并回复；陌生联系人和重复 message ID 不应回复。
3. 停止 Whisnya、填写错误 Token、停止 NapCat，再分别确认 Sidecar 不向 QQ 发送内部错误且会恢复重连。
4. 通知模式：授权后捕获联系人，重开 App，确认无需重新切换通知读取权限即可继续收到通知。
5. 分别验证 RemoteInput 成功、RemoteInput 不可用且无障碍关闭、无障碍开启但标题不匹配、锁屏四种情况。
6. 确认 QQ 对话写入绑定角色的独立会话，并能使用记忆、世界书和历史总结。

真实 QQ、Termux、NapCat 和不同 QQ 版本的通知/无障碍行为必须在 Android 真机上验收。自动化测试不能替代这部分兼容性验证。

参考来源和固定提交见 [`qq-reference-sources.md`](qq-reference-sources.md)，许可证全文见 [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。
