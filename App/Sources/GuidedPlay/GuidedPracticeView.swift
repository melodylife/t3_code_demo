import SwiftUI

struct GuidedPracticeView: View {
    @StateObject private var coordinator: GuidedPracticeCoordinator
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _coordinator = StateObject(wrappedValue: GuidedPracticeCoordinator())
    }

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 16) {
                // Top bar with Practice title and Skip button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PRACTICE BOARD")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.yellow)
                            .tracking(1.5)
                        Text("Learn the Controls")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Button {
                        coordinator.skipPractice()
                        onDismiss()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("skipTutorialButton")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer(minLength: 8)

                // Board host
                SpriteBoardView(scene: coordinator.scene)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 24)

                Spacer(minLength: 8)

                // Instruction & feedback card
                VStack(spacing: 12) {
                    if coordinator.state == .instructional {
                        HStack(spacing: 12) {
                            Text("💡")
                                .font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Make your first match")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Swipe 🍎 up into 🍌 (or tap both neighbors) to align 3 apples.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Text("🎉")
                                    .font(.system(size: 28))
                                Text("Match complete! You're ready to play!")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            Button {
                                coordinator.completePractice()
                                onDismiss()
                            } label: {
                                Text("Start Playing")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Color.yellow))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("finishPracticeButton")
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            coordinator.onFinished = onDismiss
        }
    }
}
