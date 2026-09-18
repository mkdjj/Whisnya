# Character Inner Voice Design

## Goal

Add an opt-in fictional character inner voice generated after each completed character reply, stored with the reply or selected reply variant and shown through a compact preview, full dialog, and current-session history.

## Constraints

- Keep `version: 1.5.1+23` unchanged because the user's latest instruction overrides the supplied document's build-number rule.
- Preserve every existing uncommitted QQ cleanup and chat-input change.
- Never restore notification-listener or accessibility QQ reply code.
- Inner voice is a separate user-visible AI request, never `reasoning_content` or hidden model reasoning.
- When disabled, make zero inner-voice requests, hide all inner-voice UI, and retain stored data.
- Do not add inner voice to future chat prompts, summaries, memory extraction, world-book matching, search, or text export.

## Architecture

### Data

`AppSettings.showCharacterInnerVoice` defaults to false and round-trips through settings JSON. `ChatMessage.innerVoice` stores the legacy/top-level reply voice; `ChatReplyVariant.innerVoice` stores each candidate's voice. `ChatMessage.effectiveInnerVoice` returns the selected variant's value even when that value is empty, so it never leaks another candidate's voice.

`ChatConversationController` owns guarded inner-voice updates. A write names the message index, reply snapshot, optional variant index, and normalized voice. It succeeds only if the assistant reply still exists and the snapshot still matches. When the first regeneration converts a legacy reply into variant zero, the existing top-level voice is copied into that first variant.

### Generation

`CharacterInnerVoiceService` is pure: it builds the dedicated system/user messages, selects at most 12 user/assistant messages, limits every recent message to 1200 Unicode runes, and normalizes the response to at most 500 runes. It never sends HTTP.

`ChatScreen` starts one non-streaming `AiGateway.sendMessage` request only after the main assistant reply has been displayed and saved. It reuses the actual endpoint/model, character prompt, already-computed memory/world-book prompt, current summary, and main request's recent messages. Usage is recorded as `characterInnerVoice`.

Each request captures session id, message index, reply snapshot, optional variant index, operation id, and cancel token. Runtime generating/failed state is not serialized. Completion reloads the latest settings and checks session, operation, message, variant, and reply snapshot before writing. Switching session, deleting/clearing messages, stopping generation, disabling the setting, or disposing cancels or invalidates matching operations.

### UI

The assistant reply stays visible before inner-voice generation begins. A theme-aware card below the whole assistant reply shows generating, failed, or at most two preview lines. Split role bubbles attach one card only to the last segment. The card is independent from reasoning UI.

Tapping a completed preview opens a responsive dialog with the shared character avatar, character name, selectable full text, and a history button. History derives entries directly from the current session's messages, uses each message's effective content/time/inner voice, sorts newest first, and expands entries in place.

## Error Handling

Timeouts, network/API errors, cancellation, empty output, stale operations, deleted messages, and session changes never remove or delay the assistant reply. Failed requests store no error text and do not retry automatically.

## Verification

Use red-green tests for settings/model compatibility, prompt and normalization, controller guards, settings order, preview/split/variant behavior, dialog/history, generation off/on/failure, and stale result rejection. Then run pub get, format check, analyze, all Flutter tests, Android debug build, Windows debug build, diff check, and the requested arm64-v8a release build.
