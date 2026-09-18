# Character Inner Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate, persist, display, and browse a fictional inner voice for newly completed character replies and reply variants.

**Architecture:** Store inner voice inside the existing message/variant JSON, build prompts in a pure service, and use one guarded asynchronous ChatScreen hook after normal reply persistence. Render one preview per assistant message and derive history from the current session without a new database.

**Tech Stack:** Flutter, Dart, existing `AiGateway`, `LocalStorageService`, widget/unit tests, Android Gradle

## Global Constraints

- Keep `version: 1.5.1+23` unchanged.
- Preserve existing uncommitted work and deleted QQ notification/accessibility files.
- Use the reply's existing endpoint/model and a non-streaming inner-voice request.
- Never use or persist `reasoning_content` as inner voice.
- Never include inner voice in chat prompts, summaries, memory, world-book matching, search, or TXT export.
- Do not commit, reset, clean, restore, or push unless separately requested.

---

### Task 1: Settings and message data contracts

**Files:**
- Modify: `lib/models/app_settings.dart`
- Modify: `lib/models/chat_message.dart`
- Modify: `lib/models/chat_reply_variant.dart`
- Modify: `lib/controllers/chat_conversation_controller.dart`
- Modify: `test/app_settings_test.dart`
- Modify: `test/models/chat_message_variant_test.dart`
- Modify: `test/controllers/chat_conversation_controller_test.dart`

**Interfaces:**
- Produces: `AppSettings.showCharacterInnerVoice`, `ChatMessage.innerVoice`, `ChatMessage.effectiveInnerVoice`, `ChatReplyVariant.innerVoice`, and `ChatConversationController.setAssistantInnerVoice(...)`.

- [ ] Write failing tests for default/JSON/copy behavior, variant isolation, legacy compatibility, first-variant preservation, and guarded stale-write rejection.
- [ ] Run the three targeted test files and confirm failures are caused by the missing contracts.
- [ ] Add the fields, serializers, effective getter, and controller update method with reply-snapshot guards.
- [ ] Run the targeted tests and require all to pass.

### Task 2: Pure prompt and normalization service

**Files:**
- Create: `lib/services/chat/character_inner_voice_service.dart`
- Create: `test/services/chat/character_inner_voice_service_test.dart`

**Interfaces:**
- Produces: `CharacterInnerVoiceService.buildMessages(...)`, `CharacterInnerVoiceService.normalize(String)`, `maxCharacters = 500`, `maxRecentMessages = 12`, and `maxRecentMessageCharacters = 1200`.

- [ ] Write failing tests for role filtering, 12-message selection, 1200-rune truncation, absence of inner voice/reasoning fields, prompt sections, title/fence removal, empty output, 500-rune cap, and emoji safety.
- [ ] Run the service test and confirm it fails because the service is absent.
- [ ] Implement the dedicated prompt and rune-safe normalization without adding dependencies or network code.
- [ ] Run the service test and require all cases to pass.

### Task 3: Settings UI and translations

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/utils/app_i18n.dart`
- Modify: `test/chat_bubble_preset_screen_test.dart`

**Interfaces:**
- Produces: `ValueKey('show-character-inner-voice-setting')` directly between reasoning and continuous bubble output.

- [ ] Change the widget test to require the new switch, its order, and saved true value; run it and confirm failure.
- [ ] Add the switch and all Chinese-to-English strings required by preview, dialog, history, generating, failed, and empty states.
- [ ] Run the settings test and require it to pass.

### Task 4: Preview, dialog, and current-session history

**Files:**
- Create: `lib/widgets/chat/character_inner_voice_preview.dart`
- Create: `lib/widgets/chat/character_inner_voice_dialog.dart`
- Create: `lib/screens/chat/character_inner_voice_history_screen.dart`
- Create: `test/widgets/character_inner_voice_ui_test.dart`

**Interfaces:**
- Produces: `CharacterInnerVoicePreview`, `showCharacterInnerVoiceDialog(...)`, shared `CharacterInnerVoiceAvatar`, and `CharacterInnerVoiceHistoryScreen`.

- [ ] Write failing widget tests for two-line preview, generating/failed labels, dialog content/history navigation, current-message filtering, effective variant data, newest-first order, and empty state.
- [ ] Run the UI test and confirm failure because the widgets are absent.
- [ ] Implement theme-aware responsive UI using `Text`/`SelectableText`, `MaterialLocalizations`, and the existing file-avatar pattern.
- [ ] Run the UI test and require it to pass.

### Task 5: Unified asynchronous chat integration

**Files:**
- Modify: `lib/screens/chat/chat_screen.dart`
- Modify: `test/chat_screen_hotfix_test.dart`

**Interfaces:**
- Consumes: the service, controller guard, existing endpoint/model, memory prompt, summary, recent messages, storage, and `AiCancelToken`.
- Produces: one post-reply inner-voice operation for a normal reply or newly selected variant, with runtime generating/failed status.

- [ ] Add failing integration tests proving OFF makes zero `sendMessage` calls; ON saves/displays the main reply before a controlled inner-voice future completes; success records the correct voice/variant; failure preserves the reply; stale session/message/toggle results are discarded; split output shows one preview.
- [ ] Run the focused integration tests and confirm the expected failures.
- [ ] Add one `_generateInnerVoiceForReply(...)` hook after main reply persistence, capture immutable context, use `sendMessage`, record `characterInnerVoice` usage, and add operation/session/message/variant/toggle guards.
- [ ] Wire preview/dialog/history to the last split segment and keep reasoning independent.
- [ ] Cancel or invalidate operations on stop, clear/delete, setting disable, session change, and dispose.
- [ ] Run focused integration tests and require all to pass.

### Task 6: Full verification and packaging

**Files:**
- Output: `build/app/outputs/flutter-apk/app-debug.apk`
- Output: `build/windows/x64/runner/Debug/whisnya.exe`
- Output: `build/app/outputs/flutter-apk/Whisnya-android-v1.5.1-arm64-v8a-release.apk`

**Interfaces:**
- Produces: verified debug builds and one signed arm64-v8a release APK with SHA-256.

- [ ] Run `flutter pub get`.
- [ ] Run `dart format --output=none --set-exit-if-changed lib test`.
- [ ] Run `flutter analyze` and all `flutter test` tests.
- [ ] Run `flutter build apk --debug` and `flutter build windows --debug`.
- [ ] Run `git diff --check` and verify deleted QQ notification/accessibility files remain deleted.
- [ ] Run `flutter build apk --release --target-platform android-arm64 --split-per-abi`, copy the versioned artifact, verify signature/ABI/version, and compute SHA-256.
