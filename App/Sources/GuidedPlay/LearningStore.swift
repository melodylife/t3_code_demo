import Combine
import Foundation

/// Persistent store for Guided Play tutorial completion, tips, and introduced specials.
/// Maintained strictly independent of campaign progress (`ProgressData`).
final class LearningStore: ObservableObject {
    static let shared = LearningStore()

    private enum Keys {
        static let tutorialCompleted = "emojimatch.learning.tutorial_completed_v1"
        static let tipsSeen = "emojimatch.learning.tips_seen_v1"
        static let introducedSpecials = "emojimatch.learning.specials_introduced_v1"
    }

    private let defaults: UserDefaults

    @Published private(set) var hasCompletedTutorial: Bool
    @Published private(set) var hasSeenTips: Bool
    @Published private(set) var introducedSpecials: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedTutorial = defaults.bool(forKey: Keys.tutorialCompleted)
        self.hasSeenTips = defaults.bool(forKey: Keys.tipsSeen)
        let savedSpecials = defaults.stringArray(forKey: Keys.introducedSpecials) ?? []
        self.introducedSpecials = Set(savedSpecials)
    }

    func markTutorialCompleted() {
        hasCompletedTutorial = true
        defaults.set(true, forKey: Keys.tutorialCompleted)
    }

    func skipTutorial() {
        markTutorialCompleted()
    }

    func markTipsSeen() {
        hasSeenTips = true
        defaults.set(true, forKey: Keys.tipsSeen)
    }

    func hasIntroducedSpecial(_ id: String) -> Bool {
        introducedSpecials.contains(id)
    }

    func markSpecialIntroduced(_ id: String) {
        introducedSpecials.insert(id)
        defaults.set(Array(introducedSpecials), forKey: Keys.introducedSpecials)
    }

    /// Resets all learning state for testing or replay.
    func resetForTesting() {
        hasCompletedTutorial = false
        hasSeenTips = false
        introducedSpecials.removeAll()
        defaults.removeObject(forKey: Keys.tutorialCompleted)
        defaults.removeObject(forKey: Keys.tipsSeen)
        defaults.removeObject(forKey: Keys.introducedSpecials)
    }
}
