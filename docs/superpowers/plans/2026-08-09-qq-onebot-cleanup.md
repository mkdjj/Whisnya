# QQ OneBot Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收敛 QQ 接入为单一的本地 OneBot Bridge，启用真实回复分片，并减少 Android 前台通知的无效刷新。

**Architecture:** Flutter 继续负责角色会话、AI 和分片决策，本地 HTTP API 同时返回兼容字段 `reply` 与新字段 `replies`；Termux Sidecar 顺序发送分片。Android 原生配置通过变化检测决定是否刷新前台通知。

**Tech Stack:** Flutter/Dart 3.12、Kotlin/Android、Node.js 20、TypeScript、Vitest。

## Global Constraints

- 版本保持 `1.5.1+23`。
- 保留 `POST_NOTIFICATIONS` 和前台服务。
- 不恢复通知监听、RemoteInput 或无障碍服务。
- 旧 `notification` 配置继续安全降级为关闭。
- HTTP Bridge 保持对旧 Sidecar 的 `reply` 字段兼容。

---

### Task 1: Bridge 回复分片协议

**Files:**
- Modify: `test/services/qq/local_bridge_server_test.dart`
- Modify: `lib/services/qq/local_bridge_server.dart`
- Modify: `lib/services/qq/qq_integration_runtime.dart`
- Modify: `qq_bridge/test/bridge-router.test.ts`
- Modify: `qq_bridge/src/bridge.ts`
- Modify: `qq_bridge/src/whisnya/types.ts`

**Interfaces:**
- Produces: HTTP JSON `{ reply: string, replies: string[], sessionId: string, bindingId: string }`。
- Consumes: `QqReplySplitter.splitOneBot(...)` 和旧 Sidecar 所需的完整 `reply`。

- [ ] **Step 1: 写入失败测试**

断言 Flutter Bridge 返回 `replies: ['hello', 'world']`，并断言 Sidecar 按数组顺序调用两次 `sendPrivateMessage`。

- [ ] **Step 2: 验证测试因缺少 `replies` 行为而失败**

Run: `flutter test test/services/qq/local_bridge_server_test.dart`

Run: `npm test -- --run test/bridge-router.test.ts`

- [ ] **Step 3: 实现最小兼容协议**

让 `LocalQqBridgeMessageResult.reply` 接收完整回复和分片；HTTP 同时输出二者；Sidecar 优先使用有效 `replies`，否则回退到 `[reply]`。

- [ ] **Step 4: 验证分片测试通过**

Run: `flutter test test/services/qq/local_bridge_server_test.dart test/services/qq/qq_reply_splitter_test.dart`

Run: `npm test -- --run test/bridge-router.test.ts`

### Task 2: 原生通知变化检测与动作简化

**Files:**
- Create: `android/app/src/test/kotlin/com/mkdjj/whisnya/qq/QqNativeConfigurationTest.kt`
- Modify: `android/app/src/main/kotlin/com/mkdjj/whisnya/qq/QqNativeConfiguration.kt`
- Modify: `android/app/src/main/kotlin/com/mkdjj/whisnya/qq/QqBridgeChannels.kt`
- Modify: `android/app/src/main/kotlin/com/mkdjj/whisnya/qq/QqBridgeForegroundService.kt`
- Modify: `lib/services/qq/qq_integration_runtime.dart`

**Interfaces:**
- Produces: `QqNativeConfiguration.update(values): Boolean`，仅可见状态变化时返回 `true`。

- [ ] **Step 1: 写入失败测试**

断言相同配置第二次更新返回 `false`，联系人、错误或运行状态变化返回 `true`。

- [ ] **Step 2: 验证 Kotlin 测试失败**

Run: `./gradlew app:testDebugUnitTest --tests com.mkdjj.whisnya.qq.QqNativeConfigurationTest`

- [ ] **Step 3: 实现变化检测和单次刷新**

原生通道只在 `update` 返回 `true` 时刷新；`ACTION_REFRESH` 只调用一次 `showNotification()`；前台动作根据 `runtimeActive` 二选一显示暂停或继续。Flutter 心跳仅在 `lastError` 变化时同步原生设置。

- [ ] **Step 4: 验证 Kotlin 与运行时测试通过**

Run: `./gradlew app:testDebugUnitTest --tests com.mkdjj.whisnya.qq.QqNativeConfigurationTest`

Run: `flutter test test/services/qq/qq_integration_runtime_test.dart`

### Task 3: 单模式死代码清理

**Files:**
- Delete: `lib/services/qq/onebot/onebot_action_client.dart`
- Delete: `lib/services/qq/onebot/onebot_client.dart`
- Delete: `lib/services/qq/onebot/onebot_event_parser.dart`
- Delete: `lib/services/qq/onebot/onebot_reconnect_policy.dart`
- Delete: `test/services/qq/onebot_client_test.dart`
- Delete: `test/services/qq/onebot_event_parser_test.dart`
- Modify: `lib/models/qq_integration_settings.dart`
- Modify: `lib/services/local_storage_service.dart`
- Modify: `lib/screens/settings/qq_integration_screen.dart`
- Modify: `lib/services/qq/android/qq_native_bridge.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/mkdjj/whisnya/qq/QqBridgeChannels.kt`

**Interfaces:**
- Preserves: `enabled`、`mode`、回复限制、静默时段和诊断配置的 JSON 兼容读取。

- [ ] **Step 1: 更新模型与界面测试预期**

断言旧直连字段不再序列化，设置页面不存在单模式选择器但仍显示 Bridge 配置。

- [ ] **Step 2: 删除仅测试引用的旧客户端及废弃配置**

移除旧 Host/Port/WSS/Access Token API、未使用的 QQ 安装检测与 Manifest QQ 包查询；保留回环 HTTP Bridge Token。

- [ ] **Step 3: 运行相关 Dart 测试**

Run: `flutter test test/models/qq_integration_settings_test.dart test/screens/qq_integration_screen_test.dart test/services/qq/qq_storage_test.dart`

### Task 4: 旧诊断与文档修正

**Files:**
- Create: `test/models/qq_diagnostic_event_test.dart`
- Modify: `lib/models/qq_diagnostic_event.dart`
- Modify: `README.zh-CN.md`

**Interfaces:**
- Produces: 未识别的历史事件类型读取为 `QqDiagnosticEventType.legacyUnsupported`。

- [ ] **Step 1: 写入并运行旧诊断失败测试**

Run: `flutter test test/models/qq_diagnostic_event_test.dart`

- [ ] **Step 2: 添加兼容枚举并更新 README 版本文本**

将中文说明中的当前版本和推荐产物名统一为 `1.5.1`。

- [ ] **Step 3: 执行完整验证**

Run: `flutter test`

Run: `flutter analyze`

Run: `npm test` in `qq_bridge`

Run: `npm run build` in `qq_bridge`

Run: `./gradlew app:testDebugUnitTest` in `android`
