# Whisnya

## 1.4.2+20

- Isolated manual and rolling summaries by operation and session, preventing stale requests or dialogs from writing into another conversation.
- Session management now stops active generation first, awaits partial-reply persistence, reports save failures, and avoids recreating deleted session files.
- Deleting an earlier selected assistant candidate now warns before truncating all dependent later messages and invalidates affected summaries.
- Conversation mutations are consistently disabled while generation or summarization owns the chat; controls recover when the operation finishes.
- AI-extracted memories can switch between character and current-session scope during review, with correct session binding and no world-book keyword fields.
- Global world books can now be created and edited from Settings below continuous bubble output.

## 1.4.1+19

- A character can now have multiple independent chat sessions. Sessions support renaming, duplication, archiving, and deletion.
- Assistant replies can keep multiple variants. The selected variant is used consistently for prompts, search, copy, summaries, and TXT export.
- Added character memory, session memory, and keyword-triggered world-book entries with a configurable context budget and reviewed AI extraction.
- Existing `chats/{characterId}.json` and `summaries/{characterId}.json` files migrate lazily on first session access. Migration writes the new files and index before removing legacy files; a failed migration leaves the legacy data intact.
- Full backups use manifest schema version 3 and include sessions, variants, and memories. Older schema versions remain importable.

[简体中文](README.zh-CN.md)

Whisnya is a local-first Android and Windows AI role chat and TXT novel reader app built with Flutter.

## Download

Prebuilt Android APK and Windows x64 zip packages are published on
[GitHub Releases](https://github.com/mkdjj/Whisnya/releases/latest).

Release assets are intentionally not committed to the repository. Clone the
source if you want to build Whisnya yourself.

## Features

- Configure multiple OpenAI Chat Completions compatible API endpoints.
- Create, edit, hide, lock, import, and export character cards.
- Pick and crop avatars, chat backgrounds, and interface backgrounds locally.
- Chat with full context or automatic rolling summaries plus recent messages.
- Create theater/group chats with multiple character or novel-role participants.
- Import TXT novels with UTF-8/GBK detection, read by detected chapters, summarize novels, and move extracted roles into theater chats.
- Use ten built-in chat-bubble presets, plus shared opacity settings.
- Maintain a reusable user profile for character and theater conversations.
- Switch the novel library between list and grid views.
- Export and import all local data, with API keys excluded by default.
- Privacy password for locked characters and novels.
- Light/dark/system theme, background opacity/blur, font scaling, and Chinese/English UI.

## Requirements

- Flutter >= 3.38.4
- Dart >= 3.12.2
- Android SDK with a working release build setup
- Visual Studio 2022 Build Tools with Desktop development with C++ for Windows builds

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

Current release version is `1.4.2+20`. Keep both `versionName` and `versionCode` increasing for every public release. The Android package name is
`com.mkdjj.whisnya`.

For public distribution, configure your own Android signing key first:

```powershell
keytool -genkey -v -keystore android/whisnya-release.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias whisnya
Copy-Item android/key.properties.example android/key.properties
```

Then edit `android/key.properties` with your real passwords. Both
`android/key.properties` and `.jks` files are ignored by git.

Recommended release asset name:

```text
Whisnya-android-v1.4.2-release.apk
```

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

Recommended Windows release asset name:

```text
Whisnya-windows-x64-v1.4.2.zip
```

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
  novel_summary_cache/
    {novelId}.json
  theater_sessions.json
  theater_messages/
    {sessionId}.json
  media/
    avatars/
    backgrounds/
    global/
```

The in-app full-data export creates a zip backup with relative files under `app_data/`.
API keys are excluded by default and are only included when you explicitly enable
that option before exporting.
Import repairs saved paths for the current platform, so backups can be moved between
Android, Windows, macOS, and iOS builds of Whisnya.

## Privacy

Whisnya is local-first. Chat records, novel text, character data, images, settings,
and API configuration are stored locally by default. After you configure a third-party
API endpoint, request content is sent to that model provider when you chat or summarize.

Do not publicly share backups that contain API keys, chat records, novel text, or
other private data.
