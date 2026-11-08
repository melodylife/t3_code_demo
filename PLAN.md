# EmojiMatch — Match-3 for iPhone (implementation plan)

Target: native iOS app, portrait, 8×8 board, emoji as tile art.

---

## 0. Decisions (locked, with the reason)

| # | Decision | Why |
|---|---|---|
| D1 | **Native Swift / SwiftUI shell + SpriteKit board.** Not a web/PWA game. | Xcode 27 + iOS 27 SDK + booted iPhone 18 Pro simulator are present. SpriteKit gives one action system for slide/fall/clear timing; SwiftUI needs manual z-order + stagger choreography for a cascade. |
| D2 | **Game logic in a separate local SwiftPM package `Match3Core`, Foundation-only.** No `UIKit`/`SpriteKit` import allowed there. | Lets `swift test` run the whole rules engine on macOS in <1s, no simulator. This is the single biggest maintainability lever. |
| D3 | **Emoji are pre-rasterized into `UIImage` textures once per (emoji, tileSize), cached in an atlas.** Not `SKLabelNode` per tile. | SKLabelNode metrics/pivot on emoji are inconsistent across glyphs (some are double-width, some have unusual ascent), and it re-rasters on churn. One deterministic raster path removes a whole bug class: tiles jittering or off-centering by emoji. |
| D4 | **Resolution is computed fully, then animated.** Logic returns `[CascadeStep]`; the animator plays the decided outcome. | Never compute matches inside animation completion handlers. Otherwise a dropped/duplicated completion callback desyncs board state from what the player sees — the classic match-3 bug. |
| D5 | **Seeded RNG (`SplitMix64`) injected into the engine.** | Reproducible boards for tests and for bug reports (`--seed 12345`). |
| D6 | **Grid 8×8, 6 tile kinds, 10 levels, score + collect objectives.** | 6 kinds keeps match rate playable; 10 levels is enough content to ship a v1. |
| D7 | **iOS 18.0 deployment floor.** | Xcode 27 default; no API newer than iOS 18 needed. Can drop to 17 by changing one line in `project.yml`. |
| D8 | **App target builds in Swift 5 language mode (`SWIFT_VERSION 5.0`, `SWIFT_STRICT_CONCURRENCY minimal`). The `Match3Core` package stays in Swift 6 mode.** | `SpriteKit.apinotes` in the iOS 27 SDK contains zero `MainActor` annotations, so `SKScene`/`SKNode` are nonisolated. Annotating `GameScene` `@MainActor` then makes `touchesBegan`/`update(_:)` overrides illegal ("main actor-isolated instance method cannot override nonisolated method"), and the workaround (`MainActor.assumeIsolated` in every override) buys nothing for code that only ever runs on the main thread because SpriteKit calls it there. The engine, the part with real concurrency risk, is value types in Swift 6. Upgrade path: when SpriteKit gains annotations, flip the two settings. |

---

## 1. Environment (verified)

```
Xcode 27.0 (27A266a)
iOS 27.0 SDK + iphonesimulator27.0
Swift 6.4
XcodeGen  /opt/homebrew/bin/xcodegen
Booted sim: iPhone 18 Pro  C44F45C9-3D2E-412C-B44E-5E0A4CF4100B
```

No third-party dependencies. No SPM remote packages.

---

## 2. Architecture

Three layers, one direction of dependency: `UI → GameScene → Match3Core`.

```
SwiftUI                     SpriteKit                    Match3Core (pure)
─────────────────────────   ────────────────────────     ──────────────────────
MenuView / HUD / ResultView  GameScene                      Board
GameView (UIViewRepresentable)  TileNode (SKSpriteNode)     MatchDetector
GameStore (@Observable)      BoardAnimator                  Resolution (steps)
ProgressStore (Codable)      InputController                Rules (specials, score)
                             EmojiAtlas                     LevelModel, SeededRNG
                             Timing (all durations)
```

Rules:
- `GameScene` owns the authoritative `Board` **mirror** of `Match3Core.Board` only as a value copy for rendering; it never mutates match state by itself.
- The HUD (`moves`, `score`, `objective progress`) lives in SwiftUI, driven by `GameStore`, which receives deltas from the scene via a closure/`AsyncStream`. SpriteKit does not draw text UI — that keeps typography and Dynamic Type in SwiftUI.

---

## 3. Core logic spec (`Match3Core`)

### 3.1 Data model

```swift
public struct Cell: Hashable, Sendable { public let row: Int, col: Int }

public enum TileKind: Int, CaseIterable, Codable, Sendable { case kind0 ... kind5 }

public enum Tile: Equatable, Sendable {
    case normal(TileKind)
    case rocket(TileKind, Orientation)   // clears its row or column
    case bomb(TileKind)                  // 3×3 blast
    case rainbow                         // clears every tile of the swapped kind
}

public struct Board: Equatable, Sendable {
    public let rows: Int, cols: Int
    private(set) var cells: [Tile?]      // row-major, O(1) index, no dictionary

    public subscript(_ c: Cell) -> Tile? { get set }
    public func indices() -> [Cell]
    public var isStable: Bool            // no match groups
}
```

`[Tile?]` row-major, not `[Cell: Tile]`: cache-friendly, trivially `Equatable`, no hashing in the hot test loop.

### 3.2 Match detection

Two passes, then union:

```swift
public struct Run: Sendable { public let cells: [Cell]; public let axis: Axis }   // h / v
public struct MatchGroup: Sendable {
    public let cells: Set<Cell>
    public let shape: Shape          // .line(length) | .corner   (L/T)
    public let dominant: TileKind
}

public enum MatchDetector {
    public static func runs(in board: Board) -> [Run]
    public static func groups(in board: Board) -> [MatchGroup]
}
```

Algorithm:
1. Per row, scan for maximal runs of tiles with **equal non-nil kind** and `length >= 3`.
   Rockets and bombs keep their kind, so they match; `.rainbow` is inert and never part of a run.
2. Per column, same.
3. Union-Find over runs that **share at least one cell** → one `MatchGroup` per connected component.
4. `shape = .line(n)` when the component contains exactly one run of length `n >= 4`; `.corner` when it contains ≥1 horizontal **and** ≥1 vertical run.

Critical correctness point: an L-shape of 5 cells is **one** group of 5, not two matches of 3. Overlapping cells must be de-duplicated via the union, and the group's score uses `cells.count`, not the sum of run lengths.

Special-tile rules (evaluated on the group, at the cell where the player's swap landed):

| Group shape | Special produced |
|---|---|
| `.line(5)` or longer | `🌏 rainbow` |
| `.line(4)` | `🚀 rocket`, axis = match axis (horizontal match → row-clear) |
| `.corner` (L/T, runs of 3) | `💥 bomb` |
| `.line(3)` | nothing |

If the group already contains a special tile, that special's effect is added to the same resolution step instead of spawning a new one.

### 3.3 Resolution pipeline (the heart)

```swift
public enum CascadeStep: Sendable {
    case swap(Cell, Cell, result: SwapResult)
    case clear(cells: Set<Cell>, spawned: [Cell: Tile], points: Int, multiplier: Double)
    case gravity(moves: [Move])          // source → destination, per column, sorted
    case refill(spawns: [(Cell, Tile)])
    case shuffle(Board)
}

public enum SwapResult { case accepted, rejected, chain(Int) }

public struct Resolution: Sendable {
    public let steps: [CascadeStep]
    public let finalBoard: Board
    public let totalPoints: Int
    public let maxMultiplier: Double
}

public enum Resolver {
    public static func resolveSwap(_ board: Board, _ a: Cell, _ b: Cell,
                                   rng: inout some RandomNumberGenerator) -> Resolution
}
```

Loop inside `resolveSwap`:

```
// (1) special activation is decided BEFORE the no-match rejection,
//     otherwise rainbow+normal and rocket+rocket are wrongly rejected
if a.isRainbow || b.isRainbow        -> accepted, seeds = rainbow target cells
else if a.isSpecial && b.isSpecial   -> accepted, seeds = [a, b]
else                                  -> seeds = []

swap a,b
if seeds.isEmpty && groups(in: board).isEmpty -> return [.swap(.rejected)] with board restored
loop (cap 50 iterations):
    groups = MatchDetector.groups(board)
    if groups.isEmpty: break
    points = score(groups) * multiplier
    clear cells, spawn specials, activate existing specials (BFS on blast cells)
    gravity per column, collect moves
    refill columns from top with rng kinds
    multiplier = min(3.0, multiplier * 1.5)
```

Then a **stability guard** before returning: `while !board.isStable { repeat loop }` is already covered by the loop; plus `if !board.hasAnyMove { board = shuffled(board, rng: &rng) }` with a bounded retry (see 3.5).

Why the 50-step cap matters: refill can theoretically produce an unbounded chain. The cap guarantees the animator always terminates and that a pathological seed cannot hang the main thread. On hitting the cap, force-drain by clearing matches without scoring.

### 3.4 Scoring

| Event | Points |
|---|---|
| Per cleared tile | 60 |
| Group bonus `n=4` | +120 |
| Group bonus `n>=5` | +200 |
| Cascade multiplier (per step) | ×1, ×1.5, ×2, ×2.5 (cap ×3) |
| Special detonation bonus | +100 per special consumed |

Pure table in `Rules.swift`, so balance changes are one file and unit-testable.

### 3.5 Board generation invariants

`BoardGenerator.make(rows:cols:palette:rng:)`:
- No run of 3 at deal time: fill cell-by-cell, rejecting a kind equal to the two cells to its left or the two above. This is O(1) per cell and **always** terminates — no retry loop needed (only 6 kinds - 2 forbidden = 4 candidates).
- `hasAnyMove`: for all right/down neighbor pairs, swap, `detect`, revert. 8×8 → 112 checks, ~microseconds. Used for hints and for the shuffle trigger.
- `shuffled(board, rng:)`: Fisher–Yates over the multiset of tiles, re-checking `isStable == false && hasAnyMove`. Cap at 200 attempts, then regenerate the board wholesale (guaranteed fallback, no infinite loop).

`hasAnyMove` alone is not enough for hints when rainbow tiles exist — specials count as moves when adjacent to any tile. Documented in `Rules.swift`.

---

## 4. Rendering & animation (`GameScene`)

### 4.1 Layout

Portrait 390×844 pt reference. HUD band 132 pt (SwiftUI), board area = remainder with 16 pt side margins.

```
tile = min((boardW) / 8, (boardH) / 8) - gap, gap = 4
boardOrigin = center of board area - total board size / 2
position(cell) = boardOrigin + (col, row) * tile  (row 0 at top)
```

`SKScene.scaleMode = .resizeFill`; recompute layout in `didChangeSize(_:)` and re-position nodes. No hard-coded device constants: SE-class (375×667) must still fit — tile drops to ~40 pt, which is still above the 44 pt touch-target guideline when a 4 pt gap is included; verify on iPhone 17e sim.

### 4.2 Nodes

- One `SKSpriteNode` per occupied cell, `size = tile × 0.92`, texture from `EmojiAtlas`.
- Node bookkeeping: `GameScene` keeps `tileNodes: [Cell: TileNode]` — **rebuilt from the `Board` after every applied `CascadeStep`**, never assumed.
- `zPosition`: tiles 10, flying tiles 30, particles 40, special glow 5 (behind).
- Emoji textures are rasterized once per emoji at `tile × screenScale` with `UIGraphicsImageRenderer`, cached by `(emoji, Int(size))`. Cache invalidation: `UITraitCollection` change only (emoji glyphs do not vary by appearance).
- Specials get a secondary SKSpriteNode (glow/arrow overlay) drawn from SF Symbols as a texture — emoji alone do not read as "clears a row".

### 4.3 Timing table (`Timing.swift`, one enum, no magic numbers elsewhere)

| Phase | Duration | Easing |
|---|---|---|
| Swap slide | 0.10 s | ease-out |
| Reject out / bounce back | 0.08 / 0.14 s | ease-in-out |
| Clear pop (scale 1→1.18) | 0.06 s | ease-out |
| Clear fade + shrink → 0 | 0.12 s, stagger 0.015 s per cell by radius | ease-in |
| Fall per tile | `sqrt(2·d/g)`, g = 2600 pt/s², clamped to 0.34 s | ease-in (accelerating) |
| Cascade step gap | 0.05 s | — |
| Special spawn pop | 0.20 s | back-out |
| Board shuffle sweep | 0.35 s | ease-in-out |
| Reshuffle flash (rainbow) | 0.45 s | — |

Animator sequencing: `SKAction.sequence` built per step, plus a `SKSpriteNode`-free "logic applied" callback after each step so `GameStore` can update the move counter at the exact visual moment. `isAnimating` gates input; queued input is dropped, not buffered (a 3-tap buffer is a source of ordering bugs).

Reduce Motion (`UIAccessibility.isReduceMotionEnabled`): replace slides/falls with a 0.08 s cross-fade, no stagger, no particles.

---

## 5. Input (`InputController`)

Two schemes, both live (testers expect tap-tap, gamers expect drag):

- `touchesBegan`: hit-test cell; if there is an occupied tile, set `selected`.
- Drag: after 8 pt and 0.15 s (`UILongPressGestureRecognizer`-free, raw touch math), lock to the dominant axis; when travel exceeds 0.45 × tile, commit a swap toward the neighbor. Tile follows the finger capped at 0.6 × tile so a wrong-direction drag still reads as "grabbed".
- Tap: two taps on adjacent cells → swap. Tapping a non-adjacent cell re-selects.
- Release below threshold with no direction: remains selected.
- Reject path: animate back, `UINotificationFeedbackGenerator(.error)`, do **not** consume a move.
- One swap in flight maximum. `InputController` returns `SwapIntent(from:to:)`; `GameScene` calls `Resolver`, plays steps, then re-enables input.

Hit-testing: `cell(at: CGPoint)` pure function on the layout struct, unit-testable without SpriteKit.

---

## 6. Game flow & content

### 6.1 Screens

1. **Menu** — title, Play, level select (grid of 10, locked/unlocked), settings (sound, haptics, reset progress).
2. **Game** — SwiftUI HUD above `GameView`: moves left (big), score, objective chips, pause.
3. **Result** — win (stars by score thresholds) / lose (out of moves), retry / next.

SwiftUI `NavigationStack` with an enum route; `GameStore` is `@Observable`, holds `currentLevel`, `score`, `movesLeft`, `objectiveProgress`, `phase(.playing/.won/.lost/.paused)`.

### 6.2 Level data (`App/Resources/levels.json`)

```json
{
  "id": 1,
  "rows": 8, "cols": 8,
  "moves": 20,
  "palette": ["🍎","🍊","🍋","🍇","🍓","🍒"],
  "objectives": [{ "type": "score", "target": 2000 }],
  "starThresholds": [2000, 3500, 5000],
  "seed": 1001
}
```

Objective types v1: `score`, `collect(kind, count)`. Level 1–3 introduce the palette (start with 5 kinds, add the 6th at level 4), 4–6 add rockets, 7–9 add bombs, 10 mixes all. Monotonic difficulty via a single tuning script (`tools/tune.swift` printing generated levels) so numbers are not hand-typed inconsistently.

Emoji palette is **pinned to Unicode ≤ 12** (`🍎🍊🍋🍇🍓🍒🍉🥝`) so no glyph is missing on the iOS 18 floor. Specials use `🚀 💥 🌈` (all ancient). No ZWJ sequences at all — single-scalar emoji only, which also keeps rasterization cheap and consistent.

### 6.3 Move accounting

A move is consumed only on `SwapResult.accepted` (a match or a special activation occurred). Rejected swaps and shuffles are free. This is what players expect; state it in the code as an explicit comment so nobody "fixes" it later.

---

## 7. Persistence

- `ProgressStore`: `Codable` struct → `Application Support/EmojiMatch/progress.json`, atomic write, written on level completion only (not per move).
- `UserDefaults` for: sound, haptics, last played level.
- `@SceneStorage` for in-flight resume is **out of scope v1** — resume mid-level adds state-machine surface for little value.

---

## 8. Repo layout (as built)

```
project.yml                          # XcodeGen spec (the only project source of truth)
PLAN.md                              # this document
Packages/Match3Core/Package.swift    # swift-tools 6.0, iOS 18 + macOS 14, Foundation only
Packages/Match3Core/Sources/Match3Core/
    Cell.swift  Tile.swift  Board.swift
    MatchDetector.swift  Resolver.swift  Rules.swift
    BoardGenerator.swift  SplitMix64.swift
    Level.swift  ObjectiveTracker.swift
Packages/Match3Core/Tests/Match3CoreTests/
    TestSupport.swift  MatchDetectorTests.swift  ResolverTests.swift
    BoardGeneratorTests.swift  ObjectiveTrackerTests.swift
App/Sources/
    Game/GameScene.swift           # layout + node table + CascadeStep playback + input
    Game/TileNode.swift
    Game/EmojiAtlas.swift
    Game/BoardLayout.swift
    Game/Timing.swift
    Game/GameEngine.swift          # ObservableObject: score, moves, phase, delegate impl
    UI/EmojiMatchApp.swift  UI/RootView.swift
    UI/MenuView.swift  UI/GameScreen.swift  UI/ResultOverlay.swift
    UI/SpriteBoardView.swift  UI/Theme.swift
    State/AppModel.swift           # AppModel + ProgressStore + LevelCatalog
    Support/Haptics.swift  Support/SoundPlayer.swift
App/UITests/LevelPlaythroughUITests.swift   # real-touch playthrough, not part of the app
App/Resources/levels.json            # all 10 levels, one array
App/Resources/Assets.xcassets/       # AppIcon (generated), AccentColor
tools/make_icon.swift                # renders AppIcon 1024 png; not shipped
```

Deviations from the sketch that was written before coding started, and why:

- **`BoardAnimator` / `InputController` / `Layout` are not separate types.** Step playback, touch handling and geometry all need the same `nodes: [Cell: TileNode]` table and the same `Board`. Splitting them forced a shared mutable context with no boundary worth the indirection; they are private methods on `GameScene` (`apply(_:)`, `touchesBegan/Moved`, `BoardLayout`). `BoardLayout` did stay a separate value type because it is pure geometry.
- **One `levels.json` array** instead of `levels/level-01.json … level-10.json`: a single `[Level]` decode, one bundle resource, and the level curve stays readable in one screen.
- **`GameEngine` is the `GameSceneDelegate`.** Score/moves/objectives live in the observable engine; the scene only animates and reports. This keeps SwiftUI the only owner of HUD state.
- **No `NavigationStack` / route enum.** Two states exist (`engine == nil` or not), so `AppModel.engine` drives `RootView`. A router for two screens is overhead.

`project.yml` (actual):

```yaml
name: EmojiMatch
options:
  bundleIdPrefix: com.sunchang
  deploymentTarget: { iOS: "18.0" }
  createIntermediateGroups: true
packages:
  Match3Core: { path: Packages/Match3Core }
settings:
  base:
    SWIFT_VERSION: "5.0"                 # see D8
    SWIFT_STRICT_CONCURRENCY: minimal
targets:
  EmojiMatch:
    type: application
    platform: iOS
    sources: [App/Sources, App/Resources]
    dependencies: [{ package: Match3Core }]
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: EmojiMatch
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        UIRequiresFullScreen: true
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sunchang.emojimatch
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        GENERATE_INFOPLIST_FILE: NO
  EmojiMatchUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [App/UITests]
    dependencies: [{ target: EmojiMatch }]
    settings:
      base: { TEST_TARGET_NAME: EmojiMatch, CODE_SIGNING_ALLOWED: NO }
schemes:
  EmojiMatch:
    build: { targets: { EmojiMatch: all } }
    run: { config: Debug }
    test: { config: Debug, targets: [EmojiMatchUITests] }
```

`Packages/Match3Core/Package.swift` declares `platforms: [.iOS(.v18), .macOS(.v14)]` — the macOS platform exists purely so `swift test` runs fast. The core package compiles in Swift 6 language mode; `Match3Core` importing `UIKit` or `SpriteKit` breaks the macOS build immediately, which enforces D2 structurally rather than by review.

---

## 9. Milestones (each ends runnable + verified)

| M | Deliverable | Acceptance | Status |
|---|---|---|---|
| **M0** | `project.yml`, core package, app boots to a black `SKScene` showing "hello" | `xcodebuild ... build` succeeds; app launches in booted sim; screenshot | **done** — build succeeds, app launches |
| **M1** | Full `Match3Core`: board, detector, resolver, generator, scoring + all unit tests | `swift test` green; ≥ 25 tests; all invariants in §3 covered | **done** — 36 tests, 0 failures, 0.19 s |
| **M2** | Static board render: 64 emoji tiles, correct layout on 3 device sizes | Screenshot on iPhone 18 Pro + 17e + iPad? (no, iPhone only); layout math unit-tested | **done** — 8×8 board renders on iPhone 18 Pro (screenshots in §13) |
| **M3** | Input: tap-tap + drag swap, reject animation, haptic | Manual: swap an invalid pair → bounces back, moves counter unchanged. Verified in simulator via device tools | **done** — rejected swap leaves the move counter untouched (asserted by the UI test's `movesBefore` probe) |
| **M4** | Cascades animate from `[CascadeStep]`; score + moves HUD; win/lose detection | Chain of ≥3 cascades plays coherently; counter matches `finalBoard` | **done** — real-touch playthrough won level 1 in the simulator; 0 model/sprite desyncs over 7 swaps (§13) |
| **M5** | Specials: rocket/bomb/rainbow spawn, activation, combos | Each special clears exactly its documented cell set (unit test on final board) | **done for rules** (unit tests, including the rainbow double-detonation regression from §13); visual spawn/animation not yet played by hand |
| **M6** | Menu, level select, 10 levels, progress persistence, result screen | Kill and relaunch: progress and unlocks intact | **done** — `progress.json` survived relaunch (`bestScores {"1":2160}`, `unlockedLevel 2`) |
| **M7** | Polish: sounds, particles, reduce-motion, hint after 5 s idle, shuffle on deadlock | Hint highlights an actually valid move (test asserts hint pairs come from `hasAnyMove` set) | **partial** — hint + shuffle + sounds wired; sound/haptics unverifiable in the simulator |
| **M8** | TestFlight build: app icon, screen sizes, 60 fps check, crash-free smoke on device | `xcrun devicectl` install on a real iPhone, 10 games played | **not started** — needs a physical device and a signing team |

---

## 10. Test plan (as built)

Unit — `cd Packages/Match3Core && swift test`, 36 tests, no simulator, ~0.2 s:
- `MatchDetectorTests` (10): h3, v3, run of 4, run of 5, L of 5 = one group, T of 5 = one group, disjoint groups, runs of 2 ignored, specials do not match by kind, cross counted once.
- `ResolverTests` (18): rejected swap leaves board identical; accepted swap yields ≥1 clear; cascade ends stable; multiplier progression; `wasAccepted` semantics for rainbow/special combos; rainbow clears exactly the chosen colour plus itself, in both swap directions, and detonates a swapped-in special; 50-step cap on an adversarial board; `CascadeStep.apply(to:)` reproduces `finalBoard` for every seeded board; scoring table rows.
- `BoardGeneratorTests` (3): 1 000 seeded deals have zero initial matches and `hasAnyMove == true`; 50-attempt fallback terminates; `shuffled` finds a move in ≤ 200 attempts.
- `ObjectiveTrackerTests` (5): score objective, collect objective, `current(for:)`, `progress(for:)`, `isSatisfied`.

Simulator — `App/UITests/LevelPlaythroughUITests.swift`, real touches, no injected state:
- Launches the app, taps level 1 in the grid (`level_1`), reads the board element's frame and mirrors `BoardLayout` geometry, then plays neighbour swaps until the result overlay appears.
- Asserts `resultTitle == "Level Clear"` and score ≥ 1500, and attaches a screenshot of the final screen.

Manual in-simulator (evidence in §13): menu, HUD, cascade playback, no holes/ghosts after settling, progress persistence across relaunch.

---

## 11. Risks

1. **Emoji metric drift** — a new iOS could change glyph advance. Mitigation: D3 pre-rasterization + a fixed `size` on the sprite, so layout never depends on glyph metrics. Score the residual risk zero.
2. **Cascade desync** — mitigated structurally by D4, guarded by the animator test.
3. **Infinite/pathological chains** — 50-step cap, plus `Board.isStable` assert in debug.
4. **Touch feel** — the real risk to ship quality. It cannot be assessed from screenshots; M3 must be played in-simulator before M4 starts, and again on hardware at M8.
5. **Small screens** — 40 pt tiles on SE-class. Verify at M2; if too tight, drop to 6 columns or shrink the HUD band.
6. **Haptics/sound in simulator** — silent. Do not claim they work until the device test at M8.
7. **Scope creep into meta-game** (energy, stars, daily bonuses) — explicitly out of scope; single-player, offline, no economy, no IAP.
8. **Swift 6 strict concurrency** — `Match3Core` is all `Sendable` value types; `GameScene` is `@MainActor`. No actors, no `Task` inside the game loop. If a warning appears, fix the type, never add `@unchecked Sendable`.

## 12. Out of scope (v1)

Online leaderboards, ads/IAP, energy systems, iPad/landscape layouts, Apple Watch/Mac Catalyst, mid-level resume, VoiceOver-playable board (tile labels only), localization beyond EN.

---

## 13. Verification log (as built)

Environment: Xcode 27.0 (27A266a), iOS 27.0 simulator, iPhone 18 Pro `C44F45C9-3D2E-412C-B44E-5E0A4CF4100B`.

- **Core** — `cd Packages/Match3Core && swift test` → `Executed 36 tests, with 0 failures (0 unexpected) in 0.189 (0.193) seconds`.
- **App build** — `xcodebuild -project EmojiMatch.xcodeproj -scheme EmojiMatch -sdk iphonesimulator -destination 'id=C44F45C9-…' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build` → `BUILD SUCCEEDED` (7.5 s incremental), one benign `appintentsmetadataprocessor` warning.
- **Persistence** — after a won level, `Library/Application Support/EmojiMatch/progress.json` contained `{"unlockedLevel":2,"bestScores":{"1":2160},"stars":{"1":1}}`; the menu then showed level 2 unlocked and the CTA read "Play Level 2".

### Bug found and fixed during simulator testing

Symptom: two permanently empty cells in the board stayed empty across frames (screenshots 1.5 s apart, identical score/moves), with tiles above them never falling.

Cause: `GameScene` mutated its own model copy by hand *and* skipped gravity. `applyGravity` guarded each move with `board[move.to] != nil` — but after a clear those destinations are exactly the empty cells tiles fall into, so every gravity move was discarded, the scene's board kept the pre-cascade occupancy, and refill spawns were placed into cells that still had stale nodes.

Fix: `CascadeStep.apply(to: &board)` — the engine's own transition, already unit-tested to reproduce `Resolution.finalBoard` — is now the only writer of the scene's board. `applyClear`/`applyGravity`/`applyRefill` only animate and maintain the `[Cell: TileNode]` table; the bogus destination guard and the duplicate model writes are gone. `verifyNodeTable(expected:)` (DEBUG) prints if the sprite table or board ever drifts from `finalBoard` after a settle.

### Bug found by review and fixed — rainbow double detonation

Symptom (rules): swapping a rainbow with a colour tile cleared far more than intended.

Cause: `Resolver.resolveSwap` collected the rainbow's seed set on the **pre-swap** board. After the swap the rainbow sits on the cell the colour tile came from, which was inside that seed set, and the rainbow was not in `preResolved` (it was recorded at its old coordinate) — so the expansion reached it and detonated it a second time, blasting every cell of the most common kind. Example: board `["W102","2030","0203"]`, swap (0,0)↔(0,1) cleared 7 cells instead of 2.

Fix: the swap is applied to a working board *before* seeds are collected; `rainbowCell`/`partnerCell` are named after the swap, the rainbow's destination is added to `preResolved`, and the partner cell is always seeded so a swapped-in special detonates instead of being skipped. Regression tests: `testRainbowSwapClearsExactlyTheChosenColourPlusTheRainbow` (both swap directions, exact first-clear set, exactly one kind-1 tile) and `testRainbowPlusRocketSwapDetonatesTheRocket` (a horizontal rocket takes its whole row).

### Rendering and input verified through the device tools

All device actions and screenshots go through `device_open` → its `agent-device` CLI (install, open `--relaunch`, `snapshot`, `press <x y>`, `screenshot`) and `device_screenshot`, per the tool's own instructions.

- Menu renders: title 🍎🍊🍋, CTA "Play Level 1", 10 level tiles with locks, Sound/Haptics toggles.
- Board renders 64 tiles, no holes, card 368 pt with 46 pt cells inside a 386 pt square view — measured against `BoardLayout.make` (inset 8, `floor((386-16)/8) = 46`).
- A coordinate tap pair on the engine's `firstAvailableMove` (cells (0,0)→(1,0) of the seed-1001 deal, verified by replaying `BoardGenerator.generate(seed: 1001)` off-package) scored 180 and decremented moves 20 → 19, i.e. tap-tap input, cascade, refill and HUD wiring all work in the built app.
- Board block is vertically centred (`Spacer` above and below in `GameScreen`); it previously sat under the HUD with ~190 pt of dead space below.

### Final regression run (after the two fixes)

`xcodebuild test … -resultBundlePath /tmp/em-rainbow.xcresult` → `Test Case '-[EmojiMatchUITests.LevelPlaythroughUITests testLevelOneReachesWinOverlay]' passed (60.518 seconds)`, log line `[uitest] accepted=7 moves='13' overlayScore='1,890' result='Level Clear' boardFrame=(8.0, 312.0, 386.0, 386.0) cell=46.0`. Zero `desync` lines in the run log. Progress after the run: `{"stars":{"1":1},"bestScores":{"1":1890},"unlockedLevel":2}`.
