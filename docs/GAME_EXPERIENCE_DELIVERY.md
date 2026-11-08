# Game experience — integrated delivery

Implements the three features in [the implementation plan](../GAME_EXPERIENCE_IMPLEMENTATION.md) on one branch, `feat/game-experience`, targeting `main`.

## Feature worktrees and integration

All three workers started from `ece4bc145a0f0308670d6570ad01ed72def22f39` in separate T3-managed worktrees:

- **Guided Play:** Antigravity / Gemini 3.8 Flash, branch `t3/guided-play-hints`. Original commit `d3b26fa`; integrated as `af47e24`.
- **Star Chase:** Codex / GPT-5.6 Sol, branch `t3/implement-star-chase`. Original commit `a11ba03`; integrated as `9418dc8`.
- **Daily Puzzle:** Pi / GPT-6.1 Sol, branch `t3/daily-puzzle-foundation`. Pi's sandbox could not access the worktree's external Git metadata, so a bounded Codex integration helper recovered the seven new files, checked their SHA-256 hashes against the originals, and committed them as `8785edd`.

The parent integrated shared session routing, learning presentation, input gates, fractional cascade feedback, migration-safe progress, Xcode membership, and integration tests. Only the unified branch is published; feature worktrees are retained, not removed or force-modified.

## What to try

### Guided Play

First play shows the objective and offers **Start** or **Skip Tips**. Start opens the isolated practice board when needed; its moves and score do not affect a campaign or daily session. **How to Play** on the menu or in-game opens the guide and replayable practice. **Hint** highlights and explains a deterministic legal move, preferring unmet collection objectives without consuming RNG.

Special-tile introductions wait until resolution finishes and do not cover the goal-choice/result screen. Tile accessibility elements expose position, fruit, special type, selection, and directional swap actions. Hint pulsing respects Reduce Motion; the first-goal overlay uses semantic text styles and a scrolling fallback.

### Star Chase

A completed objective guarantees and saves the clear before the player chooses **Finish** or **Chase Stars**. Chasing retains the board, RNG, score, and unused moves. Exhausting chase moves cannot turn a clear into a loss. Collection clears earn at least one star; failed attempts show no earned stars. The HUD exposes the next threshold and exact clear multipliers, including fractional values.

Campaign completion is independent of star count. Old saves retain scores, stars, and unlocks, with completion inferred only where the old data proves it. A legacy zero-star clear of the final unlocked level cannot be inferred and is intentionally not fabricated.

### Daily Puzzle preview

Enable **Daily Puzzle preview** in the menu settings. It defaults off pending the manual release checks below; no command-line preference editing is required to try it.

The daily card captures a UTC date/content version, derives a stable seed, and plays fully offline. Retry keeps that captured identity across midnight; a fresh menu launch uses the current UTC day. Completed results and Star Chase improvements use a separate, bounded daily JSON store and cannot unlock campaign levels or change campaign stars. Results offer **Retry Daily**, **Share Result**, and **Level Select**, with no campaign Next Level action. Share text excludes the board and seed. Unfinished runs are not saved/resumed, and leaving requires an explicit two-action alert.

Seed mapping is specified, but the current generator/resolver use standard-library sampling. The checked-in board/scripted-result goldens must be validated before changing Swift/OS/architecture or daily rules; any behavior divergence requires a new daily content version. This is not an anti-cheat system or a global leaderboard.

## Fresh unified verification

Verified the combined application at `584971d040e75f316ae0be8cd06dab5e2cfe32fa`, not just the isolated feature branches. Subsequent delivery documentation and whitespace-only cleanup do not change executable behavior.

- `xcodegen generate`: succeeded; the generated project includes GuidedPlay sources, the native unit-test target, and both UI-test files.
- `swift test --package-path Packages/Match3Core`: **83 passed, zero failures**. Includes rule regressions, hint legality/determinism, campaign migration/state transitions, UTC/seed goldens, daily persistence, and a 366-date/two-strategy replay corpus.
- Clean iOS simulator app build: **succeeded**.
- Native `EmojiMatchTests`: **14 passed, zero failures, zero skipped**. Tests cover learning isolation/gating and actual engine/app routing, guaranteed clears, safe chase completion, same-level replay identity, daily/campaign save separation, and retry identity across midnight.
- `EmojiMatchUITests`, serial on iPhone 18 Pro / iOS 27: **4 passed, zero failures, zero skipped**. Covers first-play practice skip without spending campaign moves, requested hints, help/practice navigation, daily exit cancellation/confirmation, and a real Level 1 touch playthrough. That run finished at 1,890 points after seven accepted swaps, with thirteen moves remaining.
- `git diff --check`: passed.

Native tests caught an iOS 27 accessibility interaction issue in the daily exit confirmation: the cancel action of a confirmation dialog was exposed only through an unlabeled dismissal region. The final implementation uses an alert with explicit **Keep Playing** and **Leave Daily Puzzle** actions; the UI suite passed after this fix.

Local artifacts (ignored build products, not PR dependencies):

- `build/review/unified-core-tests.log`
- `build/review/unified-simulator-build.log`
- `build/review/unified-unit.xcresult`
- `build/review/unified-ui.xcresult`
- `build/review/unified-ui-tests-after-fix.log`

Normal verification commands:

```sh
xcodegen generate
swift test --package-path Packages/Match3Core
xcodebuild -project EmojiMatch.xcodeproj -scheme EmojiMatch \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

The parent Pi sandbox could not run ordinary SwiftPM/Xcode test launches or atomic host-temp writes. It did freshly compile/typecheck the complete app and test sources with explicit simulator module/framework paths. The Codex verification helper then ran the fresh standard core/build/native/UI commands successfully. Root SourceKit lacked Xcode package/test-framework context for some files; these context-only diagnostics were dispositioned against real compiler/build evidence, not hidden by source ignore comments.

## Remaining manual release checks

Not claimed as verified: physical device play, complete VoiceOver operation, airplane-mode device play, manual large-text/Reduce Motion inspection, or the completed-daily native share-sheet/cancel flow. Keep Daily Puzzle opt-in until these checks and clean-install iOS golden comparisons are complete. Existing non-fatal diagnostics include main-thread AVAudioSession activation and an unused test-fixture local; no test was skipped to accommodate them.
