# Chat Generation Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow non-destructive chat controls and the text input to remain usable during generation, while delete and summary actions stay disabled and an ARM64 release APK is produced.

**Architecture:** Split the previous broad busy guard into interaction-specific guards. Keep generation ownership unchanged, expose an owned completion future for deferred session switching, and make input focus/border behavior explicit in `ChatInputComposer`.

**Tech Stack:** Flutter, Dart, Flutter widget tests, Git, Android Gradle build.

## Global Constraints

- Keep `version: 1.4.2+20` unchanged.
- Do not add dependencies or alter local JSON formats.
- Do not weaken `generationId`/`sessionId` stale-result protection.
- During generation, delete and summary actions remain disabled.
- Other controls must not cancel the active API request.
- Produce an Android `arm64-v8a` release APK after verification.

---

### Task 1: Input focus and border regression

**Files:**
- Modify: `test/chat_screen_hotfix_test.dart`
- Modify: `lib/widgets/chat_input_composer.dart`
- Modify: `lib/screens/chat/chat_screen.dart`

**Interfaces:**
- Consumes: `ChatInputComposer(controller, focusNode, isGenerating, enabled, ...)`
- Produces: an enabled borderless `TextField` whose focus survives the transition to generation.

- [ ] **Step 1: Write the failing widget test**

Add a controlled streaming test that focuses the composer, sends text, waits for `Icons.stop`, and asserts `TextField.focusNode!.hasFocus`, `tester.testTextInput.isVisible`, and all four input borders equal `InputBorder.none`.

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/chat_screen_hotfix_test.dart --plain-name "sending keeps the keyboard and borderless input visible"`

Expected: FAIL because the current field becomes disabled, loses focus, and has outline borders.

- [ ] **Step 3: Implement the minimum input change**

Add a `FocusNode` to `ChatScreen`, pass it to `ChatInputComposer`, keep the field enabled while `isGenerating`, and use `InputBorder.none` for every border state.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command again. Expected: PASS.

### Task 2: Generation-time control policy

**Files:**
- Modify: `test/chat_screen_hotfix_test.dart`
- Modify: `lib/screens/chat/chat_screen.dart`
- Modify: `lib/screens/chat/chat_session_list_screen.dart`
- Modify: `lib/widgets/chat_variant_controls.dart`

**Interfaces:**
- Consumes: `_isSending`, `_isSummarizing`, `_isLoading`, and the active generation completion future.
- Produces: separate non-destructive interaction and delete/summary guards.

- [ ] **Step 1: Replace the old busy-state expectation with failing policy tests**

Assert during a controlled stream that settings, memory, and session management callbacks are non-null, while delete and summary callbacks remain null. Open each non-destructive screen and verify the gateway token is not cancelled.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `flutter test test/chat_screen_hotfix_test.dart --plain-name "generation keeps non-destructive controls available"`

Expected: FAIL because `_canMutateConversation` currently disables the non-destructive controls.

- [ ] **Step 3: Implement interaction-specific guards**

Remove `_isSending` from the general navigation guard, retain it in delete/clear/summary guards, stop passing `_isSending` as a blanket bubble busy state, and remove generation cancellation from `_openSessionList`.

- [ ] **Step 4: Protect session deletion and defer session switching**

Pass a generation-time delete lock to `ChatSessionListScreen`. Complete an owned future from the active generation `finally`, and await it before loading a selected different session.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run the Step 2 command again. Expected: PASS with the gateway token still active.

### Task 3: Full verification and ARM64 package

**Files:**
- Verify: `lib/`
- Verify: `test/`
- Create ignored artifact: `build/release-assets/Whisnya-android-v1.4.2-arm64-v8a-release.apk`

**Interfaces:**
- Consumes: the completed source tree.
- Produces: verified code and a single-ABI release APK.

- [ ] **Step 1: Run formatting, analysis, and full tests**

Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test --reporter compact`, and `git diff --check`. Expected: all exit 0.

- [ ] **Step 2: Build the ARM64 small package**

Run: `flutter build apk --release --target-platform android-arm64 --split-per-abi`

Expected: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

- [ ] **Step 3: Verify and copy the artifact**

Use `aapt dump badging`, archive inspection, and SHA-256 hashing to confirm versionName `1.4.2`, versionCode derived from build `20`, and only `arm64-v8a` native libraries. Copy it to the release-assets filename above.
