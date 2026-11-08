import Combine
import Foundation
import Match3Core

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var progress: CampaignProgress
    @Published private(set) var engine: GameEngine?
    @Published var saveWarning: String?

    let levels: [Level]
    let dailyPuzzle: DailyPuzzleModel?
    private let store: CampaignProgressStore

    init(store: CampaignProgressStore = CampaignProgressStore(),
         dailyModel: DailyPuzzleModel? = nil,
         levels: [Level]? = nil) {
        self.store = store
        self.levels = levels ?? LevelCatalog.load()
        dailyPuzzle = dailyModel ?? (try? DailyPuzzleModel(
            store: DailyChallengeStore(url: DailyPuzzleModel.defaultStoreURL)))
        progress = store.data
        if let error = store.lastError {
            saveWarning = "Progress could not be loaded: \(error.message)"
        }
    }

    func isUnlocked(_ level: Level) -> Bool {
        level.id <= progress.unlockedLevel
    }

    func isCompleted(_ level: Level) -> Bool {
        progress.isCompleted(levelID: level.id)
    }

    func stars(for level: Level) -> Int {
        progress.stars[level.id] ?? 0
    }

    func bestScore(for level: Level) -> Int {
        progress.bestScores[level.id] ?? 0
    }

    func bestScore(for configuration: GameConfiguration) -> Int {
        switch configuration {
        case let .campaign(level):
            return bestScore(for: level)
        case let .daily(challenge):
            return dailyPuzzle?.records.first { $0.id == challenge.id }?.bestCompletedScore ?? 0
        }
    }

    func level(withID id: Int) -> Level? {
        levels.first { $0.id == id }
    }

    var nextCampaignLevel: Level? {
        guard let id = progress.nextUncompletedLevelID(from: levels.map(\.id)) else { return nil }
        return level(withID: id)
    }

    func start(_ level: Level) {
        start(.campaign(level))
    }

    func start(_ configuration: GameConfiguration) {
        engine?.resetTransientState()
        let nextEngine = GameEngine(configuration: configuration)
        nextEngine.onSettledOutcome = { [weak self] outcome in
            self?.record(outcome)
        }
        engine = nextEngine
    }

    func exitGame() {
        engine?.resetTransientState()
        engine = nil
    }

    /// Compatibility entry point for callers that already have a final result.
    func recordResult(level: Level, score: Int, stars: Int) {
        record(.init(configuration: .campaign(level),
                     score: score,
                     stars: max(1, stars),
                     completed: true,
                     movesUsed: 0))
    }

    private func record(_ outcome: GameEngine.SettledOutcome) {
        if case let .daily(challenge) = outcome.configuration {
            guard let dailyPuzzle,
                  let result = DailyShareResult(challenge: challenge,
                                                completed: outcome.completed,
                                                score: outcome.score,
                                                movesUsed: outcome.movesUsed) else {
                saveWarning = "Daily history could not be saved. Your current result is still available."
                return
            }
            dailyPuzzle.recordSettled(result)
            saveWarning = dailyPuzzle.warning == nil ? nil
                : "Your daily result is safe for this session but could not be saved."
            return
        }
        guard case let .campaign(level) = outcome.configuration, outcome.completed else { return }
        let unlocked = min(levels.count, level.id + 1)
        let result = store.record(levelID: level.id,
                                  score: outcome.score,
                                  stars: outcome.stars,
                                  unlockedLevel: unlocked,
                                  completed: outcome.completed)
        progress = store.data
        switch result {
        case .success:
            saveWarning = nil
        case let .failure(error):
            saveWarning = "Progress is safe for this session but could not be saved: \(error.message)"
        }
    }
}

enum LevelCatalog {
    static func load() -> [Level] {
        guard let url = Bundle.main.url(forResource: "levels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let levels = try? JSONDecoder().decode([Level].self, from: data),
              !levels.isEmpty else {
            assertionFailure("levels.json is missing or malformed")
            return []
        }
        return levels
    }
}
