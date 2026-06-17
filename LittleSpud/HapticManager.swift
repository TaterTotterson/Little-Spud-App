import QuartzCore
import UIKit

final class HapticManager {
    static let shared = HapticManager()

    private let replyTickGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let completeGenerator = UINotificationFeedbackGenerator()
    private var lastTickAt: TimeInterval = 0

    private init() {
        replyTickGenerator.prepare()
        completeGenerator.prepare()
    }

    func play(_ type: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch type {
            case "replyTick":
                self.replyTick()
            case "messageComplete":
                self.messageComplete()
            default:
                break
            }
        }
    }

    private func replyTick() {
        let now = CACurrentMediaTime()
        guard now - lastTickAt > 0.08 else { return }
        lastTickAt = now
        replyTickGenerator.impactOccurred(intensity: 0.35)
        replyTickGenerator.prepare()
    }

    private func messageComplete() {
        completeGenerator.notificationOccurred(.success)
        completeGenerator.prepare()
    }
}
