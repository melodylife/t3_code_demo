import SwiftUI

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPractice = false

    init() {}

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section 1: Basics
                        guideSection(title: "Basic Controls & Matching", icon: "hand.tap.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Swap Tiles**: Swipe a tile toward an adjacent neighbor, or tap two neighboring tiles in sequence.")
                                Text("• **Match 3**: Align 3 or more identical fruit tiles horizontally or vertically to clear them.")
                                Text("• **Gravity & Cascades**: When tiles clear, tiles above fall down to fill empty spaces, and new fruit drops in.")
                            }
                        }

                        // Section 2: Objectives
                        guideSection(title: "Level Objectives", icon: "target") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Collect Fruit (🎯)**: Clear the required quantity of specific fruit shown in the top HUD before running out of moves.")
                                Text("• **Score Target (⭐️)**: Reach designated score thresholds to earn 1, 2, or 3 stars.")
                            }
                        }

                        // Section 3: Special Tiles
                        guideSection(title: "Special Tiles", icon: "sparkles") {
                            VStack(spacing: 12) {
                                specialCard(icon: "🚀",
                                            title: "Rocket (Match 4)",
                                            description: "Match 4 tiles in a line. Clears its entire row or column when matched or combined with another special.")

                                specialCard(icon: "💣",
                                            title: "Bomb (Match 5 in L/T)",
                                            description: "Match 5 tiles in a corner (L or T shape). Clears a 3×3 area when matched or combined.")

                                specialCard(icon: "🌈",
                                            title: "Rainbow (Match 5 in a Line)",
                                            description: "Match 5 tiles in a straight row. Swap with any fruit to clear all tiles of that fruit, or swap two Rainbows to clear the entire board!")
                            }
                        }

                        // Section 4: Accessibility
                        guideSection(title: "Accessibility & VoiceOver", icon: "figure.walk.motion") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Tile Labels**: VoiceOver announces fruit kind, row, column, and special badges.")
                                Text("• **Direct Double-Tap**: Double-tap a tile to select it, then double-tap an adjacent neighbor to swap.")
                                Text("• **Rotor Actions**: Use VoiceOver Actions rotor to 'Swap Right', 'Swap Down', 'Swap Left', or 'Swap Up'.")
                                Text("• **Reduce Motion**: All animations and pulsing scale effects respect your device's Reduce Motion setting.")
                            }
                        }

                        // Section 5: Interactive Practice
                        VStack(spacing: 8) {
                            Button {
                                showingPractice = true
                            } label: {
                                HStack {
                                    Text("🎮")
                                    Text("Try Practice Board")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color.yellow))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("openPracticeFromHelp")

                            Text("Practice a swap on a mini board without affecting your campaign score or moves.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.yellow)
                }
            }
            .sheet(isPresented: $showingPractice) {
                GuidedPracticeView {
                    showingPractice = false
                }
            }
        }
    }

    private func guideSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.yellow)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            content()
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        }
    }

    private func specialCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon)
                .font(.system(size: 28))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
