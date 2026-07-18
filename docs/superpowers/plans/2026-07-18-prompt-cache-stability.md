# Prompt Cache Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize ordinary-chat and theater prompt prefixes without changing selected history, prompt rules, reply counts, or output-token behavior.

**Architecture:** Keep `PromptBuilder` as the single request-assembly point. Ordinary full-context requests omit summary memory; theater requests split stable summary memory from per-turn instructions and append the latter after unchanged history messages.

**Tech Stack:** Dart, Flutter, `flutter_test`.

## Global Constraints

- Do not add `max_tokens`, `max_completion_tokens`, or any output-token limit.
- Do not trim full-context history or change current summary-mode history selection.
- Do not change participant order, reply counts, role permissions, retry, truncation, hiding, streaming, or `theater_participant_reply_sanitizer.dart`.
- Do not add dependencies or storage/UI fields; old data remains readable.
- Submit one commit: `perf: stabilize prompt order for cache reuse`.

---

### Task 1: Ordinary chat request ordering

**Files:**
- Modify: `test/prompt_builder_test.dart`
- Modify: `lib/prompts/prompt_builder.dart:56-79`

**Interfaces:**
- Consumes: `PromptBuilder.buildChatRequestMessages(...)` existing signature.
- Produces: summary mode `[fixed, summary, history...]`; full mode `[fixed, all history...]`.

- [ ] **Step 1: Write failing tests**

Update the full-context test to require no summary message and exact history preservation, and add consecutive-request assertions:

```dart
expect(request, hasLength(messages.length + 1));
expect(request.skip(1), [
  for (final message in messages)
    {'role': message.role, 'content': message.content},
]);
expect(request.toString(), isNot(contains('【动态历史总结】')));
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/prompt_builder_test.dart`

Expected: FAIL because full-context mode currently inserts `buildChatMemoryPrompt`.

- [ ] **Step 3: Implement the minimum conditional element**

```dart
return [
  {'role': 'system', 'content': buildSystemPrompt(character)},
  if (!useFullContext)
    {'role': 'system', 'content': buildChatMemoryPrompt(historySummary)},
  for (final message in requestMessages)
    {'role': message.role, 'content': message.content},
];
```

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/prompt_builder_test.dart`

Expected: PASS.

### Task 2: Theater stable memory and trailing turn instructions

**Files:**
- Modify: `test/prompt_builder_test.dart`
- Modify: `test/theater_reply_engine_test.dart`
- Modify: `lib/prompts/prompt_builder.dart:238-520`

**Interfaces:**
- Consumes: existing theater request-builder signatures and history filtering.
- Produces: `[fixed settings, stable summary memory, history..., dynamic turn instruction]`.

- [ ] **Step 1: Write failing ordering and prefix-stability tests**

For both theater builders, assert summary memory is index 1, old history follows unchanged, and the dynamic instruction is last. Build a second request with one appended message and compare the prior prefix:

```dart
expect(request[1]['content'], contains('【群聊总结】'));
expect(request[2], {'role': 'user', 'content': '[用户] A'});
expect(request.last['content'], contains('【本轮生成意图】'));
expect(after.take(before.length - 1), before.take(before.length - 1));
```

Build a third request with only `session.theaterSummary` changed; assert the fixed settings and history maps remain equal while the summary map changes.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/prompt_builder_test.dart test/theater_reply_engine_test.dart`

Expected: FAIL because dynamic state currently precedes history in one system message.

- [ ] **Step 3: Split stable and dynamic text without rewriting it**

Create `_theaterSummaryMemory(session, novelSummary)` containing only novel summary, theater summary, and context rules. Rename the remaining per-turn assembly to `_theaterTurnInstruction(...)`, preserving its existing wording. Assemble both request types as:

```dart
return [
  fixedSettings,
  {
    'role': 'system',
    'content': _theaterSummaryMemory(session, novelSummary),
  },
  ..._theaterHistoryMessages(messages),
  {
    'role': 'system',
    'content': _theaterTurnInstruction(
      session: session,
      allowed: allowed,
      currentParticipant: currentParticipant,
      generationIntent: generationIntent,
      phase: phase,
      previousOutputInvalid: previousOutputInvalid,
    ),
  },
];
```

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/prompt_builder_test.dart test/theater_reply_engine_test.dart`

Expected: PASS.

### Task 3: Required verification and commit

**Files:**
- Modify only formatting produced by the Dart formatter in touched files.

- [ ] **Step 1: Run required verification**

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Expected: all commands exit 0.

- [ ] **Step 2: Confirm prohibited scope is untouched**

Run: `git diff --name-only` and `rg "max_tokens|max_completion_tokens" lib`.

Expected: only planned prompt/tests/plan files changed; no output-token limit in production code.

- [ ] **Step 3: Commit once**

```powershell
git add docs/superpowers/plans/2026-07-18-prompt-cache-stability.md lib/prompts/prompt_builder.dart test/prompt_builder_test.dart test/theater_reply_engine_test.dart
git commit -m "perf: stabilize prompt order for cache reuse"
```
