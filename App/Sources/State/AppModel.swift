import Combine
import Foundation
import Match3Core

struct ProgressData: Codable, Equatable {
    var unlockedLevel = 1
    var stars: [Int: Int] = [:]
    var bestScores: [Int: Int] = [:]

    static let empty = ProgressData()
}

/// JSON in Application Support. Synchronous and tiny, so no actor needed.
final class ProgressStore {
    private(set) var data: ProgressData
    private let url: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("EmojiMatch", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("progress.json")

        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ProgressData.self, from: raw) {
            data = decoded
        } else {
            data = .empty
        }
    }

    func record(levelID: Int, score: Int, stars: Int, unlockedLevel: Int) {
        var next = data
        next.stars[levelID] = max(next.stars[levelID] ?? 0, stars)
        next.bestScores[levelID] = max(next.bestScores[levelID] ?? 0, score)
        next.unlockedLevel = max(next.unlockedLevel, unlockedLevel)
        data = next
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: url, options: .atomic)
    }
}

final class AppModel: ObservableObject {
    @Published private(set) var progress: ProgressData
    @Published private(set) var engine: GameEngine?

    let levels: [Level]
    private let store: ProgressStore

    init(store: ProgressStore = ProgressStore()) {
        self.store = store
        levels = LevelCatalog.load()
        progress = store.data
    }

    func isUnlocked(_ level: Level) -> Bool {
        level.id <= progress.unlockedLevel
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

    func start(_ level: Level) {
        engine = GameEngine(level: level)
    }

    func exitGame() {
        engine = nil
    }

    func recordResult(level: Level, score: Int, stars: Int) {
        store.record(levelID: level.id,
                     score: score,
                     stars: stars,
                     unlockedLevel: min(levels.count, level.id + 1))
        progress = store.data
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
