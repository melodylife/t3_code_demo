import Foundation

/// Index into a level's palette. The palette strings themselves live in the UI layer.
public struct TileKind: Hashable, Codable, Sendable, CustomStringConvertible {
    public let index: Int

    public init(_ index: Int) {
        self.index = index
    }

    public var description: String { "kind(\(index))" }
}

public enum Axis: String, Codable, Sendable {
    case horizontal
    case vertical
}

public enum Tile: Hashable, Codable, Sendable, CustomStringConvertible {
    case normal(TileKind)
    case rocket(TileKind, Axis)
    case bomb(TileKind)
    case rainbow

    /// The match colour. `nil` for rainbows, which never join a run.
    public var kind: TileKind? {
        switch self {
        case let .normal(k): return k
        case let .rocket(k, _): return k
        case let .bomb(k): return k
        case .rainbow: return nil
        }
    }

    public var isSpecial: Bool {
        if case .normal = self { return false }
        return true
    }

    public var isRainbow: Bool {
        if case .rainbow = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case let .normal(k): return "normal(\(k.index))"
        case let .rocket(k, axis): return "rocket(\(k.index),\(axis.rawValue))"
        case let .bomb(k): return "bomb(\(k.index))"
        case .rainbow: return "rainbow"
        }
    }
}
