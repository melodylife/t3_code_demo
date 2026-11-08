import SwiftUI

enum Theme {
    static let backgroundTop = Color(red: 0.11, green: 0.07, blue: 0.20)
    static let backgroundBottom = Color(red: 0.03, green: 0.02, blue: 0.07)
    static let accent = Color(red: 1.00, green: 0.45, blue: 0.35)
    static let accentSecondary = Color(red: 1.00, green: 0.78, blue: 0.30)
    static let card = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.12)
}

struct GradientBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom],
                       startPoint: .top,
                       endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct CardBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
    }
}
