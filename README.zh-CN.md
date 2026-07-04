# Whisnya

[English](README.md)

Whisnya 是一个本地自用 Android AI 角色聊天 App，使用 Flutter + Dart 开发。

## 已实现

- Grok / DeepSeek / GPT 三组 OpenAI Chat Completions 兼容 API 配置。
- 角色创建、编辑、隐藏、上锁、导入和导出。
- 头像、聊天背景图和界面背景可从系统文件选择器选取，并在 App 内裁剪后保存到本地。
- 选择角色进入聊天，发送消息时携带角色设定和历史总结。
- 导入 TXT 小说，按章节阅读，总结小说并提取角色。
- 小说内角色聊天、角色详情查看、导出和删除。
- 导出/导入全部本地数据，包括小说原文、聊天记录、总结、图片、设置和 API 配置。
- 隐私密码保护上锁角色和小说。
- 主题模式、背景透明度/模糊度、字体大小和中英文界面。

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

不要上传本地备份、API Key、聊天记录、小说原文或签名文件。

## 常用命令

```powershell
.\.toolcache\flutter\bin\flutter.bat pub get
.\.toolcache\flutter\bin\flutter.bat analyze
.\.toolcache\flutter\bin\flutter.bat test
.\.toolcache\flutter\bin\flutter.bat build apk --release
```
