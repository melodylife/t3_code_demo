# EmojiMatch — Player Experience Improvements

Three small, self-contained features to improve the in-session player experience. Each is designed around the existing architecture: SwiftUI owns the HUD, `GameScene` owns the board mirror and RNG, and `GameEngine` owns score/moves/tracker/phase. Because `Board`, `SplitMix64`, `ObjectiveTracker`, and `StarChaseState` are all value types, snapshot-and-restore features stay cheap and low-risk.

---

## Feature 1 — Undo Last Move

### Player benefit

A single mistap — especially during a drag that slips one cell too far — currently costs a move with no way to take it back. For a moves-limited match-3 game that feels punishing. A one-step **Undo** lets players recover from accidental input immediately, without rethinking strategy or exiting the level.

### How it works

- A new **Undo** button sits in the HUD next to **Hint**.
- It is enabled only when:
  - the board is settled (`GameScene.isSettled`),
  - the engine is still in `phase == .playing` (not `starChase`, `goalReached`, or a final result),
  - no cascade is resolving, and
  - a snapshot exists for the most recent move.
- Undo restores the exact state from before the last accepted swap and gives the spent move back. It is one-level-deep: undoing twice in a row is not allowed until another move is made.
- Invalid swaps (rejections) never create a snapshot, so Undo cannot accidentally re-trigger them.

### Implementation (all value types — no deep copies needed)

1. **`GameScene.swift`** — add a lightweight snapshot and capture/restore pair:

   ```swift
   struct Snapshot {
       let board: Board
       let rng: SplitMix64
   }

   func captureSnapshot() -> Snapshot { Snapshot(board: board, rng: rng) }
   func restore(_ snapshot: Snapshot) {
       board = snapshot.board
       rng = snapshot.rng
       syncAllNodes()          // existing method rebuilds the sprite table
   }
   ```

   Capture it at the very top of `commitSwap(from:to:)`, **before** `Resolver.resolveSwap` advances `rng` and before `gameDelegate?.sceneDidConsumeMove()` is called.

2. **`GameEngine.swift`** — add a combined `UndoSnapshot` that also captures the engine side:

   ```swift
   struct UndoSnapshot {
       let scene: GameScene.Snapshot
       let score: Int
       let movesLeft: Int
       let tracker: ObjectiveTracker
       let chaseState: StarChaseState
   }
   ```

   - Expose a `captureUndoSnapshot()` that pulls the scene snapshot plus the current `score`, `movesLeft`, `tracker`, and `chaseState`.
   - Expose `undoLastMove()` that restores each field, calls `scene.restore(...)`, sets `isResolving = false`, and refreshes scene input via the existing `refreshSceneInput()`.
   - Add `var canUndo: Bool` that returns `phase == .playing && !isResolving && scene.isSettled && snapshot != nil`.
   - Clear the snapshot in `resetTransientState()` and whenever a new game/session starts, so a stale snapshot can never leak across levels.

3. **`GameScreen.swift`** (HUD) — add an `arrow.uturn.backward` button beside **Hint**, disabled with `!engine.canUndo`, calling `engine.undoLastMove()`. Add an accessibility label ("Undo last move").

4. Wire the snapshot capture so the scene hands its part to the engine at the right instant (a `sceneWillBeginSwap` delegate callback, or have `commitSwap` invoke an `onWillCommitSwap` closure set by the engine). Either way, capture happens atomically before any mutation.

### Acceptance criteria

- After a valid swap and settle, Undo restores the board, RNG, score, collected counts, and move count exactly; a subsequent identical swap reproduces the same cascade (RNG restored).
- Undo is disabled during cascades, in Star Chase, on the goal/final screens, and when no prior move exists.
- Rejected swaps never enable Undo.
- No snapshot survives a restart or level change.

---

## Feature 2 — In-game Restart

### Player benefit

Right now the only way to retry a level is to back out to the menu and tap the level again — two taps and a full screen transition, plus a daily-puzzle confirmation dialog. A one-tap **Restart** in the HUD lets players immediately reset a run they've botched (bad opening moves, wasted specials) without leaving the board.

### How it works

- A **Restart** button (`arrow.counterclockwise`) is added to the HUD row that currently holds **Hint** and **How to Play**.
- **Campaign levels:** tapping it immediately starts the same level fresh — identical seed, so the same starting board, but a clean slate for score, moves, and objectives.
- **Daily puzzle:** it re-runs the *captured* daily configuration (same identity as the existing **Retry Daily** path), never re-deriving today's date — consistent with the current midnight-safe behavior.
- The button is disabled while a cascade is resolving (same guard as the existing exit button's `engine.isResolving`).

### Implementation

1. **`GameScreen.swift`** — add a `restart()` helper next to the existing `requestExit()`:

   ```swift
   private func restart() {
       guard !engine.isResolving else { return }
       app.start(engine.configuration)   // campaign: same level; daily: captured challenge
   }
   ```

   `AppModel.start(_ configuration:)` already tears down the old engine (`resetTransientState`) and builds a fresh one, so no new engine logic is required.

2. **HUD** — add the button alongside the existing `Button(action: requestHint)` / `Button(action: openHelp)` row, using `.buttonStyle(.bordered)`, disabled with `engine.isResolving`. Add `accessibilityIdentifier("restartButton")`.

3. (Optional, recommended) For daily mode, show a one-line confirmation first, reusing the existing `DailyPuzzleExitConfirmation` pattern, so a mid-run restart can't be triggered by a stray tap. Campaign restarts stay immediate.

### Acceptance criteria

- Campaign restart returns to the same level with score 0, full moves, and no collected objectives; the level-select back button still works.
- Daily restart replays the captured challenge identity and records to the daily store exactly like **Retry Daily**.
- Restart is ignored while a cascade is resolving.

---

## Feature 3 — Live Best Score + "New Best" Celebration

### Player benefit

Personal bests are currently invisible until the result screen. Players have no idea, mid-run, whether they're close to beating their record, which removes the drive to keep a good run going. Showing the best score live on the HUD — and celebrating the moment it's passed — turns every clear into a small competition against yourself.

### How it works

- The HUD shows a compact **BEST: <value>** line under the current score.
- When the running score first exceeds the stored personal best (and the best is nonzero, so first-ever plays stay quiet), the game fires a one-time celebration: a brief "NEW BEST!" badge near the score, a success haptic, and the existing win sound.
- The celebration fires once per session, then the HUD simply keeps the live best value (now equal to the current score).

### Implementation

1. **`GameScreen.swift`** (HUD) — `AppModel.bestScore(for: engine.configuration)` already returns the right value for both campaign and daily. Add:

   ```swift
   private var personalBest: Int { app.bestScore(for: engine.configuration) }
   ```

   Render `BEST: \(personalBest)` as a small secondary caption under the score text, with `accessibilityIdentifier("bestScoreValue")`.

2. **Celebration state** — track a `@State private var celebratedNewBest = false` in `GameScreen` (or a `didCelebrateNewBest` flag on the engine). In `.onChange(of: engine.score)`:

   ```swift
   if !celebratedNewBest, personalBest > 0, engine.score > personalBest {
       celebratedNewBest = true
       Haptics.success()
       SoundPlayer.shared.play(.win)
   }
   ```

   Reset the flag on engine change (`app.engine?.sessionID` already drives view identity, so a fresh `GameScreen` starts with `false`).

3. **Badge** — reuse the existing `ClearFeedbackView` styling (a `Capsule().fill(Theme.card)`) to show a `"NEW BEST!"` pill for ~1.5 s, animated with the same `.scale.combined(with: .opacity)` transition already used for clear feedback. Respect `accessibilityReduceMotion` by dropping the scale.

### Acceptance criteria

- The HUD best value updates correctly for campaign and daily configurations.
- "NEW BEST!" triggers exactly once per session, only when the previous best was positive and is actually exceeded.
- No celebration on first-ever clears (best is 0), and none in Star Chase replays that already exceeded the best earlier in the same run.
