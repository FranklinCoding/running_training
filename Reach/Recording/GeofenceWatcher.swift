import CoreLocation

/// The single "you've left the place you were sitting" geofence, using
/// iOS 17's CLMonitor. CLMonitor keeps its conditions across launches and
/// relaunches the app when one changes, as long as we open the same named
/// monitor again at launch, which `start` does.
@MainActor
final class GeofenceWatcher {
    private static let monitorName = "ReachStationaryArea"
    private static let anchorID = "anchor"

    private var monitor: CLMonitor?
    private var eventsTask: Task<Void, Never>?
    /// Operations requested before the monitor finished opening.
    private var pending: [(CLMonitor) async -> Void] = []
    /// Keeps add/remove calls in the order they were made.
    private var lastOperation: Task<Void, Never>?
    private var onExit: (@MainActor (Date) -> Void)?

    func start(onExit: @escaping @MainActor (Date) -> Void) {
        self.onExit = onExit
        guard eventsTask == nil else { return }
        eventsTask = Task { [weak self] in
            let monitor = await CLMonitor(Self.monitorName)
            guard let self else { return }
            self.monitor = monitor
            let queued = pending
            pending.removeAll()
            for operation in queued { enqueue(operation) }
            do {
                for try await event in await monitor.events {
                    guard event.identifier == Self.anchorID, event.state == .unsatisfied else { continue }
                    onExit?(event.date)
                }
            } catch {
                // The stream only ends if monitoring becomes impossible (e.g. permission
                // revoked); visits and significant changes still wake us.
            }
        }
    }

    func setAnchor(_ center: CLLocationCoordinate2D, radius: CLLocationDistance) {
        enqueue { monitor in
            let condition = CLMonitor.CircularGeographicCondition(center: center, radius: radius)
            await monitor.add(condition, identifier: Self.anchorID, assuming: .satisfied)
        }
    }

    func clearAnchor() {
        enqueue { monitor in
            await monitor.remove(Self.anchorID)
        }
    }

    private func enqueue(_ operation: @escaping (CLMonitor) async -> Void) {
        guard let monitor else {
            pending.append(operation)
            return
        }
        let previous = lastOperation
        lastOperation = Task {
            await previous?.value
            await operation(monitor)
        }
    }
}
