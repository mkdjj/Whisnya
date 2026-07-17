# Whisnya Runtime and Complexity Cleanup Design

## Goal

Reduce repeated disk work and eager UI construction, remove stale summaries after message deletion, and delete code that has no runtime value without changing Whisnya's visible behavior or localization direction.

## Constraints

- Keep the current Flutter/Dart stack and add no dependencies.
- Preserve the existing storage formats, migration behavior, API error copy, tab state, and Android/Windows support.
- Retain ARB localization resources; cache repeated regular expressions instead of removing the localization path.
- Prefer small helpers and native Dart/Flutter APIs over new abstractions.
- Every behavior change starts with a failing test.

## Runtime Changes

### Storage readiness and JSON recovery

`LocalStorageService` will memoize the one-time application-directory preparation future. Concurrent callers will share that future, so directory creation and legacy migration run once per service instance.

`JsonFileStore` will use the main file directly when it exists and no recovery artifacts are present. It will only inspect and parse recovery candidates when the main file is missing or a `.tmp`/`.bak` artifact exists. Corrupt-main fallback and atomic replacement behavior remain unchanged.

### Home tab lazy loading

`HomeScreen` will create a tab the first time it is selected and cache that widget for later visits. Unvisited `IndexedStack` entries will use a lightweight placeholder. Switching tabs must preserve the state of pages that have already been created.

### Duplicate work

- Keep character usage marking in the chat entry point and remove the duplicate home-screen call.
- Read and write endpoint API keys concurrently with `Future.wait`, while keeping each key paired with its endpoint ID.
- Compile dynamic translation regular expressions once at library scope.
- Put endpoint usability validation on the endpoint configuration model and reuse it from settings, chat, and theater flows while preserving their existing user-facing handling.

## Summary Consistency

Ordinary chat, novel chat, and theater chat must never retain summary text that includes a deleted message.

Before deletion, each flow will determine whether the target message belongs to the already summarized prefix. If it does, it will clear the summary text and reset the summarized-message count before persisting. Deleting a message outside that prefix leaves the summary intact. The calculation uses the same message filtering/counting rules as the corresponding summarization engine.

The summarized-prefix decision will be exposed as a small pure helper so boundary behavior is covered without widget mocks:

- deleting index `count - 1` invalidates the summary;
- deleting index `count` does not invalidate it;
- no stored summary never triggers a reset;
- non-chat/error entries do not shift filtered chat indexes incorrectly.

## Complexity Cleanup

Delete only files and wrappers with no production value:

- inline the one-call prompt/chat forwarding wrappers where their real implementation already has a clear public API;
- remove prompt wrapper tests that only assert delegation;
- remove the unused `NovelReaderState` type;
- remove empty novel reader part files;
- remove source-string and constructor-only widget tests that do not exercise behavior.

Do not remove ARB files, active novel analysis code, dependencies with runtime callers, or compatibility code used by persisted data.

## Verification

For each behavior change: add a focused failing test, confirm the expected failure, implement the smallest fix, and rerun the focused test. After cleanup, run Dart formatting, `flutter analyze`, the full Flutter test suite, an Android arm64 release APK build, and a Windows release build. The work is complete only if all commands succeed and the Git worktree contains only the intended changes.
