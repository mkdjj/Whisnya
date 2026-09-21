# 四功能交付记录 · 2026-09-20

## 本次交付

剧情存档/独立分支、会话状态卡、不可变回忆册/本地 PNG、Android/Windows 系统角色语音已接入。使用说明见 [story-features.md](story-features.md)。新增开关默认关闭；旧版数据在读取时补齐稳定消息 ID，不重做既有记忆、世界书或角色心声。

源码基线：`100d009c2fcb1691f2beeeb00e425384e1fe6033`，开始时工作区干净。本次改动留在工作区，未提交、推送或更新 Release。

## 安装包

- 文件：`E:/AIChat/dist/arm64-20260920-232729-876/Whisnya_1.5.2+24_arm64_20260920-232729-876.apk`
- 大小：22,429,150 bytes / 21.390 MiB。
- 版本：源码 `1.5.2+24`，APK versionName `1.5.2`，split ARM64 versionCode `2024`。
- applicationId：`com.mkdjj.whisnya`；debuggable=false；仅 arm64-v8a。
- SHA256：`27A3FF82FFF01815CD72B9A84DF696616BD2D374C014A3A7BD113B81DBBA6A6E`。
- 与上次小包 21,970,006 bytes 相比增加 459,144 bytes（约 0.438 MiB / 2.09%）。不要把本次未拆调试信息的基准包当作上次交付包比较。
- 维持用户之前明确批准的历史签名配置，证书与旧包相同：`43633229155f48f19f5a432f5575c81d7f0f5521ab7979fe6fa497775fe8f984`。证书名称为 Android Debug；这是沿用已有证书以保持覆盖安装兼容，不是新建签名或自动回退。APK 本身是非调试 Release 构建。
- 历史 APK 未删除。本次符号文件、APK 签名/大小报告和 SHA256SUMS 一同保留在新 dist 目录。

## 验证结果

| 项目 | 结果 | 证据 |
|---|---|---|
| flutter pub get | exit 0 | build/optimization_report/20260920-232729-876/pub-get.log |
| 格式检查 | exit 0，253 文件无改动 | dart format --output=none --set-exit-if-changed lib test tool |
| 静态分析 | exit 0，No issues found | build/story-analyze-final.log |
| Flutter 全量测试 | exit 0，555 passed | build/story-features-tests-final.log |
| Windows Debug | exit 0 | build/story-windows-final.log |
| Android 全模块 testDebugUnitTest | exit 0 | build/story-android-unit-verified.log |
| Android 应用原生测试 | 2 tests / 0 failures / 0 errors | build/app/test-results/testDebugUnitTest/*.xml |
| ARM64 Release | exit 0 | build/optimization_report/20260920-232729-876/final-release.log |
| 签名与历史证书比较、Manifest、ABI、ZIP 内容 | exit 0 | 同目录 signature.log / historical-signature.log / manifest-*.log，dist BUILD_REPORT.txt |
| git diff --check | exit 0 | 本次终端执行记录 |

Flutter 3.44.3 / Dart 3.12.2，Android SDK 36.0.0，JDK 21.0.11，Visual Studio Build Tools 2022。Windows 语音插件需要 NuGet CLI，已在本地工具缓存补齐并核对 Microsoft Authenticode 签名。Android 全模块测试的工作目录须同处 C 盘且不包含中文，本次使用进程级 `java.io.tmpdir=C:/Users/Public/Whisnya-build-tmp`；Gradle 缓存为 `.toolcache/gradle-home`，没有修改用户全局环境变量。

重点新增回归：旧 ID 迁移幂等；完整前缀锚点；候选同文异 ID；分支未来正文/总结隔离；写失败后的恢复；状态锁/手动与 AI 并发/跨会话队列/清空回滚；回忆正文/头像不可变与隐私；长文本分页和部分保存；语音旧回调/停止串行/默认不调用引擎；真实临时目录全量备份往返（两分支、孤立存档、状态锁、受保护回忆、头像、双平台音色）。

## 验证边界与注意事项

`adb devices -l` 没有 Android 设备。本次没有宣称完成真机覆盖安装、真实 API 端到端请求、系统音色试听、Android 文件选择器保存 PNG 或厂商后台行为测试。Windows 完成编译及假后端/通道测试，未做实际扬声器试听。系统音色是否可用、是否需要下载音色包取决于设备；需要网络或网络属性未知的音色必须先获得明确许可。

新状态自动更新会产生额外 AI 请求费用；所有这些行为默认关闭。隐私锁是应用访问控制，不是文件加密。分享前请检查正文/标题中的个人信息。原角色删除时默认保留独立存档与回忆册；保留的受保护快照仍需原有隐私密码。
