import UIKit

enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func tap() {
        guard isEnabled else { return }
        impact.prepare()
        impact.impactOccurred(intensity: 0.7)
    }

    static func reject() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
    }

    static func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }
}
