import CoreGraphics
import Foundation

/// Every duration in the game. Nothing else in the codebase hard-codes a timing.
enum Timing {
    static let swap: TimeInterval = 0.10
    static let rejectOut: TimeInterval = 0.08
    static let rejectBack: TimeInterval = 0.14

    static let clearPop: TimeInterval = 0.06
    static let clearFade: TimeInterval = 0.12
    static let clearStagger: TimeInterval = 0.012

    static let specialPop: TimeInterval = 0.20
    static let fallPad: TimeInterval = 0.02
    static let cascadeGap: TimeInterval = 0.04
    static let shuffle: TimeInterval = 0.35

    static let hintDelay: TimeInterval = 5.0

    /// Constant-acceleration fall: t = sqrt(2d/g), clamped so a full-column drop
    /// still reads as fast.
    static func fall(distance: CGFloat) -> TimeInterval {
        guard distance > 0 else { return 0.05 }
        let gravity: CGFloat = 2600
        return min(0.34, max(0.06, sqrt(2 * distance / gravity)))
    }
}
