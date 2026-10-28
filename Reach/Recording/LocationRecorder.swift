import CoreLocation
import Observation
import ReachCore
import UIKit

/// Runs background recording: owns CLLocationManager, feeds events into
/// `TrackingPolicy` and carries out the actions it returns.
///
/// Continuous updates use CLLocationManager's standard service rather than
/// iOS 17's `CLLocationUpdate.liveUpdates`. With Always permission the standard
/// service can be restarted from a background wakeup (geofence exit, visit,
/// significant change) and lets us set accuracy and distance filter per mode.
/// Swapping in `liveUpdates` later only touches `perform(_:)`.
@Observable
@MainActor
final class LocationRecorder: NSObject {
    private static let enabledKey = "recordingEnabled"
    private static let tickInterval: TimeInterval = 30

    private(set) var isEnabled: Bool
    private(set) var isRunning = false
    private(set) var mode: TrackingMode = .off
    private(set) var profile: LocationProfile = .onFoot
    private(set) var lastSample: LocationSample?
    private(set) var lastMotion: MotionKind = .unknown

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let motion = MotionMonitor()
    @ObservationIgnored private let geofence = GeofenceWatcher()
    @ObservationIgnored private let store: RecordingStore
    @ObservationIgnored private let coverage: CoverageModel
    @ObservationIgnored private var policy = TrackingPolicy()
    @ObservationIgnored private var filter = PointFilter()
    @ObservationIgnored private var tracer = CoverageTracer()
    @ObservationIgnored private var tickTimer: Timer?

    init(store: RecordingStore, coverage: CoverageModel) {
        self.store = store
        self.coverage = coverage
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        super.init()
        manager.delegate = self
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: Control

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled { startIfAuthorized() } else { stop() }
    }

    /// Starts recording if it's switched on and location permission allows.
    /// Safe to call repeatedly (launch, foreground, permission changes).
    func startIfAuthorized() {
        let status = manager.authorizationStatus
        guard isEnabled, status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        if isRunning {
            startWakeupServicesIfAlways()
            return
        }
        isRunning = true
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false  // TrackingPolicy decides when to pause
        manager.showsBackgroundLocationIndicator = false
        startWakeupServicesIfAlways()
        geofence.start { [weak self] date in
            self?.log("geofence", "Left the stationary area")
            self?.handle(.geofenceExit(at: date.timeIntervalSince1970))
        }
        motion.start { [weak self] kind, confident, date in
            guard let self else { return }
            lastMotion = kind
            handle(.motion(kind, confident: confident, at: date.timeIntervalSince1970))
        }
        log("start", status == .authorizedAlways ? "Recording with Always permission"
                                                 : "Recording while the app is in use only")
        handle(.start(at: Date().timeIntervalSince1970))
    }

    func stop() {
        guard isRunning else { return }
        handle(.stop)
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        motion.stop()
        isRunning = false
        log("stop", "Recording switched off")
        store.flush()
    }

    func flush() {
        store.flush()
    }

    func log(_ kind: String, _ message: String) {
        let level = UIDevice.current.batteryLevel
        store.log(kind, message, battery: level < 0 ? nil : Double(level))
    }

    /// Visits and significant changes are what wake a suspended or terminated
    /// app. They need Always permission.
    private func startWakeupServicesIfAlways() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        manager.startMonitoringVisits()
        manager.startMonitoringSignificantLocationChanges()
    }

    // MARK: Policy

    private func handle(_ event: TrackingEvent) {
        let before = policy.mode
        for action in policy.handle(event) {
            perform(action)
        }
        mode = policy.mode
        profile = policy.profile
        guard policy.mode != before else { return }
        switch policy.mode {
        case .moving:
            log("moving", "GPS on (\(policy.profile.rawValue))")
        case .stationary(let anchor):
            log("stationary", anchor == nil ? "GPS off, no fix found" : "GPS off, waiting to leave")
            store.flush()
        case .off:
            break
        }
    }

    private func perform(_ action: TrackingAction) {
        switch action {
        case .startContinuousUpdates(let profile):
            switch profile {
            case .onFoot:
                manager.activityType = .fitness
                manager.desiredAccuracy = kCLLocationAccuracyBest
                manager.distanceFilter = 5
            case .vehicle:
                manager.activityType = .automotiveNavigation
                manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                manager.distanceFilter = 20
            }
            manager.startUpdatingLocation()
            startTicking()
        case .stopContinuousUpdates:
            manager.stopUpdatingLocation()
            stopTicking()
        case let .setGeofence(center, radius):
            geofence.setAnchor(CLLocationCoordinate2D(center), radius: radius)
        case .clearGeofence:
            geofence.clearAnchor()
        case .breakTrace:
            tracer.breakTrace()
        }
    }

    private func startTicking() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handle(.tick(at: Date().timeIntervalSince1970))
            }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: Fixes

    private func receive(_ locations: [CLLocation]) {
        for location in locations {
            let sample = LocationSample(location)
            switch policy.mode {
            case .moving:
                record(sample)
                handle(.location(sample))
            case .stationary:
                // Continuous updates are off, so this is a significant-change fix.
                handle(.significantChange(sample))
            case .off:
                break
            }
        }
    }

    private func record(_ sample: LocationSample) {
        lastSample = sample
        guard filter.accept(sample) else { return }
        store.append(sample)
        let touches = tracer.add(sample)
        guard !touches.isEmpty else { return }
        coverage.add(store.record(touches))
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { receive(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let departed = visit.departureDate != .distantFuture
        MainActor.assumeIsolated {
            guard departed else {
                log("visit", "Arrived somewhere")
                return
            }
            log("visit", "Left a visit")
            // Departures can be reported late, so act on them as of now.
            handle(.visitDeparture(at: Date().timeIntervalSince1970))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                startIfAuthorized()
            case .denied, .restricted:
                stop()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        MainActor.assumeIsolated {
            // locationUnknown is transient (no fix yet); not worth logging.
            guard code != .locationUnknown else { return }
            log("error", error.localizedDescription)
        }
    }
}

extension LocationSample {
    init(_ location: CLLocation) {
        self.init(timestamp: location.timestamp.timeIntervalSince1970,
                  latitude: location.coordinate.latitude,
                  longitude: location.coordinate.longitude,
                  horizontalAccuracy: location.horizontalAccuracy,
                  speed: location.speed,
                  course: location.course)
    }
}

extension CLLocationCoordinate2D {
    init(_ coordinate: GeoCoordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
