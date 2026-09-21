# Four story features implementation ledger

Spec: `F:/Whisnya_四功能_剧情分支_状态卡_回忆册_角色语音_Codex需求文档.txt` (read through EOF).

Goal: deliver checkpoints/isolated branches, per-session state, immutable collections/local PNG export, and system character speech together. Keep version 1.5.2+24 and existing signing. No GitHub writes.

Baseline: clean main 100d009c2fcb1691f2beeeb00e425384e1fe6033. Previous ARM64 APK 21970006 bytes, SHA256 93D1BFEC88C4EC897E545D1C7E33F4970D8C1C2C9BA1A31499DF82595105C62D.

Architecture: retain Flutter JSON storage and existing maintenance/epoch gates. Stable persisted message/candidate identities anchor immutable snapshots. New independent services share the existing JsonFileStore and data epoch. Auxiliary operations never roll back saved formal replies. No database/server/network speech service.

Global constraints: all new optional behavior defaults off; no reasoning in state/speech/share; preserve current inner-voice behavior; branches exclude source summaries/current memories/shared character memories by default; locked snapshots retain access restrictions after source deletion; import invalidates pending work; atomic disk publication and immutable body snapshots; Android/Windows bilingual UI; no unrelated dependency upgrades.

Ownership and interfaces:
- Root: `MessageAnchor` in `lib/models/message_anchor.dart` with sessionId/messageId/variantId/prefixDigest, toJson/fromJson, static capture(sessionId, messages, index), matches(messages). Message and variant id fields default empty; storage persists legacy migration. `StoryAccess` is a short-lived explicit authorization grant, never inferred from source deletion. Core storage, branch model/service, settings flags, shared completion receipt, chat integration, backup and final builds owned by root.
- State domain: new state models/services/widgets/tests; service takes LocalStorageService, uses appDataDirectory/jsonStore/datasetEpoch. Root supplies anchor model. Expose snapshot/manual update/reconcile/AI refresh with callback gateway and immutable capture; no changes to root-owned files.
- Collection domain: new collection models/services/screens/widgets/tests; same storage facade and anchor model, authorization callback for protected snapshots. Root integrates entry points and backup validators. No changes to root-owned files.
- Speech domain: voice profiles/AppCharacter, new backend/controller/formatter/config widgets/tests, flutter_tts 4.2.5 and platform integration. Root wires settings/chat lifecycle; no edits to ChatScreen/AppSettings/settings screen.

Review focus: stale asynchronous writes, privacy after orphaning, canonical prefix identity, transactional publication, snapshot immutability, bounded image/audio memory, candidate transitions, old data compatibility.

Execution checklist:
- [x] A. Stable IDs, prefix anchors, source and session guards (red/green tests).
- [x] B. Checkpoint snapshots, crash-safe independent branches, memory exclusion and UI.
- [x] C. State persistence, strict parser, revision/lock guards, rollback, UI and prompts.
- [x] D. Collection persistence, privacy, avatars, navigation, bounded PNG editor/export.
- [x] E. Platform system speech, serialization/cancellation, profiles and UI.
- [x] F. Unified formal receipt integration, settings, lifecycle, backups and translations.
- [x] G. Documentation, formatter/analyzer/full tests, Windows build, native Android tests, ARM64 package/signature/hash verification.

Tests: begin each domain with failing behavior tests, then scoped green tests. Integrate and run the full suite. Physical device checks only if attached; distinguish fake/backend and desktop build verification from real device validation. Record exact remaining limitations rather than claiming unverified completion.

Completion evidence: docs/story-features-delivery-2026-09-20.md. Final full suite 555 passed; analysis clean. Physical Android installation/audio/SAF and real Windows audible voice QA remain explicitly unverified (no attached Android device).

Independent review found and fixed: duplicate branch dropped isolation flags; fork preflight authorization could become stale; post-publication journal cleanup could misreport failure; checkpoint publication could leave orphan payload; state clear/delete was outside recoverable session transaction. Added failure/recovery and real full-backup integration tests. No Git commits, pushes, or release mutations performed.
