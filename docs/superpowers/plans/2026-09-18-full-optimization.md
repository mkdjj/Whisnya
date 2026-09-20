# Full optimization implementation plan

Spec: `F:/Whisnya_全项优化_版本不变_ARM64_Codex任务单.txt` (user-authorized requirements).

Baseline: bd0238f, clean worktree, version 1.5.1+23. No commits, pushes, dependency upgrades, QQ notification restoration or destructive data migrations.

Architecture: retain Flutter, JsonFileStore, local JSON and the existing HTTP runner. Session operations share ordering and recoverable journals; backup uses an exclusive dataset maintenance gate and epoch. Structured AI responses keep content, public reasoning and fictional inner voice separate. Rendering owns a local draft, persisted only on finalization.

- [x] A: Capture toolchain/version/signing diagnostics in build/optimization_report; assert exact version before/after build. Existing signing configuration is absent; check toolchain and retain explicit signing blocker if unavailable.
- [x] B: Session storage agent implements clear-preserving-summary transaction, nullable messageCount and bounded list backfill. Test write failures, restart, deleted target and metadata races.
- [x] C: AI protocol agent implements typed deltas/responses and model compatibility. Test mixed SSE fields, usage-only, old JSON and independent selected candidates.
- [x] D: Main integrates structured events, local draft notifier and finalization with interrupted/unsaved states. Test network tail flush, candidate failure, stale operations and dataset epoch.
- [x] E: Main implements character recovery resolver using session mapping/metadata, conflicts and one-time recovery. Test grouping, old format, corruption and deliberate deletion.
- [x] F: Backup agent implements file streams, safe validation, consistent snapshots, secret handling, rollback transaction and native Android copy. Test each failure boundary and large disk sample.
- [ ] G: Main implements signed ARM64 build/verification script; run format, analyze, full tests, Android/Windows checks when possible. Deliver actual verified APK only if signing available; report every remaining gap honestly.

Each implementation starts with failing behavioral regression tests; independent files are assigned to parallel agents using dispatching-parallel-agents. Main reviews diffs and integration, then performs full regression. Shared storage interfaces are agreed before integration. Progress and command evidence live in build/optimization_report.

G code/tooling is implemented. Final full regression: analyze clean, 493 tests passed (no skips), Windows debug and Android native unit tests passed. Independent delivery review's legacy-array recovery issue was fixed with an end-to-end regression and re-reviewed as resolved. Release script and actual ARM64 release command explicitly stop at missing signing configuration. APK delivery remains unchecked, not disguised as completion. Full evidence: build/optimization_report/FINAL_REPORT.md; no old/debug APK is delivered as a new release.
