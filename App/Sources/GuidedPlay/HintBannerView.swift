import Match3Core
import SwiftUI

struct HintBannerView: View {
    let hint: HintSuggestion
    let palette: [String]
    let onDismiss: () -> Void

    init(hint: HintSuggestion, palette: [String] = [], onDismiss: @escaping () -> Void) {
        self.hint = hint
        self.palette = palette
        self.onDismiss = onDismiss
    }

    private var hintText: String {
        switch hint.reason {
        case let .collectObjective(kind, _):
            let fruit = palette[safe: kind.index] ?? "target fruit"
            return "Match \(fruit) toward your collection goal."
        case let .createSpecial(special):
            switch special {
            case .rocket:
                return "Match 4 to create a Rocket!"
            case .bomb:
                return "Match an L or T shape to create a Bomb!"
            case .rainbow:
                return "Match 5 in a row to create a Rainbow!"
            case .normal:
                return "Match 3 tiles."
            }
        case .activateSpecial:
            return "Activate your special tile!"
        case let .standardMatch(count):
            return "Match \(count) tiles to clear."
        }
    }

    private var icon: String {
        switch hint.reason {
        case let .collectObjective(kind, _):
            return palette[safe: kind.index] ?? "🎯"
        case let .createSpecial(special):
            switch special {
            case .rocket: return "🚀"
            case .bomb: return "💣"
            case .rainbow: return "🌈"
            case .normal: return "💡"
            }
        case .activateSpecial:
            return "⚡️"
        case .standardMatch:
            return "💡"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 22))

            VStack(alignment: .leading, spacing: 2) {
                Text("HINT SUGGESTION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .tracking(1.2)

                Text(hintText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Hint")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hint suggestion: \(hintText)")
    }
}
