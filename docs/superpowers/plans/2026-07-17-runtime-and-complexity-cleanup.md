# Whisnya Runtime and Complexity Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove repeated runtime work and stale summaries, lazy-load home tabs, and delete forwarding/dead code without changing persisted formats or visible behavior.

**Architecture:** Keep changes inside existing models, storage services, screens, and summary services. Add no framework layer: pure summary-adjustment helpers live beside the summary services that own their counting rules, while UI code calls those helpers before persisting a deletion.

**Tech Stack:** Flutter, Dart, `flutter_test`, `flutter_secure_storage`, Git.

## Global Constraints

- Add no dependencies.
- Preserve Android arm64 and Windows release builds.
- Preserve JSON formats, recovery behavior, API error copy, visited tab state, and ARB resources.
- Use a failing focused test before each behavior change.
- Keep semantically neutral deletion/allocation cleanup inside a green refactor step.

---

### Task 1: One-time storage preparation and recovery fast path

**Files:**
- Modify: `lib/services/local_storage_service.dart`
- Modify: `lib/services/storage/json_file_store.dart`
- Test: `test/local_storage_write_test.dart`
- Test: `test/json_file_store_test.dart`

**Interfaces:**
- Produces: `LocalStorageService.appDataDirectory` returning the same cached `Future<Directory>` for every caller.
- Produces: `JsonFileStore.recoveryNeeded(File)` returning whether `.tmp`/`.bak` recovery inspection is required.

- [ ] **Step 1: Write the failing storage readiness test**

Add this assertion to a new test using a temporary directory:

```dart
final storage = LocalStorageService(appDataDirectory: directory);
final first = storage.appDataDirectory;
final second = storage.appDataDirectory;
expect(identical(first, second), isTrue);
expect(await first, same(await second));
```

- [ ] **Step 2: Run the readiness test and verify RED**

Run: `flutter test test/local_storage_write_test.dart`

Expected: FAIL because the current `async` getter creates a new future for every access.

- [ ] **Step 3: Cache one directory-preparation future**

Use one lazy future and one resolver:

```dart
Future<Directory>? _appDataDirectoryFuture;

Future<Directory> get appDataDirectory =>
    _appDataDirectoryFuture ??= _prepareAppDataDirectory();

Future<Directory> _prepareAppDataDirectory() async {
  final directory = _appDataDirectory ??
      Directory(
        '${(await getApplicationDocumentsDirectory()).path}'
        '${Platform.pathSeparator}app_data',
      );
  _appDataDirectory = directory;
  await _ensureAppDataDirectories(directory);
  return directory;
}
```

- [ ] **Step 4: Verify readiness GREEN**

Run: `flutter test test/local_storage_write_test.dart`

Expected: PASS.

- [ ] **Step 5: Write the failing recovery fast-path test**

Add a test for the wished-for API:

```dart
final target = file('normal.json');
await target.writeAsString('{"value":1}');
expect(await store.recoveryNeeded(target), isFalse);
await File('${target.path}.bak').writeAsString('{"value":0}');
expect(await store.recoveryNeeded(target), isTrue);
```

- [ ] **Step 6: Run the recovery test and verify RED**

Run: `flutter test test/json_file_store_test.dart`

Expected: compile failure because `recoveryNeeded` does not exist.

- [ ] **Step 7: Implement and use the recovery fast path**

Add:

```dart
Future<bool> recoveryNeeded(File file) async {
  if (!await file.exists()) return true;
  return await File('${file.path}.tmp').exists() ||
      await File('${file.path}.bak').exists();
}
```

Call `recover(file)` from `read` and `update` only when `recoveryNeeded(file)` is true. A normal main file is then parsed once by its actual read, while missing/corrupt/artifact cases retain the existing recovery code.

- [ ] **Step 8: Verify storage tests and commit**

Run: `flutter test test/json_file_store_test.dart test/local_storage_write_test.dart`

Expected: PASS.

Commit: `git commit -am "perf: avoid repeated storage preparation"`

---

### Task 2: Concurrent secure-key I/O and shared endpoint validation

**Files:**
- Modify: `lib/services/local_storage_service.dart`
- Modify: `lib/models/api_config.dart`
- Modify: `lib/screens/api_settings_screen.dart`
- Modify: `lib/screens/chat/chat_screen.dart`
- Modify: `lib/screens/theater/theater_chat_screen.dart`
- Test: `test/api_config_test.dart`
- Create: `test/local_storage_secure_keys_test.dart`

**Interfaces:**
- Produces: `AiEndpointConfig.validationError`, returning the existing first validation error or `null`.
- Keeps `loadApiConfig` and `saveApiConfig` public behavior unchanged while endpoint secret operations overlap.

- [ ] **Step 1: Write endpoint validation tests**

Add cases that start from a complete enabled endpoint and assert:

```dart
expect(endpoint.validationError, isNull);
expect(endpoint.copyWith(enabled: false).validationError,
    '褰撳墠 API 閰嶇疆宸茬鐢ㄣ€?);
expect(endpoint.copyWith(apiKey: ' ').validationError,
    'API Key 涓虹┖锛岃鍏堥厤缃€?);
expect(endpoint.copyWith(baseUrl: ' ').validationError,
    'Base URL 涓虹┖锛岃鍏堥厤缃€?);
expect(endpoint.copyWith(model: ' ').validationError,
    'Model 涓虹┖锛岃鍏堥厤缃€?);
```

- [ ] **Step 2: Verify endpoint validation RED**

Run: `flutter test test/api_config_test.dart`

Expected: compile failure because `validationError` does not exist.

- [ ] **Step 3: Implement and reuse model validation**

Add the getter to `AiEndpointConfig`:

```dart
String? get validationError {
  if (!enabled) return '褰撳墠 API 閰嶇疆宸茬鐢ㄣ€?;
  if (apiKey.trim().isEmpty) return 'API Key 涓虹┖锛岃鍏堥厤缃€?;
  if (baseUrl.trim().isEmpty) return 'Base URL 涓虹┖锛岃鍏堥厤缃€?;
  if (model.trim().isEmpty) return 'Model 涓虹┖锛岃鍏堥厤缃€?;
  return null;
}
```

Keep each screen's `null` endpoint error locally, then return `endpoint.validationError`. API settings may validate a disabled draft by checking `endpoint.copyWith(enabled: true).validationError` so its prior save/test behavior is unchanged.

- [ ] **Step 4: Verify endpoint validation GREEN**

Run: `flutter test test/api_config_test.dart`

Expected: PASS.

- [ ] **Step 5: Write secure-key concurrency tests**

Use a `FlutterSecureStorage` test double whose first two endpoint reads/writes wait on a shared `Completer<void>`. Start `loadApiConfig`/`saveApiConfig`, require both endpoint operations to reach the double before releasing the completer, and always release in `finally`:

```dart
var overlapped = false;
final operation = storage.loadApiConfig();
try {
  await secureStorage.twoEndpointOperationsStarted.future
      .timeout(const Duration(milliseconds: 250));
  overlapped = true;
} finally {
  secureStorage.release();
}
await operation;
expect(overlapped, isTrue);
```

Repeat for writes and verify endpoint IDs still receive their matching keys.

- [ ] **Step 6: Verify secure-key tests RED**

Run: `flutter test test/local_storage_secure_keys_test.dart`

Expected: timeout failure because endpoint operations are currently awaited sequentially.

- [ ] **Step 7: Use `Future.wait` without reordering endpoint results**

Read keys as an indexed list:

```dart
final apiKeys = await Future.wait([
  for (final endpoint in config.endpoints)
    _secureStorage.read(key: _secureApiKeyKey(endpoint.id)),
]);
```

Build copied endpoints by index. For writes, build one future per endpoint, await them together, then delete stale IDs together, and write the new ID index only after all secret operations succeed.

- [ ] **Step 8: Verify and commit**

Run: `flutter test test/api_config_test.dart test/local_storage_secure_keys_test.dart`

Expected: PASS.

Commit: `git commit -am "perf: share endpoint validation and key io"`

---

### Task 3: Lazy home tabs and one character-usage write

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Replace behavior in: `test/home_screen_state_test.dart`

**Interfaces:**
- Produces: a `_visitedTabs` set owned by `_HomeScreenState`; tab 0 is initially visited and other pages mount on first selection.
- Preserves the `IndexedStack` so visited pages retain state.

- [ ] **Step 1: Replace source-string tests with widget behavior tests**

Pump `HomeScreen` with a temporary `LocalStorageService`, `AiService`, and `MaterialApp`. Assert initially:

```dart
expect(find.byType(NovelScreen), findsNothing);
expect(find.byType(TheaterListScreen), findsNothing);
expect(find.byType(SettingsScreen), findsNothing);
```

Tap `Icons.menu_book_outlined`, pump, and assert `NovelScreen` exists. Return to characters and assert it remains mounted offstage.

Add a tracking `LocalStorageService` override, open one unprotected character, and assert `markCharacterUsed` is called once rather than twice.

- [ ] **Step 2: Verify home tests RED**

Run: `flutter test test/home_screen_state_test.dart`

Expected: initial lazy-loading assertions fail and usage count is 2.

- [ ] **Step 3: Implement visited-tab lazy loading**

Add:

```dart
final _visitedTabs = <int>{0};

void _selectTab(int index) {
  setState(() {
    _tabIndex = index;
    _visitedTabs.add(index);
  });
  if (index == 0) unawaited(_load());
}
```

In each non-character `IndexedStack` slot, use the current widget tree only when its index is present; otherwise use `const SizedBox.shrink()`. Remove the home-screen `markCharacterUsed` call and keep the chat-screen call.

- [ ] **Step 4: Verify and commit**

Run: `flutter test test/home_screen_state_test.dart`

Expected: PASS.

Commit: `git commit -am "perf: lazily mount home tabs"`

---

### Task 4: Invalidate summaries when a summarized message is deleted

**Files:**
- Modify: `lib/services/chat/chat_summary_service.dart`
- Modify: `lib/services/theater/theater_summary_service.dart`
- Modify: `lib/screens/chat/chat_screen.dart`
- Modify: `lib/screens/novel/novel_reader_screen.dart`
- Modify: `lib/screens/theater/theater_chat_screen.dart`
- Test: `test/chat_services_test.dart`
- Test: `test/theater_summary_service_test.dart`

**Interfaces:**
- Produces: `chatSummaryAfterMessageDeletion(...) -> ChatSummary`.
- Produces: `theaterSummaryAfterMessageDeletion(...) -> ({String summary, int summarizedMessageCount})`.

- [ ] **Step 1: Write failing ordinary/novel summary boundary tests**

Test a list containing user, system, and assistant messages. With a non-empty summary count of 2, assert deleting either summarized chat message returns `ChatSummary.empty(characterId)`, deleting the first unsummarized chat message returns the identical summary, and deleting the system message does not change the filtered chat index.

```dart
final next = chatSummaryAfterMessageDeletion(
  summary: summary,
  messages: messages,
  index: index,
);
expect(next.summary, isEmpty); // summarized entry
expect(next.summarizedMessageCount, 0);
```

- [ ] **Step 2: Verify chat summary tests RED**

Run: `flutter test test/chat_services_test.dart`

Expected: compile failure because the helper does not exist.

- [ ] **Step 3: Implement the filtered chat-prefix helper**

Count only preceding user/assistant messages. Return the original summary for invalid indexes, empty summaries, non-chat messages, and indexes at or beyond `summarizedMessageCount`; otherwise return `ChatSummary.empty(summary.characterId)`.

- [ ] **Step 4: Verify chat helper GREEN**

Run: `flutter test test/chat_services_test.dart`

Expected: PASS.

- [ ] **Step 5: Write failing theater summary boundary tests**

Assert deletion of a valid message below the absolute summarized count returns an empty summary/count 0. Assert deletion of an invalid/error entry below the count keeps summary text but decrements the count, because theater summary indexes are absolute while error messages are filtered from prompt content. Assert deletion at the count boundary changes nothing.

- [ ] **Step 6: Verify theater tests RED**

Run: `flutter test test/theater_summary_service_test.dart`

Expected: compile failure because the helper does not exist.

- [ ] **Step 7: Implement theater adjustment and wire all three screens**

Call the appropriate pure helper before removing the message. If the returned summary differs, persist it before the message file so an interrupted save can lose a cache but cannot retain deleted content. Update screen state with both the adjusted summary/session and message list.

For ordinary and novel chat:

```dart
final nextSummary = chatSummaryAfterMessageDeletion(
  summary: _summary,
  messages: _messages,
  index: index,
);
if (!identical(nextSummary, _summary)) {
  await widget.storage.saveSummary(nextSummary);
}
```

Use `_chatSummary` and `novel_chat_${_book.id}` unchanged in novel chat. For theater, locate the message ID before removal and save a copied session when either returned field changes.

- [ ] **Step 8: Verify and commit**

Run: `flutter test test/chat_services_test.dart test/theater_summary_service_test.dart`

Expected: PASS.

Commit: `git commit -am "fix: clear stale summaries after message deletion"`

---

### Task 5: Remove forwarding layers and allocation/dead-code noise

**Files:**
- Modify: `lib/screens/chat/chat_screen.dart`
- Modify: `lib/prompts.dart`
- Modify: `lib/utils/app_i18n.dart`
- Modify: `lib/screens/novel/novel_screens.dart`
- Modify: `test/chat_services_test.dart`
- Delete: `lib/services/chat/character_chat_service.dart`
- Delete: `lib/services/chat/chat_request_factory.dart`
- Delete: `lib/services/novel/novel_reader_state.dart`
- Delete: `lib/prompts/character_prompt_builder.dart`
- Delete: `lib/prompts/novel_prompt_builder.dart`
- Delete: `lib/prompts/summary_prompt_builder.dart`
- Delete: `lib/prompts/theater_prompt_builder.dart`
- Delete: `lib/screens/novel/novel_reader_settings_sheet.dart`
- Delete: `lib/screens/novel/novel_role_dialog.dart`
- Delete: `lib/screens/novel/widgets/novel_card.dart`
- Delete: `lib/screens/novel/widgets/novel_reader_toolbar.dart`
- Delete: `test/prompt_snapshot_test.dart`
- Delete: `test/chat_screen_flow_test.dart`

**Interfaces:**
- Consumes: `PromptBuilder` and `AiGateway`, which already provide the real forwarding APIs.
- Produces: no new API.

- [ ] **Step 1: Inline the two chat forwarding calls while tests are green**

Replace `ChatRequestFactory().build(...)` with `PromptBuilder.buildChatRequestMessages(..., useFullContext: _character.useFullChatContext)` and replace `CharacterChatService(...).stream(...)` with `widget.aiService.streamMessage(...)`, retaining `maxTokens: 800` and the existing usage callback.

- [ ] **Step 2: Delete wrapper-only tests/files and empty parts**

Remove wrapper imports/tests from `chat_services_test.dart`, remove wrapper exports from `prompts.dart`, remove the listed files, and remove the four matching `part` directives from `novel_screens.dart`. Keep `novel_analysis_dialog.dart` and all non-empty widget parts.

- [ ] **Step 3: Cache dynamic translation regular expressions**

Move each literal `RegExp(...)` in `_dynamicEn` to a library-level `final` such as:

```dart
final _parsedFieldsPattern = RegExp(r'^已识别 (\d+) 个字段$');
```

Then use `_parsedFieldsPattern.firstMatch(text)`. Do not change the patterns, translations, `_en` map, or ARB resources.

- [ ] **Step 4: Format and run focused regression tests**

Run: `dart format lib test`

Run: `flutter test test/chat_services_test.dart test/localization_test.dart test/novel_analysis_service_test.dart test/novel_import_flow_test.dart`

Expected: PASS with no missing imports or `part` errors.

- [ ] **Step 5: Commit**

Commit: `git add -A && git commit -m "refactor: remove unused forwarding layers"`

---

### Task 6: Full verification and release builds

**Files:**
- Verify all intended source/test/doc changes.

**Interfaces:**
- Produces: a clean, analyzed, tested codebase plus arm64 APK and Windows release artifacts.

- [ ] **Step 1: Static verification**

Run: `dart format --output=none --set-exit-if-changed lib test`

Run: `flutter analyze`

Expected: both exit 0 with no findings.

- [ ] **Step 2: Full test suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 3: Build the requested 64-bit small APK**

Run: `flutter build apk --release --target-platform android-arm64 --split-per-abi`

Expected artifact: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

- [ ] **Step 4: Build Windows release**

Run: `flutter build windows --release`

Expected: exit 0 and release files under `build/windows/x64/runner/Release`.

- [ ] **Step 5: Inspect final diff and status**

Run: `git diff HEAD~5 --stat`

Run: `git status --short`

Expected: only intended committed changes; build output remains ignored.
