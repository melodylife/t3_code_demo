import SwiftUI

/// Full-screen launch splash shown briefly before the menu.
struct SplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var floating = false
    @State private var pulsing = false

    let onFinish: () -> Void

    private let emojis = ["🍎", "🍊", "🍋", "🍇", "🫐", "🍓"]

    private let floaters: [Floater] = [
        Floater(id: 0, symbol: "🍎", x: -130, y: -250, size: 44, rotation: -14, delay: 0.00),
        Floater(id: 1, symbol: "🍋", x: 128, y: -220, size: 36, rotation: 12, delay: 0.25),
        Floater(id: 2, symbol: "🍇", x: -150, y: 40, size: 30, rotation: 18, delay: 0.50),
        Floater(id: 3, symbol: "🍊", x: 150, y: 90, size: 40, rotation: -10, delay: 0.15),
        Floater(id: 4, symbol: "🫐", x: -90, y: 260, size: 28, rotation: 8, delay: 0.40),
        Floater(id: 5, symbol: "🍓", x: 110, y: 280, size: 34, rotation: -16, delay: 0.60),
    ]

    var body: some View {
        ZStack {
            GradientBackground()

            ForEach(floaters) { floater in
                Text(floater.symbol)
                    .font(.system(size: floater.size))
                    .rotationEffect(.degrees(floater.rotation))
                    .offset(x: floater.x, y: floater.y + (floating ? -16 : 16))
                    .opacity(0.16)
                    .animation(floaterAnimation(floater), value: floating)
            }

            VStack(spacing: 30) {
                logoCard
                    .scaleEffect(appeared ? 1 : 0.68)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 12) {
                    title
                        .opacity(appeared ? 1 : 0)

                    Text("MATCH THREE · POP EMOJI")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                        .opacity(appeared ? 1 : 0)
                }
                .offset(y: appeared ? 0 : 18)

                loadingDots
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 40)
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("splashScreen")
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                appeared = true
            }
            floating = true
            pulsing = true
            scheduleDismiss()
        }
    }

    private var logoCard: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { col in
                        Text(emojis[row * 3 + col])
                            .font(.system(size: 34))
                            .frame(width: 56, height: 56)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [Theme.accent.opacity(0.20),
                                            Theme.accentSecondary.opacity(0.10)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Theme.accent.opacity(0.85),
                                            Theme.accentSecondary.opacity(0.45)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Theme.accent.opacity(0.35), radius: 26, x: 0, y: 0)
    }

    private var title: some View {
        Text("EmojiMatch")
            .font(.system(size: 46, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [Theme.accentSecondary, Theme.accent],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )
            .shadow(color: Theme.accent.opacity(0.5), radius: 22, x: 0, y: 0)
            .shadow(color: Theme.accentSecondary.opacity(0.25), radius: 6, x: 0, y: 0)
    }

    private var loadingDots: some View {
        HStack(spacing: 11) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulsing ? 1.6 : 0.6)
                    .animation(dotAnimation(index), value: pulsing)
            }
        }
    }

    private func floaterAnimation(_ floater: Floater) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 1.7)
            .repeatForever(autoreverses: true)
            .delay(floater.delay)
    }

    private func dotAnimation(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 0.65)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.18)
    }

    private func scheduleDismiss() {
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run { onFinish() }
        }
    }
}

private struct Floater: Identifiable {
    let id: Int
    let symbol: String
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let rotation: Double
    let delay: Double
}
