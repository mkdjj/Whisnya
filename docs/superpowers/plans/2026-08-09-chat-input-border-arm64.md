# Chat Input Border and ARM64 Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the chat input outline with opacity matching `inputOpacity`, then produce the Android arm64-v8a release APK.

**Architecture:** Keep the change inside `ChatInputComposer`, where the input surface opacity is already clamped. Reuse that alpha for all `OutlineInputBorder` states so focus and generation cannot introduce a fully opaque frame.

**Tech Stack:** Flutter, Dart widget tests, Android Gradle release build

## Global Constraints

- Keep `version: 1.5.1+23` unchanged.
- Do not alter generation controls, focus retention, or keyboard behavior.
- Build only the Android arm64-v8a small package.

---

### Task 1: Restore the opacity-aware input outline

**Files:**
- Modify: `lib/widgets/chat_input_composer.dart`
- Create: `test/widgets/chat_input_composer_test.dart`

**Interfaces:**
- Consumes: `ChatInputComposer.inputOpacity` and the active `ColorScheme`.
- Produces: `OutlineInputBorder` decorations whose alpha equals the clamped input opacity.

- [x] **Step 1: Write the failing widget test**

Build a `ChatInputComposer` with `inputOpacity: 0.35` and assert that its default, enabled, focused, and disabled borders are outlines with alpha `0.35`.

- [x] **Step 2: Run the targeted test and verify RED**

Run: `flutter test test/widgets/chat_input_composer_test.dart`

Expected: FAIL because the current decoration uses `InputBorder.none`.

- [x] **Step 3: Implement the minimal decoration change**

Create outline borders from `colors.outline.withValues(alpha: alpha)` and `colors.primary.withValues(alpha: alpha)`, then assign them to the four input states.

- [x] **Step 4: Run the targeted test and verify GREEN**

Run: `flutter test test/widgets/chat_input_composer_test.dart`

Expected: PASS.

### Task 2: Verify and build the small package

**Files:**
- Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

**Interfaces:**
- Consumes: the verified Flutter project and Android release configuration.
- Produces: one installable arm64-v8a APK plus its SHA-256 digest.

- [x] **Step 1: Run formatting, analysis, and Flutter tests**

Run `dart format`, `flutter analyze`, and `flutter test`, and require zero failures.

- [x] **Step 2: Build Android arm64-v8a release**

Run: `flutter build apk --release --target-platform android-arm64 --split-per-abi`

Expected: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` exists and is non-empty.

- [x] **Step 3: Verify the artifact**

Compute its size and SHA-256 digest, and confirm `git diff --check` succeeds.
