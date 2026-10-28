import CoreMotion
import ReachCore

/// Live Core Motion activity while the app is awake. (Phase 2 also reads
/// the 7-day activity history to label trips after the fact.)
@MainActor
final class MotionMonitor {
    private let manager = CMMotionActivityManager()
    private var running = false

    static var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    func start(_ handler: @escaping @MainActor (MotionKind, _ confident: Bool, Date) -> Void) {
        guard Self.isAvailable, !running else { return }
        switch CMMotionActivityManager.authorizationStatus() {
        case .denied, .restricted:
            return
        default:
            break
        }
        running = true
        manager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            let kind = MotionKind.classify(stationary: activity.stationary, walking: activity.walking,
                                           running: activity.running, cycling: activity.cycling,
                                           automotive: activity.automotive)
            let confident = activity.confidence != .low
            let date = activity.startDate
            MainActor.assumeIsolated { handler(kind, confident, date) }
        }
    }

    func stop() {
        guard running else { return }
        manager.stopActivityUpdates()
        running = false
    }
}
