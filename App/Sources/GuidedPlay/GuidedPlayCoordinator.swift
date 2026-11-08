import Combine
import Foundation
import Match3Core
import SwiftUI

/// Coordinates Guided Play features (hints, one-time special intros, level objectives tip)
/// with the active `GameScene` without requiring changes to `GameEngine`.
final class GuidedPlayCoordinator: ObservableObject {
    let scene: GameScene
    let store: LearningStore

    @Published var activeHint: HintSuggestion?
    @Published var activeSpecialIntro: SpecialIntroType?
    @Published var showsLevelIntro: Bool = false
    @Published var showsPractice: Bool = false
    @Published var showsHowToPlay: Bool = false

    private var pendingSpecialsQueue: [SpecialIntroType] = []

    init(scene: GameScene, store: LearningStore = .shared) {
        self.scene = scene
        self.store = store
        setupHooks()
        checkInitialState()
    }

    private func setupHooks() {
        // Observe hinted suggestion updates
        scene.onHintChanged = { [weak self] hint in
            DispatchQueue.main.async {
                self?.activeHint = hint
            }
        }

        // Catch newly spawned specials
        scene.onSpecialSpawned = { [weak self] tile in
            guard let self, let introType = SpecialIntroType.from(tile: tile) else { return }
            if !self.store.hasIntroducedSpecial(introType.id) && !self.pendingSpecialsQueue.contains(introType) {
                self.pendingSpecialsQueue.append(introType)
            }
        }

        // Settled board hook: queued special introductions appear ONLY on settled boards!
        let existingSettledHook = scene.onBoardSettled
        scene.onBoardSettled = { [weak self] board in
            existingSettledHook?(board)
            self?.handleBoardSettled()
        }
    }

    private func checkInitialState() {
        // First-time play check for level objective introduction
        if !store.hasSeenTips && scene.level.id == 1 {
            showsLevelIntro = true
            scene.isInputGated = true
        }

        // Check if starting board already contains specials not yet introduced
        for cell in scene.board.cells {
            if let tile = scene.board[cell], let type = SpecialIntroType.from(tile: tile) {
                if !store.hasIntroducedSpecial(type.id) && !pendingSpecialsQueue.contains(type) {
                    pendingSpecialsQueue.append(type)
                }
            }
        }
    }

    private func handleBoardSettled() {
        guard activeSpecialIntro == nil, !showsLevelIntro, !showsPractice else { return }
        guard let nextSpecial = pendingSpecialsQueue.first else { return }
        pendingSpecialsQueue.removeFirst()

        // Gate board input and clear any active hints/drags
        scene.clearInstructionState()
        scene.isInputGated = true

        DispatchQueue.main.async {
            self.store.markSpecialIntroduced(nextSpecial.id)
            self.activeSpecialIntro = nextSpecial
        }
    }

    // MARK: - User Actions

    func requestHint(unmetKinds: Set<TileKind> = []) {
        let suggestion = scene.requestHint(unmetCollectionKinds: unmetKinds)
        activeHint = suggestion
    }

    func dismissHint() {
        scene.clearHint()
        activeHint = nil
    }

    func dismissSpecialIntro() {
        activeSpecialIntro = nil
        scene.isInputGated = false
        scene.clearInstructionState()

        // Check if another special is queued
        if !pendingSpecialsQueue.isEmpty {
            handleBoardSettled()
        }
    }

    func dismissLevelIntro(skipTips: Bool = false) {
        showsLevelIntro = false
        scene.isInputGated = false
        if skipTips {
            store.markTipsSeen()
        }
    }

    func openPractice() {
        showsPractice = true
        scene.isInputGated = true
    }

    func closePractice() {
        showsPractice = false
        scene.isInputGated = false
    }

    func openHowToPlay() {
        showsHowToPlay = true
        scene.isInputGated = true
    }

    func closeHowToPlay() {
        showsHowToPlay = false
        scene.isInputGated = false
    }
}
