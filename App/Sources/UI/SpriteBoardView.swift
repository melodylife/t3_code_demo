import SpriteKit
import SwiftUI

struct SpriteBoardView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 60
        // One addressable element for UI tests and VoiceOver: the board itself.
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "board"
        view.accessibilityLabel = "Match board"
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }
}
