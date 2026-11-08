import Combine
import Foundation
import Match3Core

/// Owns learning presentation, independently of campaign/daily scoring. The
/// engine's phase gate and this scene instruction gate are deliberately separate.
final class GuidedPlayCoordinator: ObservableObject {
    let scene: GameScene
    let store: LearningStore
    private let canPresentInstruction: () -> Bool

    @Published private(set) var activeHint: HintSuggestion?
    @Published private(set) var activeSpecialIntro: SpecialIntroType?
    @Published private(set) var showsLevelIntro = false
    @Published private(set) var showsPractice = false
    @Published private(set) var showsHowToPlay = false
    private var pendingSpecials: [SpecialIntroType] = []

    var blocksInput: Bool {
        showsLevelIntro || showsPractice || showsHowToPlay || activeSpecialIntro != nil
    }

    init(scene: GameScene, store: LearningStore = .shared,
         canPresentInstruction: @escaping () -> Bool = { true }) {
        self.scene = scene
        self.store = store
        self.canPresentInstruction = canPresentInstruction
        showsLevelIntro = !store.hasSeenTips
        updateInputGate()
        scene.onHintChanged = { [weak self] hint in self?.activeHint = hint }
        scene.onSpecialSpawned = { [weak self] tile in self?.queueSpecial(tile) }
        scene.onBoardSettled = { [weak self] _ in self?.refreshPresentation() }
        for cell in scene.board.cells {
            if let tile = scene.board[cell] { queueSpecial(tile) }
        }
    }

    private func queueSpecial(_ tile: Tile) {
        guard let type = SpecialIntroType.from(tile: tile),
              !store.hasIntroducedSpecial(type.id), !pendingSpecials.contains(type) else { return }
        pendingSpecials.append(type)
    }

    /// Also called after entering Star Chase: the goal-choice/result overlay
    /// always takes precedence over a tip queued by the same last cascade.
    func refreshPresentation() {
        guard scene.isSettled, canPresentInstruction(), !blocksInput else { return }
        while let first = pendingSpecials.first, store.hasIntroducedSpecial(first.id) {
            pendingSpecials.removeFirst()
        }
        guard !pendingSpecials.isEmpty else { return }
        scene.clearInstructionState()
        activeSpecialIntro = pendingSpecials.removeFirst()
        updateInputGate()
    }

    func requestHint(unmetKinds: Set<TileKind> = []) {
        guard !blocksInput, canPresentInstruction() else { return }
        activeHint = scene.requestHint(unmetCollectionKinds: unmetKinds)
    }

    func dismissHint() {
        scene.clearHint()
        activeHint = nil
    }

    func dismissSpecialIntro() {
        if let type = activeSpecialIntro { store.markSpecialIntroduced(type.id) }
        activeSpecialIntro = nil
        updateInputGate()
        refreshPresentation()
    }

    func dismissLevelIntro(skipTips: Bool = false) {
        store.markTipsSeen()
        showsLevelIntro = false
        if skipTips {
            store.skipTutorial()
        } else if !store.hasCompletedTutorial {
            showsPractice = true
        }
        updateInputGate()
        refreshPresentation()
    }

    func openPractice() {
        guard scene.isSettled else { return }
        showsPractice = true
        scene.clearInstructionState()
        updateInputGate()
    }

    func closePractice() {
        showsPractice = false
        updateInputGate()
        refreshPresentation()
    }

    func openHowToPlay() {
        guard scene.isSettled, !blocksInput else { return }
        showsHowToPlay = true
        scene.clearInstructionState()
        updateInputGate()
    }

    func closeHowToPlay() {
        showsHowToPlay = false
        updateInputGate()
        refreshPresentation()
    }

    private func updateInputGate() {
        scene.isInputGated = blocksInput
    }
}
