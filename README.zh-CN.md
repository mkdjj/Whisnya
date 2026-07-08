# Whisnya

[English](README.md)

Whisnya 是一个本地优先的 Android / Windows AI 角色聊天和 TXT 小说阅读 App，使用 Flutter 开发。

## 下载

预构建的 Android APK 和 Windows x64 zip 包会发布在
[GitHub Releases](https://github.com/mkdjj/Whisnya/releases/latest)。

发布包不会提交进源码仓库。想自己打包时，clone 源码后按下面步骤构建即可。

## 功能

- 可添加多个 OpenAI Chat Completions 兼容 API 配置。
- 角色创建、编辑、隐藏、上锁、导入和导出。
- 头像、聊天背景图和界面背景可从系统文件选择器选取，并在 App 内裁剪后保存到本地。
- 角色聊天支持全部上下文，或自动滚动总结 + 最近消息。
- 可创建多个角色或小说角色参与的群聊/剧场。
- 导入 TXT 小说，支持 UTF-8 / GBK 识别，按章节阅读，总结小说并提取角色。
- 小说列表支持列表/网格视图切换。
- 小说内角色聊天、角色详情查看、导出和删除。
- 导出/导入全部本地数据，默认不包含 API Key。
- 隐私密码保护上锁角色和小说。
- 主题模式、背景透明度/模糊度、字体大小和中英文界面。

## 环境要求

- Flutter >= 3.38.4
- Dart >= 3.12.2
- Android SDK，并能正常执行 release 构建
- Windows 打包需要 Visual Studio 2022 Build Tools，并包含 Desktop development with C++

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

当前发布版本是 `1.3.1+9`。每次公开发版都要同时递增 `versionName`
和 `versionCode`。Android 包名是 `com.mkdjj.whisnya`。

如果要公开分发，请先配置自己的 Android 签名文件：

```powershell
keytool -genkey -v -keystore android/whisnya-release.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias whisnya
Copy-Item android/key.properties.example android/key.properties
```

然后把真实密码写进 `android/key.properties`。`android/key.properties`
和 `.jks` 文件都已经被 git 忽略，不要提交。

推荐发布文件名：

```text
Whisnya-android-v1.3.1-release.apk
```

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

推荐 Windows 发布文件名：

```text
Whisnya-windows-x64-v1.3.1.zip
```

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
API Key 默认不会导出，只有在导出前明确勾选“包含 API Key”时才会写入备份。
导入时会自动修复当前平台的数据路径，所以备份可以在 Whisnya 的 Android、Windows、macOS 和 iOS 版本之间迁移。

## 隐私说明

Whisnya 是本地优先应用。聊天记录、小说原文、角色数据、图片、设置和 API 配置默认保存在本地。配置第三方 API 后，聊天或总结时的请求内容会发送给对应模型服务商。

不要公开分享包含 API Key、聊天记录、小说原文或其他隐私内容的备份文件。
