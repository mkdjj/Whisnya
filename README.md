# Whisnya

[简体中文](README.zh-CN.md)

Whisnya is a local-first Android AI role chat and TXT novel reader app built with Flutter.

## Features

- Configure Grok, DeepSeek, and GPT-compatible Chat Completions APIs.
- Create, edit, hide, lock, import, and export character cards.
- Pick and crop avatars, chat backgrounds, and interface backgrounds locally.
- Chat with character prompts plus saved conversation summaries.
- Import TXT novels, read by detected chapters, summarize novels, and chat with extracted roles.
- Export and import all local data, including novel text, chats, summaries, images, settings, and API config.
- Privacy password for locked characters and novels.
- Light/dark/system theme, background opacity/blur, font scaling, and Chinese/English UI.

## Requirements

- Flutter >= 3.38.4
- Dart >= 3.12.2
- Android SDK with a working release build setup

## Build APK

```powershell
git clone https://github.com/mkdjj/Whisnya.git
cd Whisnya
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The APK will be generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For public distribution, configure your own Android signing key first.

## Other Platforms

Windows platform files are included. Build Windows on Windows:

```powershell
flutter build windows --release
```

The Windows build is generated at:

```text
build/windows/x64/runner/Release/
```

Ship the whole `Release` folder, not only the `.exe`.

Generate iOS or macOS platform files, then build on macOS with Xcode installed:

```bash
flutter create --platforms=ios,macos .
flutter build ipa --release
flutter build macos --release
```

iOS and macOS distribution requires Apple signing.

## Local Data

Whisnya stores data in the app documents directory:

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

The in-app full-data export creates a zip backup with relative files under `app_data/`.
Import repairs saved paths for the current platform, so backups can be moved between
Android, Windows, macOS, and iOS builds of Whisnya.

Do not publish local backups, API keys, chat records, novel text, or signing files.
