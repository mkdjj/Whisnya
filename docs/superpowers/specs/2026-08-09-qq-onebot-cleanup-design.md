# QQ OneBot 单模式清理与优化设计

## 目标

在彻底移除通知监听、RemoteInput 和无障碍回复后，将 QQ 接入收敛为唯一的 Termux + NapCat / OneBot 本地 Bridge，并修复当前无效的回复分片设置，减少 Android 前台通知的重复刷新。

## 兼容策略

- `QqIntegrationMode` 和持久化 `mode` 暂时保留，用于把旧 `notification` 配置安全降级为关闭；设置界面不再显示只有一个选项的模式选择器。
- `/v1/qq/message` 成功响应继续返回完整的 `reply`，并新增 `replies` 分片数组。旧 Sidecar 仍发送完整回复，新 Sidecar 优先逐条发送 `replies`。
- 旧通知诊断类型统一读取为 `legacyUnsupported`，不再误报为 `replyFailed`。
- `POST_NOTIFICATIONS` 与 QQ 前台服务保留，因为 OneBot 后台 Bridge 仍依赖常驻通知。

## 实现边界

- 删除 App 内不再使用的直连 OneBot WebSocket 客户端、Host/Port/WSS 配置及旧 Access Token 存储接口。
- 原生配置只保留前台通知真正读取的字段；配置未变化时不刷新通知。
- Sidecar 的 30 秒状态心跳只更新 Flutter 状态；只有前台通知可见信息变化时才同步原生配置。
- 前台通知根据运行状态只显示“暂停”或“继续”，并始终保留“停止”。
- 修正中文 README 的 1.5.1 版本与产物名称。

## 验证

- Dart：模型、HTTP Bridge、回复分片、运行时与设置界面相关测试。
- TypeScript：Sidecar 单条兼容与多分片顺序发送测试，以及 TypeScript 构建。
- Kotlin：原生配置变化检测单元测试。
- 最后执行 Flutter 静态分析；不在本轮生成发布包。
