import CoreLocation
import CoreMotion
import Observation
import UIKit

/// Location and motion permission state, and the requests for them.
@Observable
@MainActor
final class Permissions: NSObject {
    private(set) var location: CLAuthorizationStatus
    private(set) var isPrecise: Bool
    private(set) var motion: CMAuthorizationStatus

    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let motionManager = CMMotionActivityManager()
    /// Set while we're walking the user through When In Use → Always.
    @ObservationIgnored private var upgradeToAlwaysWhenGranted = false
    private static let askedForAlwaysKey = "askedForAlwaysLocation"

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        location = manager.authorizationStatus
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
        motion = CMMotionActivityManager.authorizationStatus()
        super.init()
        manager.delegate = self
    }

    var hasAlways: Bool { location == .authorizedAlways }
    var hasAnyLocation: Bool { location == .authorizedAlways || location == .authorizedWhenInUse }
    var isLocationBlocked: Bool { location == .denied || location == .restricted }
    var isMotionDecided: Bool { motion != .notDetermined || !MotionMonitor.isAvailable }

    func refresh() {
        location = manager.authorizationStatus
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
        motion = CMMotionActivityManager.authorizationStatus()
    }

    /// iOS only offers Always after When In Use has been granted, so ask for
    /// When In Use first and follow straight on with the Always prompt.
    func requestLocation() {
        switch location {
        case .notDetermined:
            upgradeToAlwaysWhenGranted = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse where !UserDefaults.standard.bool(forKey: Self.askedForAlwaysKey):
            requestAlways()
        default:
            openSettings()
        }
    }

    /// There's no direct Motion & Fitness prompt; the first activity query triggers it.
    func requestMotion() {
        guard MotionMonitor.isAvailable else { return }
        let now = Date()
        motionManager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// iOS shows the Always prompt at most once; after that only Settings can change it.
    private func requestAlways() {
        UserDefaults.standard.set(true, forKey: Self.askedForAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension Permissions: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            refresh()
            if upgradeToAlwaysWhenGranted, location == .authorizedWhenInUse {
                upgradeToAlwaysWhenGranted = false
                requestAlways()
            }
        }
    }
}
