import Foundation

/// The single routing discriminator for a session. Campaign levels retain their
/// original id, rules and seed verbatim. A daily retry retains its launch capture.
///
/// ## Shell integration (owned by the parent feature)
///
/// 1. Keep the configuration alongside the engine. Initialize the existing engine
///    with `GameEngine(level: configuration.level)`. Only the enum determines
///    persistence/routing; never infer mode from `level.id` or the seed.
/// 2. In the app, create `DailyPuzzleModel(store: DailyChallengeStore(url:
///    DailyPuzzleModel.defaultStoreURL))` with `try`, handling invalid device dates.
///    Insert `DailyPuzzleMenuCard(model:start:)` only when
///    `DailyPuzzleFeature.isEnabled()`; `start` receives the fresh capture.
/// 3. Switch on configuration at every settled result event. Campaign calls its
///    existing progress path. Daily builds `DailyShareResult(challenge:completed:
///    score:movesUsed:)`, where movesUsed is initial budget minus movesLeft,
///    and calls `dailyModel.recordSettled(result)` ONLY. Persist a guaranteed clear
///    at goalReached and improvements during settled Star Chase/finish. If the
///    record fails, retain the session and show the non-blocking model warning.
/// 4. Use `DailyPuzzleResultActions(result:retry:levelSelect:)` at the final result.
///    Retry passes the same captured challenge; do not call today() or rebuild
///    from the menu's day. Hide campaign Next Level/unlock copy in daily mode.
/// 5. Gate board input at settled exit, then present DailyPuzzleExitConfirmation.
///    Background/foreground must not rewrite active configuration; refresh only
///    the menu model. No unfinished-board persistence is promised.
///
/// ## Version/release policy
///
/// V1 is 8x8, six colors, 20 moves, score goal 1500, tiers 1500/2500/4000.
/// Seed bytes are stable FNV-1a, but existing BoardGenerator and Resolver use
/// stdlib random sampling/shuffle. The checked-in board and five-first-legal-move
/// golden fixtures identify Apple Swift 6.4, Xcode 27.0 (27A266a), arm64 macOS.
/// Before shipping on a new Swift/OS/architecture combination, run those fixtures
/// natively there and compare clean-install boards and scripted results on iOS.
/// Any divergence in sampling, rules, palette, score, dimensions or move budget
/// requires a NEW daily content version and fresh fixtures. Never change campaign
/// generation to make daily fixtures pass. Unknown content IDs remain distinct
/// in history; unknown schema envelopes are not overwritten. There is no v0
/// migration because this is the first daily store, separate from progress.json.
///
/// The local flag defaults OFF. Enable per-device with
/// `UserDefaults.standard.set(true, forKey: DailyPuzzleFeature.defaultsKey)` only
/// after routing/Star Chase integration, cross-install iOS goldens, share cancel,
/// midnight/foreground, VoiceOver/Dynamic Type, and airplane-mode device checks.
/// Corpus strategies are regression probes, not human difficulty evidence.
public enum GameConfiguration: Equatable, Sendable {
    case campaign(Level)
    case daily(DailyChallenge)

    public enum Mode: Equatable, Sendable { case campaign, daily }

    public var mode: Mode {
        switch self {
        case .campaign: return .campaign
        case .daily: return .daily
        }
    }

    public var level: Level {
        switch self {
        case .campaign(let level): return level
        case .daily(let challenge): return challenge.level
        }
    }

    public var dailyChallenge: DailyChallenge? {
        if case .daily(let challenge) = self { return challenge }
        return nil
    }

    public var seed: UInt64 { level.seed }
}

/// Spoiler-free native-share payload. Construct only from a settled result.
public struct DailyShareResult: Equatable, Sendable {
    public let challenge: DailyChallenge
    public let completed: Bool
    public let score: Int
    public let movesUsed: Int

    public init?(challenge: DailyChallenge, completed: Bool, score: Int, movesUsed: Int) {
        guard score >= 0, (0...challenge.level.moves).contains(movesUsed),
              !completed || (movesUsed > 0 && score >= challenge.level.objectives[0].target) else { return nil }
        self.challenge = challenge
        self.completed = completed
        self.score = score
        self.movesUsed = movesUsed
    }

    public var text: String {
        "EmojiMatch Daily Puzzle • \(challenge.id.date) UTC • v\(challenge.id.version)\n"
        + "\(completed ? "Complete" : "Not completed") • Score: \(score) • Moves used: \(movesUsed)/\(challenge.level.moves)"
    }
}
