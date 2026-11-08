# EmojiMatch — Game Experience Implementation Plan

Status: proposed; no gameplay changes implemented.

This document proposes exactly three features: **Guided Play**, **Star Chase**, and **Daily Puzzle**. They address learning, mastery, and replayability respectively. Implement them in that order, preserving the existing Foundation-only rules package and the resolve-first/animate-second contract.

## Review and playtest basis

### What was inspected and exercised

- Reviewed the SwiftUI menu, HUD, result overlay, progress persistence, SpriteKit input/animation/hints, core board generation, resolution, scoring, objective tracking, shipped levels, and existing tests.
- Inspected a current screenshot of the installed app's menu on the booted iPhone 18 Pro simulator. The menu has ten levels, stars, a continue button, and sound/haptics settings.
- **Native touch playthrough was attempted but blocked**, not passed: Xcode UI-test launch failed with `IDEPseudoTerminalDomain Code 7 / Operation not permitted`. Normal package test builds also encountered sandbox permission errors. No claims about animation quality, touch feel, sound, or VoiceOver usability are based on hands-on play.
- Ran the existing prebuilt core XCTest bundle: **36 tests passed, zero failures**. This verifies that existing binary, not a fresh build of the entire test suite.
- Separately compiled the current core source with `swiftc` and ran a headless playthrough of all ten shipped levels. Each turn chose `Resolver.firstAvailableMove`, replayed every cascade step, updated objectives as the scene does, and checked final-board equality, stability, available moves, and the cascade cap.
- That automated strategy cleared levels 1, 2, 3, 4, 6, and 9, and exhausted moves on 5, 7, 8, and 10. Level 1 finished at 1,530 points after seven moves, leaving thirteen unused. These are deterministic scenario results, **not human difficulty or engagement measurements**.

Local evidence is under `build/review/`: `HeadlessPlaythrough.swift`, `headless-playthrough.log`, `cached-tests.log`, `existing-playthrough.log`, and `current-screen.png`. Build artifacts are supporting evidence, not application dependencies.

### Code-review findings that inform the proposals

**Keep the existing architecture.** `Match3Core` is independent of UIKit/SpriteKit, seeded boards are reproducible, and `CascadeStep.apply(to:)` lets tests verify that animation instructions reconstruct the final board. New features should consume these contracts rather than introduce a second rules engine.

**Learning is mostly implicit.** `GameScene.showHintIfNeeded()` already pulses a legal pair after five seconds, but it uses the first row-major legal move. There is no objective-aware explanation, tutorial, or special-tile guide. Rockets and bombs retain their fruit art with small symbol badges; their meaning is not explained in the UI.

**Mastery and completion are conflated.** `GameEngine.sceneDidSettle` immediately ends play when objectives are satisfied, even with many moves left. `Level.stars(for:)` measures score alone; collection levels can therefore be completed below the first score threshold. `MenuView.nextLevel` treats zero stars as unfinished, and `ResultOverlay` can display earned-looking score stars even on a failed collection attempt. These are source-level concerns; the zero-star-win path was not reproduced in the ten headless scenarios.

**Replay content is finite and repeats.** There are ten catalog levels, and every `GameEngine` initialization starts from that level's fixed seed. `ProgressStore` records only unlocked level, best scores, and stars. There is no separate challenge or daily history.

**Accessibility needs explicit work.** `SpriteBoardView` currently exposes the whole board as one accessibility element named “Match board,” not individual actionable tiles. An instructional overlay alone would not make the game VoiceOver-playable.

---

## Feature 1 — Guided Play: learn mechanics and request useful hints

### Player benefit and experience

Help a new player understand what to do, why a move works, and how special tiles help—without forcing experienced players through a long tutorial.

1. On first play, show the level's actual objective in plain language, such as “Collect 12 apples,” followed by a short explanation of swipe or tap-two-neighbors controls. Include **Start** and **Skip tips**.
2. Teach the first swap with a small deterministic practice board outside campaign scoring. Highlight one legal pair and show a directional arrow; finish as soon as the player makes that swap. Provide a skip action at every step.
3. When a rocket, bomb, or rainbow first appears, queue a one-time explanation for the next settled board. Explain the actual rules: four makes a directional rocket; an L/T makes a bomb; five makes a rainbow. A rocket/bomb is activated by matching it or combining specials, not by any arbitrary normal swap.
4. Add a **Hint** button. It highlights a useful legal move and gives a short reason, such as “Match apples toward your collection goal.” Keep the current idle hint as a subtle fallback rather than pretending it is a new capability.
5. Add **How to Play** to the menu so instructions remain available after dismissal.

### Implementation

**Core — new `Packages/Match3Core/Sources/Match3Core/HintAdvisor.swift`:**

- Enumerate adjacent right/down pairs and filter with `Resolver.isAcceptedSwap`.
- Return a `HintSuggestion` containing source/destination cells and a semantic reason, not localized UI strings.
- Rank by immediate progress on unmet collection goals, then special creation/activation, then immediate clear potential. Tie-break by stable cell order.
- Inspect the post-swap groups and reuse/extract the resolver's initial special-blast calculation where needed. Do not duplicate special rules in SwiftUI.
- Do **not** resolve random future refills to choose the “best” move. Hints must not peek at future RNG or advance the live generator. Start with a bounded first-step heuristic, not a solver.

**Scene and engine — `GameScene.swift`, `GameEngine.swift`:**

- Expose a safe hint-request method; the board remains owned by the scene. The engine supplies unmet objective context and publishes the explanation.
- Only show hints on a settled, input-enabled board. Clear the suggestion on selection, swap, shuffle, restart, exit, or tutorial transition.
- Use one rendering path for idle and requested hints. Reset the idle timer whenever a player requests a hint.
- Deliver special-introduction events after settling; never interrupt a partially applied cascade. Clear drag, selection, and hint state before presenting instruction UI.

**UI and state — `GameScreen.swift`, `MenuView.swift`, plus new `LearningStore.swift` and `HowToPlayView.swift`:**

- Persist tutorial completion and introduced-special flags with versioned keys, separate from campaign progress. Skipping cannot affect score, unlocks, or star awards.
- Let a SwiftUI overlay control tutorial presentation and input gating; do not add tutorial rules to the resolver.
- Add per-cell accessibility elements/actions to the SpriteKit host. Labels include fruit, row/column, special type and rocket direction. Accessible selection of adjacent cells must invoke the same validated swap path as touch.
- Support Dynamic Type and Reduce Motion. Hints need a static outline/arrow and spoken explanation, not pulsing alone. Announce requested hints once, not on every animation frame.

### Acceptance criteria and verification

- A first-time player can learn a swap or skip directly to the real level; replaying never forces the lesson again.
- Every returned hint is legal, leaves board/RNG unchanged, and is deterministic for identical input. Fixtures cover collection goals, completed goals, rainbow swaps, special pairs, and a board with no legal move.
- Unit tests prove ranking favors an immediately useful collection move when one exists and never invents a move that `Resolver` rejects.
- UI tests cover first launch, skip, reopening help, first special introduction, rapid repeated hint requests, and dismissal during navigation.
- Manual simulator/device verification covers swipe and tap input, large text, Reduce Motion, and a complete VoiceOver swap. This remains required because the current environment could not run touch automation.

**Scope and risk:** no hint currency, penalties, or automatic moves. The main risks are duplicating special rules and displaying stale coordinates after a cascade; shared core evaluation and settled-board gating are mandatory. Ship the basic lesson and help first, then enable ranked hints once parity tests pass.

---

## Feature 2 — Star Chase: turn remaining moves into optional mastery

### Player benefit and experience

Make a clear feel like an achievement rather than an abrupt interruption, and let a player use their remaining moves to improve their result.

When all objectives are met, show **“Goal complete!”** with **Finish** and, if moves remain and fewer than three stars have been earned, **Chase Stars**. Finishing immediately grants the clear. Choosing Star Chase resumes the same board with the same RNG, score, and remaining moves. It is optional and never puts the clear at risk.

During play, show the next star threshold and remaining points. During cascades, briefly display the clear's points and multiplier; a long chain should be understandable rather than only making the HUD total jump. The final result distinguishes objective completion, stars, personal best, and the next available action.

### Rules and state transitions

- Introduce explicit phases such as `playing`, `goalReached`, `starChase`, `won`, and `lost`. Replace checks like `phase != .playing` with semantic properties such as `canAcceptMoves` and `showsFinalResult`.
- Evaluate objectives only when the entire resolution settles, as today. If the final move completes the objective, success wins over move exhaustion.
- A campaign clear earns **at least one star**, even when a collection objective finishes below its first score threshold. Two and three stars remain score-based. Failed attempts show no earned stars; any score-tier indicator must be labeled differently.
- In Star Chase, a player may finish at any settled point. Reaching three stars or exhausting moves finishes as `won`, never `lost`.
- Persist the guaranteed clear when `goalReached` is entered, then update best score/stars monotonically during settled Star Chase turns and on finish. Recording the same outcome twice must be harmless. Abandoning or backgrounding a chase cannot revoke a clear.
- Do not add an unused-move bonus in this version. Directly spending remaining moves is easier to understand and avoids simultaneously changing the scoring table.

### Implementation

**Core — `Level.swift` and new `StarRating.swift`:**

- Keep score-tier calculation reusable, but add an explicit campaign-result rating API taking objective completion. Centralize the minimum-one-star rule rather than patching the menu and result UI separately.
- Keep all existing clear/scoring mechanics unchanged. Baseline thresholds should remain unchanged until actual Star Chase playtests justify retuning.

**Engine/scene — `GameEngine.swift`, `GameScene.swift`:**

- Implement a small, tested transition function taking objective satisfaction, moves left, current phase, and player choice. A `.playing → .goalReached` transition disables input only after settling.
- The scene delegate currently discards the multiplier from `.clear`. Pass a structured feedback event containing points, multiplier, and special creation; publish it without recalculating awarded points.
- Drive a short-lived SwiftUI feedback label from those events; keep it outside the board hit area. Cancel its pending dismissal on restart or exit. Respect Reduce Motion and throttle accessibility announcements.

**UI/persistence — `GameScreen.swift`, `ResultOverlay.swift`, `AppModel.swift`, `MenuView.swift`:**

- Add the completion choice and live next-star meter. Disable Finish while a cascade is running; accept it immediately at the next settled boundary if queued.
- Record completion through one engine/app outcome path rather than relying solely on the current `onChange(.won)` callback.
- Store explicit completed-level IDs independently of star count. Make `nextLevel` choose an unlocked, uncompleted level; once all are completed, offer replay intentionally.
- Add backward-compatible decoding: infer prior clears from positive stored stars and levels below `unlockedLevel`; retain all existing best scores and unlocks. The old save cannot prove a zero-star clear of the final level, so do not fabricate that completion. Document this migration limitation.
- Inject the progress file URL for tests; verify atomic writes and corrupt/old-save behavior. A write failure should keep the session playable and surface a non-blocking save warning instead of silently implying durability.

### Acceptance criteria and verification

- The level-1 scenario that currently stops with thirteen unused moves offers a choice; finishing retains its clear, while chasing spends those same remaining moves without resetting the board.
- Unit tests cover the full transition matrix: last-move win, last-move loss, zero-star collection clear, early finish, three-star finish, and move exhaustion during a chase.
- Regression tests cover migration from existing JSON, duplicate result events, non-decreasing best records, and continue-button selection after a collection clear.
- UI tests cover Finish, Chase Stars, replay, Next Level, and leaving/relaunching after the guaranteed clear is saved. Verify overlays block board touches and cannot consume a move underneath them.
- Existing resolver tests must remain unchanged and pass; feedback/UI must not change resolution totals or consume RNG.

**Scope and risk:** no paid extra moves, lives, or consumables. Most risk lies in phase handling and saving completion exactly once. Land and test the result-state model before adding cascade presentation. Star Chase may make higher ratings easier; measure with real players before changing thresholds.

---

## Feature 3 — Daily Puzzle: a fresh, reproducible offline challenge

### Player benefit and experience

Add one short reason to return without requiring an account, network connection, or more campaign levels.

The menu gets a **Daily Puzzle** card showing the UTC date, challenge goal, and today's best completed score. Tapping it starts the same dated puzzle for everyone using the same challenge version. Players can retry without limits, retain their best completed result, and share a spoiler-free text result. The campaign remains unchanged and separately saved.

Use a simple score goal with a fixed move budget for the first version. Reuse Star Chase after the goal is reached so successful runs can compete for a personal best rather than stopping immediately at the target. Show progress for unsuccessful attempts without calling them clears.

### Implementation

**Challenge identity and generation — new `DailyChallenge.swift`:**

- Define `DailyChallengeID` from a Gregorian **UTC** date and an explicit rules/content version. Display the reset convention in the UI; inject a clock and calendar for tests.
- Derive a `UInt64` seed using a documented stable algorithm over the date/version, not Swift's process-randomized `hashValue`. Add golden date-to-seed fixtures.
- Add `GameConfiguration` or a similar session descriptor containing mode, challenge ID, seed, and level-shaped rules. Do not invent a campaign level number and call `recordResult` with it.
- Use the existing generator/resolver and data-driven objectives. Begin with one curated rules template; evaluate many dated seeds before adding rotating goals or palettes.
- Identical seeds are not by themselves a cross-version guarantee: board generation currently uses standard-library random selection/shuffle operations. Lock supported-build reproducibility with board fingerprints and scripted-move golden tests; either adopt an explicitly specified RNG-to-index/shuffle algorithm for daily mode or bump the challenge version when behavior changes. Do not silently alter existing campaign boards as part of this work.

**Session routing — `AppModel.swift`, `GameEngine.swift`, `MenuView.swift`, `ResultOverlay.swift`:**

- Pass the configuration into the engine instead of assuming every game is a campaign `Level`.
- Route daily completion to daily records only. Daily play must never unlock campaign levels, change campaign stars, or navigate to a campaign “Next Level.”
- Freeze date/version/seed at session start. Crossing midnight does not replace the active board; retry from its result screen replays that captured challenge. A fresh menu entry uses the new UTC day.
- Offer Retry Daily, Share Result, and Level Select. Share only date/version, completion, score, and moves used; exclude the seed and board layout. Use the native share sheet and no automatic posting.

**Persistence — new `DailyChallengeStore.swift`:**

- Keep versioned daily records separate from `ProgressData`: ID, completion flag, best completed score, and moves used for that best run.
- Persist only settled outcomes; retries cannot lower a best. Store a bounded history, such as the most recent 90 dates, and make duplicate saves idempotent.
- An interrupted unfinished attempt is not a completion. Initial scope does not promise mid-board resume; state that plainly in the UI before leaving an active daily game.
- Remain fully offline. Device-clock changes can select different dates; do not claim anti-cheat, global fairness, or a verified leaderboard. A server-authoritative competition would be separate work.

### Acceptance criteria and verification

- Two clean installs on the same supported build produce the same initial board and scripted outcomes for a given UTC date/version; the next date has a separately derived identity.
- Tests cover UTC midnight, month/year boundaries, leap day, local timezone/DST differences, an active run crossing reset, clock rollback, version rollover, and malformed/old records.
- Test campaign/daily persistence isolation, unlimited retries, duplicate completion events, best-score retention, and bounded-history pruning.
- Run a large deterministic date corpus through both the first-legal-move strategy and a simple objective-aware strategy. Assert no unstable or dead starting boards, resolution caps, or replay divergence. Use this to detect pathological templates, not to claim human difficulty is balanced.
- UI tests cover the daily card, start, loss, retry, successful finish/Star Chase, share-sheet cancellation, and returning to campaign without unlock changes.
- Before release, manually test on a device in airplane mode and play several dated puzzles. Verify the reset copy and dated result remain clear after midnight.

**Scope and risk:** no backend, notifications, streak penalties, leaderboard, or user accounts. Determinism and date boundaries are the primary technical risks. Ship behind a local feature flag after Guided Play and Star Chase; enable only when cross-install golden tests and offline device checks pass.

---

## Delivery and validation

Each feature should be a separate implementation change with its own tests. Preserve campaign progress and existing seeded behavior unless a change is explicitly versioned. Keep rules in `Match3Core`, session/outcome state in the engine/app layer, and presentation in SwiftUI/SpriteKit.

For each change: run the fresh core suite, app build, targeted UI tests, then manual device checks for interaction, VoiceOver, Reduce Motion, and save/relaunch behavior. The native build/UI-test sandbox blocker recorded above must be resolved before claiming those checks passed. This proposal does not substitute headless scenarios for a native playtest.
