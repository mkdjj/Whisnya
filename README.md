# Whisnya

[简体中文](README.zh-CN.md)

Whisnya is a local-first Android AI role chat app built with Flutter and Dart.

## Features

- Configure Grok, DeepSeek, and GPT-compatible Chat Completions APIs.
- Create, edit, hide, lock, import, and export character cards.
- Pick and crop avatars, chat backgrounds, and interface backgrounds locally.
- Chat with character prompts plus saved conversation summaries.
- Import TXT novels, read by detected chapters, summarize novels, and chat with extracted roles.
- Export and import all local data, including novel text, chats, summaries, images, settings, and API config.
- Privacy password for locked characters and novels.
- Light/dark/system theme, background opacity/blur, font scaling, and Chinese/English UI.

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

Do not publish local backups, API keys, chat records, novel text, or signing files.

## Commands

```powershell
.\.toolcache\flutter\bin\flutter.bat pub get
.\.toolcache\flutter\bin\flutter.bat analyze
.\.toolcache\flutter\bin\flutter.bat test
.\.toolcache\flutter\bin\flutter.bat build apk --release
```
