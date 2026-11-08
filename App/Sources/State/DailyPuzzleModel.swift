import Combine
import Foundation
import Match3Core

/// Opt-in on this build: enable locally only after shell integration and release
/// gates in GameConfiguration's integration notes. No network requests.
enum DailyPuzzleFeature {
    static let defaultsKey = "dailyPuzzle.enabled.v1"
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}

@MainActor
final class DailyPuzzleModel: ObservableObject {
    @Published private(set) var menuChallenge: DailyChallenge
    @Published private(set) var records: [DailyRecord]
    @Published private(set) var warning: DailyStoreWarning?
    private let store: DailyChallengeStore
    private let clock: () -> Date

    init(store: DailyChallengeStore, clock: @escaping () -> Date = Date.init) throws {
        self.store = store
        self.clock = clock
        menuChallenge = try DailyChallenge.today(clock: clock)
        records = store.records
        warning = store.warning
    }

    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("EmojiMatch", isDirectory: true)
            .appendingPathComponent("daily-records-v1.json")
    }

    /// Refresh on foreground and while the menu is visible. Never mutates an
    /// active configuration; the parent owns that immutable launch value.
    func refreshMenu() {
        if let today = try? DailyChallenge.today(clock: clock), today != menuChallenge {
            menuChallenge = today
        }
    }

    /// Re-read the clock at the tap, including a tap at the exact reset boundary.
    func captureForLaunch() throws -> GameConfiguration {
        let challenge = try DailyChallenge.today(clock: clock)
        menuChallenge = challenge
        return .daily(challenge)
    }

    func recordSettled(_ result: DailyShareResult) {
        store.record(result)
        records = store.records
        warning = store.warning
    }

    var currentRecord: DailyRecord? { records.first { $0.id == menuChallenge.id } }
}
