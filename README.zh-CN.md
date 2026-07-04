# Whisnya

[English](README.md)

Whisnya 是一个本地优先的 Android AI 角色聊天和 TXT 小说阅读 App，使用 Flutter 开发。

## 功能

- Grok / DeepSeek / GPT 三组 OpenAI Chat Completions 兼容 API 配置。
- 角色创建、编辑、隐藏、上锁、导入和导出。
- 头像、聊天背景图和界面背景可从系统文件选择器选取，并在 App 内裁剪后保存到本地。
- 选择角色进入聊天，发送消息时携带角色设定和历史总结。
- 导入 TXT 小说，按章节阅读，总结小说并提取角色。
- 小说内角色聊天、角色详情查看、导出和删除。
- 导出/导入全部本地数据，包括小说原文、聊天记录、总结、图片、设置和 API 配置。
- 隐私密码保护上锁角色和小说。
- 主题模式、背景透明度/模糊度、字体大小和中英文界面。

## 环境要求

- Flutter >= 3.38.4
- Dart >= 3.12.2
- Android SDK，并能正常执行 release 构建

## 打包 APK

```powershell
git clone https://github.com/mkdjj/Whisnya.git
cd Whisnya
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

APK 会生成在：

```text
build/app/outputs/flutter-apk/app-release.apk
```

如果要公开分发，请先配置自己的 Android 签名文件。

## 其他平台

仓库已经包含 Windows 平台文件。在 Windows 上打包 Windows 版：

```powershell
flutter build windows --release
```

Windows 产物会生成在：

```text
build/windows/x64/runner/Release/
```

发布时要带上整个 `Release` 文件夹，不要只发 `.exe`。

iOS 或 macOS 需要先生成平台文件，然后在安装了 Xcode 的 macOS 上打包：

```bash
flutter create --platforms=ios,macos .
flutter build ipa --release
flutter build macos --release
```

iOS 和 macOS 分发需要 Apple 签名。

## 本地数据

App 会在应用文档目录下创建：

```text
app_data/
  api_config.json
  settings.json
  characters.json
  novels.json
  chats/
    {characterId}.json
  summaries/
    {characterId}.json
  novels/
    {novelId}.txt
  novel_chats/
    {novelId}.json
  media/
    avatars/
    backgrounds/
    global/
```

App 内的“导出全部数据”会生成 zip 备份，里面使用 `app_data/` 下的相对文件结构。
导入时会自动修复当前平台的数据路径，所以备份可以在 Whisnya 的 Android、Windows、macOS 和 iOS 版本之间迁移。

不要上传本地备份、API Key、聊天记录、小说原文或签名文件。
