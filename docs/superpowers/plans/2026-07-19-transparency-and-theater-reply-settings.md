# Transparency and Theater Reply Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every transparency control read 0% as opaque and 100% as transparent, and generate theater reply-count choices from the current replyable role count.

**Architecture:** Persist existing opacity/alpha values unchanged and invert only at UI boundaries through two shared conversion functions. Keep the existing theater reply value meanings (`0` means all for main replies and none for extra replies), but remove the obsolete upper limit of two and generate chips from the enabled, unmuted AI participant count.

**Tech Stack:** Flutter, Dart, flutter_test

## Global Constraints

- Do not rename persisted opacity JSON fields or migrate saved values.
- Transparency is exactly `1 - opacity`, clamped to `0..1` in both directions.
- Extra-reply labels use compact Chinese text such as `0-1个`.
- Build only the Android arm64 split release APK for delivery.

---

### Task 1: Shared Transparency Conversion and UI Wiring

**Files:**
- Create: `lib/utils/transparency.dart`
- Create: `test/transparency_test.dart`
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/screens/chat/chat_screen.dart`
- Modify: `lib/screens/theater/theater_chat_screen.dart`
- Modify: `lib/screens/theater/theater_edit_screen.dart`
- Modify: `lib/widgets/chat_bubble_theme_editor.dart`

**Interfaces:**
- Produces: `double opacityToTransparency(num opacity)` and `double transparencyToOpacity(num transparency)`.
- Consumes: Existing stored opacity values and existing slider callbacks.

- [ ] **Step 1: Write the failing conversion test**

```dart
expect(opacityToTransparency(1), 0);
expect(opacityToTransparency(0), 1);
expect(transparencyToOpacity(0), 1);
expect(transparencyToOpacity(1), 0);
expect(opacityToTransparency(2), 0);
expect(transparencyToOpacity(-1), 1);
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/transparency_test.dart`

Expected: compilation failure because `lib/utils/transparency.dart` does not exist.

- [ ] **Step 3: Add the minimal conversion functions**

```dart
double opacityToTransparency(num opacity) =>
    1 - opacity.clamp(0, 1).toDouble();

double transparencyToOpacity(num transparency) =>
    1 - transparency.clamp(0, 1).toDouble();
```

- [ ] **Step 4: Invert every transparency slider at the UI boundary**

For each stored opacity named in the design, use this exact pattern:

```dart
final transparency = opacityToTransparency(storedOpacity);
value: transparency,
display: '${(transparency * 100).round()}%',
onChanged: (value) => saveOpacity(transparencyToOpacity(value)),
```

Apply it to global background, navigation bar, list cards, character/theater backgrounds, character/theater inputs, and both sides of the chat-bubble theme editor.

- [ ] **Step 5: Run the focused tests and commit**

Run: `flutter test test/transparency_test.dart test/chat_bubble_widget_test.dart test/chat_api_refresh_test.dart test/theater_chat_screen_test.dart`

Expected: all tests pass.

```powershell
git add lib test/transparency_test.dart
git commit -m "fix: use intuitive transparency controls"
```

### Task 2: Dynamic Theater Reply Choices

**Files:**
- Modify: `lib/screens/theater/theater_reply_settings.dart`
- Modify: `lib/screens/theater/theater_chat_screen.dart`
- Modify: `lib/screens/theater/theater_edit_screen.dart`
- Modify: `lib/models/theater.dart`
- Modify: `lib/utils/app_i18n.dart`
- Modify: `test/theater_chat_screen_test.dart`
- Modify: `test/theater_reply_engine_test.dart`

**Interfaces:**
- `TheaterReplySettings` consumes `int participantCount`.
- Main choices store `1..N-1` and `0` for all.
- Extra choices store `0` for none and `1..N-1` as the random upper bound.

- [ ] **Step 1: Write failing widget and model tests**

For five replyable roles, assert main labels `1 人`, `2 人`, `3 人`, `4 人`, `全部角色` and extra labels `不追加`, `0-1个`, `0-2个`, `0-3个`, `0-4个`. For four roles, assert the `4 人` and `0-4个` labels are absent. Round-trip `mainReplyCount: 4` and `extraReplyMode: 4` through JSON.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `flutter test test/theater_chat_screen_test.dart test/theater_reply_engine_test.dart`

Expected: constructor error for missing `participantCount`, missing dynamic labels, and model values clamped to two.

- [ ] **Step 3: Generate compact dynamic chips**

```dart
final count = participantCount.clamp(0, 1000000);
final mainValues = [for (var value = 1; value < count; value++) value];
final extraValues = [for (var value = 1; value < count; value++) value];
```

Render `mainValues` as `$value 人`, then `全部角色`; render `不追加`, then `extraValues` as `0-$value个`. Pass `draft.activeAiParticipants.length` in chat settings and the enabled, unmuted, non-user selected-participant count in the editor.

- [ ] **Step 4: Remove only the obsolete upper clamp**

Change model normalization from `.clamp(0, 2)` to non-negative normalization while preserving `0` defaults and JSON field names.

- [ ] **Step 5: Run the focused tests and commit**

Run: `flutter test test/theater_chat_screen_test.dart test/theater_reply_engine_test.dart test/theater_session_round_trip_test.dart`

Expected: all tests pass.

```powershell
git add lib test
git commit -m "feat: size theater reply choices dynamically"
```

### Task 3: Full Verification and arm64 APK

**Files:**
- Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- Output: `dist/Whisnya-android-arm64-v8a-v1.3.6-release.apk`

- [ ] **Step 1: Format and analyze**

Run: `dart format .` then `flutter analyze`

Expected: zero formatting changes after the format pass and no analysis issues.

- [ ] **Step 2: Run all tests**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 3: Build and inspect arm64 APK**

Run: `flutter build apk --release --target-platform android-arm64 --split-per-abi`

Expected: `app-arm64-v8a-release.apk` builds successfully and its `lib/` entries contain only `arm64-v8a`.

- [ ] **Step 4: Copy and hash the deliverable**

Copy the APK to `dist/Whisnya-android-arm64-v8a-v1.3.6-release.apk`, verify its signature with the installed Android build tools, and report its byte size and SHA-256.
