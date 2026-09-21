# Reply Inspiration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add an explicitly requested, three-option reply inspiration panel beside the chat input.

**Architecture:** A pure service builds bounded prompts and parses three JSON suggestions. A modal owns its independent request token, mode, loading, error and retry state. Chat captures the session/dataset and inserts the selected text into the existing draft without sending or writing chat history.

**Tech Stack:** Existing Flutter/Dart and AiGateway; no dependencies.

**Spec:** User request in this task: lightbulb click generates three editable directions; selection only fills input; no background requests; action-only mode does not draft dialogue.

## Global Constraints

- Keep version 1.5.2+24 and all preceding UI changes.
- No APK packaging, Git commit, push or release in this turn.
- Never reuse or cancel the main reply's request token.
- Opening is explicit generation; changing modes only changes mode, then user clicks generate.
- Preserve existing draft and selected reply variants; do not include hidden reasoning or inner voice.

## Review Focus

- Repeated generation clicks: exactly one in-flight request.
- Dismissal before completion: cancel token and ignore late response.
- Malformed or fewer than three suggestions: show retryable error, no invented options.
- Existing draft and session/dataset change: preserve draft; reject stale result.
- Narrow screen and large text: scrollable panel, bounded composer buttons.

## Task 1: End-to-end inspiration flow

Files: create lib/services/chat/reply_inspiration_service.dart and lib/widgets/chat/reply_inspiration_sheet.dart; modify lib/widgets/chat_input_composer.dart, lib/screens/chat/chat_screen.dart, lib/utils/app_i18n.dart; test test/reply_inspiration_service_test.dart, test/reply_inspiration_sheet_test.dart and test/chat_screen_hotfix_test.dart.

Interfaces:
- ReplyInspiration(label, text), ReplyInspirationMode.reply/actions.
- ReplyInspirationService.buildMessages(characterName, recentMessages, draft, mode) -> List<Map<String,String>>.
- ReplyInspirationService.parse(raw) -> List<ReplyInspiration>; throws FormatException for invalid response.
- ReplyInspirationSheet(generate: Future<List<ReplyInspiration>> Function(ReplyInspirationMode, AiCancelToken)); pops selected text, cancels on dispose.

- [x] Write tests and observe red: assert prompt excludes reasoning/inner voice, bounds history, modes differ; parser returns exactly three valid distinct options and rejects malformed data.
- [x] Implement pure prompt/parser: JSON array of three label/text objects, no dialogue in actions mode, bounded recent selected message bodies and draft.
- [x] Test sheet: initial explicit opening triggers one generation, mode change alone does not; select returns text; dismiss cancels; failure supports explicit retry.
- [x] Implement scrollable mode/results/loading panel with separate cancel token and disabled duplicate generation.
- [x] Integrate optional lightbulb composer action; snapshot session and dataset; use current selected endpoint; record characterReplyInspiration usage; insert into draft without send.
- [x] Add chat test proving no request before click and no send/history mutation after selection; preserve draft.
- [x] Run scoped tests, full Flutter suite, analyzer, formatter and read-only review. Do not commit.


## Execution record

- Implemented inline in the user's existing dirty checkout; prior completed feature work was preserved. No branch, commit, publication, package build or version change.
- Ruling: mode changes clear/cancel current suggestions but do not issue requests; explicit Generate is required. Opening via lightbulb is itself explicit generation.
- Ruling: selected draft text must also survive; suggestions insert after the selection without replacing it.
- Review: independent read-only reviewers checked the layout and inspiration flow. Both inspiration findings were reproduced by failing tests, then fixed: preserve noncollapsed selections; cancel in PopScope immediately on dismissal, not after the reverse animation.
- Additional verification: dismiss during API configuration loading issues no request; narrow-screen inspiration does not interrupt the main reply; usage is recorded as characterReplyInspiration for existing category aggregation.
- Final verification: 65 scoped tests passed; 566 full Flutter tests passed; flutter analyze reports no issues; git diff --check passed. No device/API-live verification performed.
- Final review boundaries: unrelated pre-existing feature changes and device visual QA were excluded. Prior layout review found no actionable defect; the new request did not authorize packaging or publication.
