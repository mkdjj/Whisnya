# Whisnya Quality Improvements Implementation Plan

> **For agentic workers:** Execute inline in the current workspace. Do not commit, reset, restore, clean, or overwrite unrelated changes.

**Goal:** Fix media lifetime bugs, persist novel reading progress, complete known English translations, add theater-chat search, and remove duplication only where the new search feature provides a clear net reduction.

**Architecture:** Keep the existing local-first JSON storage and screen structure. Add reference-aware media cleanup in the storage boundary, store reading progress on `NovelBook`, and reuse one small search dialog/helper from both chat screens. Do not add dependencies or introduce a generic appearance-settings abstraction with a large callback surface.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing local JSON storage.

## Global Constraints

- Keep `1.3.8+16`.
- Preserve all existing uncommitted work.
- Add no dependencies.
- Use tests first for every behavior change.
- Do not commit, push, or publish.

---

### Task 1: Reference-aware local cleanup

**Files:**
- Modify: `lib/services/local_storage_service.dart`
- Modify: `lib/services/storage/media_store.dart`
- Modify: `test/media_store_test.dart`
- Modify: `test/local_storage_write_test.dart`

**Interfaces:**
- Produce: `cleanupUnusedMedia(Directory root, Set<String> referencedPaths)`
- Produce: `LocalStorageService.cleanupUnusedMedia()`

- [ ] Add failing tests proving referenced files survive, unreferenced files are removed, character deletion preserves avatars referenced by theater participants, and novel deletion removes its summary cache.
- [ ] Run the focused tests and confirm failures are caused by missing cleanup behavior.
- [ ] Implement path-normalized cleanup under `app_data/media`, excluding `media/temp`.
- [ ] Collect references from settings, characters, theater sessions, and theater participants before deleting.
- [ ] Replace direct character-media deletion with reference-aware cleanup; invoke cleanup after character/theater deletion and delete the novel cache with the novel.
- [ ] Run the focused tests until green.

### Task 2: Persistent novel reading position

**Files:**
- Modify: `lib/models/novel_book.dart`
- Modify: `lib/controllers/novel_reader_controller.dart`
- Modify: `lib/screens/novel/novel_reader_screen.dart`
- Modify: `test/novel_book_round_trip_test.dart`
- Modify: `test/controllers/novel_reader_controller_test.dart`

**Interfaces:**
- Produce: `NovelBook.readingProgress`
- Produce: `NovelReaderController.bookWithReadProgress()`

- [ ] Add failing tests for JSON round-trip, initial controller restoration, progress persistence, and chapter-change reset.
- [ ] Run the focused tests and confirm the new expectations fail.
- [ ] Add a clamped `readingProgress` value to `NovelBook`.
- [ ] Initialize controller progress from the book and return updated books from the controller.
- [ ] Restore the scroll ratio after the reader is laid out and persist it at scroll end.
- [ ] Run the focused tests until green.

### Task 3: Complete known English translations

**Files:**
- Modify: `lib/utils/app_i18n.dart`
- Modify: `test/localization_test.dart`

**Interfaces:**
- Existing: `BuildContext.t(String)`

- [ ] Add a failing widget test for `编辑`, `聊天外观`, `请先到 API 设置添加配置`, and `预览`.
- [ ] Run the test and confirm the four values remain Chinese.
- [ ] Add the four English mappings.
- [ ] Run the localization test until green.

### Task 4: Shared theater-chat search

**Files:**
- Create: `lib/utils/chat_search.dart`
- Create: `test/chat_search_test.dart`
- Modify: `lib/screens/chat/chat_screen.dart`
- Modify: `lib/screens/theater/theater_screens.dart`
- Modify: `lib/screens/theater/theater_chat_screen.dart`
- Modify: `lib/screens/theater/widgets/theater_message_bubble.dart`
- Modify: `test/theater_chat_screen_test.dart`

**Interfaces:**
- Produce: `findChatSearchResults(Iterable<String> contents, String query)`
- Produce: `showChatSearchDialog(...)`

- [ ] Add failing unit and widget tests for case-insensitive matching and highlighted theater results.
- [ ] Run the focused tests and confirm search is absent.
- [ ] Move the existing character-chat dialog and matching loop into the shared helper.
- [ ] Add theater search state, app-bar action, result scrolling, bubble border highlighting, and query text highlighting.
- [ ] Reuse the helper from character chat and remove its duplicated dialog implementation.
- [ ] Run chat and theater focused tests until green.

### Task 5: Documentation and verification

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`

- [ ] Replace the stale `novel_chats/` layout with `novel_summary_cache/`, `theater_sessions.json`, and `theater_messages/`.
- [ ] Run `dart format --output=none --set-exit-if-changed lib test`.
- [ ] Run `flutter test`.
- [ ] Run `flutter analyze`.
- [ ] Run `git diff --check`.
- [ ] Build `flutter build apk --release --split-per-abi --target-platform android-arm64`.
