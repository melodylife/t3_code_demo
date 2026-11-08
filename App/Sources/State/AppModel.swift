import Combine
import Foundation
import Match3Core

final class AppModel: ObservableObject {
    @Published private(set) var progress: CampaignProgress
    @Published private(set) var engine: GameEngine?
    @Published var saveWarning: String?

    let levels: [Level]
    private let store: CampaignProgressStore

    init(store: CampaignProgressStore = CampaignProgressStore()) {
        self.store = store
        levels = LevelCatalog.load()
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

    func level(withID id: Int) -> Level? {
        levels.first { $0.id == id }
    }

    var nextCampaignLevel: Level? {
        guard let id = progress.nextUncompletedLevelID(from: levels.map(\.id)) else { return nil }
        return level(withID: id)
    }

    func start(_ level: Level) {
        engine?.resetTransientState()
        let nextEngine = GameEngine(level: level)
        nextEngine.onSettledCampaignOutcome = { [weak self] outcome in
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
        record(.init(level: level,
                     score: score,
                     stars: max(1, stars),
                     completed: true))
    }

    private func record(_ outcome: GameEngine.SettledCampaignOutcome) {
        let unlocked = outcome.completed
            ? min(levels.count, outcome.level.id + 1)
            : progress.unlockedLevel
        let result = store.record(levelID: outcome.level.id,
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
