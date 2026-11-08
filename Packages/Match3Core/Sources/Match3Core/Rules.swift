import Foundation

public enum Rules {
    public static let pointsPerTile = 60
    public static let bonusForFour = 120
    public static let bonusForFivePlus = 200
    public static let bonusPerDetonatedSpecial = 100

    public static func multiplier(cascadeIndex: Int) -> Double {
        min(3.0, 1.0 + 0.5 * Double(cascadeIndex))
    }

    /// Special spawned by a matched group, if any.
    /// line(5+) -> rainbow, line(4) -> rocket, corner -> bomb, line(3) -> nothing.
    public static func special(for group: MatchGroup) -> Tile? {
        switch group.shape {
        case .line(5...):
            return .rainbow
        case .line(4):
            let axis: Axis = isHorizontal(group) ? .horizontal : .vertical
            return .rocket(group.kind, axis)
        case .corner:
            return .bomb(group.kind)
        default:
            return nil
        }
    }

    private static func isHorizontal(_ group: MatchGroup) -> Bool {
        let rows = Set(group.cells.map(\.row))
        return rows.count == 1
    }

    public static func points(clearedCount: Int,
                              groups: [MatchGroup],
                              detonations: Int,
                              multiplier: Double) -> Int {
        var base = clearedCount * pointsPerTile
        for group in groups {
            switch group.length {
            case 4: base += bonusForFour
            case 5...: base += bonusForFivePlus
            default: break
            }
        }
        base += detonations * bonusPerDetonatedSpecial
        return Int((Double(base) * multiplier).rounded())
    }
}
