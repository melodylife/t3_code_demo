import Match3Core
import SwiftUI

enum SpecialIntroType: String, CaseIterable, Identifiable, Sendable {
    case rocket
    case bomb
    case rainbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rocket: return "Directional Rocket"
        case .bomb: return "Explosive Bomb"
        case .rainbow: return "Rainbow Star"
        }
    }

    var icon: String {
        switch self {
        case .rocket: return "🚀"
        case .bomb: return "💣"
        case .rainbow: return "🌈"
        }
    }

    var creationRule: String {
        switch self {
        case .rocket:
            return "Match 4 tiles in a straight line to create a Rocket."
        case .bomb:
            return "Match 5 tiles in an L or T corner shape to create a Bomb."
        case .rainbow:
            return "Match 5 tiles in a straight row to create a Rainbow."
        }
    }

    var activationRule: String {
        switch self {
        case .rocket:
            return "Activate by matching it with its fruit color, or by swapping it with any other special tile! It blasts an entire row or column."
        case .bomb:
            return "Activate by matching it with its fruit color, or by swapping it with any other special tile! It detonates a 3×3 area."
        case .rainbow:
            return "Swap with any adjacent fruit to clear all tiles of that fruit from the board! Swapping two Rainbows clears the entire board."
        }
    }

    static func from(tile: Tile) -> SpecialIntroType? {
        switch tile {
        case .rocket: return .rocket
        case .bomb: return .bomb
        case .rainbow: return .rainbow
        case .normal: return nil
        }
    }
}

struct SpecialIntroOverlay: View {
    let type: SpecialIntroType
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(type: SpecialIntroType, onDismiss: @escaping () -> Void) {
        self.type = type
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 16) {
                Text(type.icon)
                    .font(.system(size: 64))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.12)))

                VStack(spacing: 4) {
                    Text("NEW SPECIAL TILE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.yellow)
                        .tracking(1.5)

                    Text(type.title)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.yellow)
                            .font(.system(size: 16, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How to Create")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(type.creationRule)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }

                    Divider().background(Color.white.opacity(0.2))

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 16, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How to Activate")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(type.activationRule)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))

                Button {
                    onDismiss()
                } label: {
                    Text("Got It!")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.yellow))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dismissSpecialIntro")
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(UIColor.systemGray6).opacity(0.95))
                    .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
            )
            .padding(.horizontal, 28)
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(type.title). \(type.creationRule). \(type.activationRule)")
    }
}
