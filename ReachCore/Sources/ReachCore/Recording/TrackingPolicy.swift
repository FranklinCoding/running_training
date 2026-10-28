import Foundation

/// What Core Motion thinks you're doing, reduced to the cases Reach cares about.
public enum MotionKind: String, Codable, Sendable, CaseIterable {
    case stationary, walking, running, cycling, automotive, unknown

    /// `CMMotionActivity` can set several flags at once (automotive + stationary
    /// at a red light). The most specific kind of movement wins.
    public static func classify(stationary: Bool, walking: Bool, running: Bool,
                                cycling: Bool, automotive: Bool) -> MotionKind {
        if automotive { return .automotive }
        if cycling { return .cycling }
        if running { return .running }
        if walking { return .walking }
        if stationary { return .stationary }
        return .unknown
    }

    public var isMoving: Bool {
        switch self {
        case .walking, .running, .cycling, .automotive: return true
        case .stationary, .unknown: return false
        }
    }
}

/// How the continuous location updates are tuned.
public enum LocationProfile: String, Codable, Sendable {
    /// Walking, running, cycling: best accuracy, small distance filter.
    case onFoot
    /// In a vehicle: coarser accuracy and a bigger distance filter are plenty.
    case vehicle
}

public enum TrackingMode: Equatable, Sendable {
    /// Recording is switched off.
    case off
    /// GPS on, recording a path.
    case moving
    /// GPS off. Waiting for a geofence exit, visit departure or significant
    /// location change to wake us. The anchor is nil if we never got a fix.
    case stationary(anchor: GeoCoordinate?)
}

public enum TrackingEvent: Sendable {
    case start(at: Double)
    case stop
    case location(LocationSample)
    case motion(MotionKind, confident: Bool, at: Double)
    /// Periodic check while moving, so a dwell is noticed even when the
    /// distance filter suppresses fixes.
    case tick(at: Double)
    case geofenceExit(at: Double)
    case visitDeparture(at: Double)
    case significantChange(LocationSample)
}

public enum TrackingAction: Equatable, Sendable {
    case startContinuousUpdates(LocationProfile)
    case stopContinuousUpdates
    case setGeofence(center: GeoCoordinate, radius: Double)
    case clearGeofence
    /// Don't join the next recorded fix to the previous one.
    case breakTrace
}

/// The battery-saving state machine behind recording, kept free of
/// CoreLocation so it can be unit-tested.
///
/// Moving: continuous GPS. After `dwellDuration` within `dwellRadius` of one
/// spot (and no recent movement from Core Motion) it switches GPS off and
/// drops a geofence around the spot. Leaving the geofence, a visit ending,
/// a significant location change far from the spot, or Core Motion seeing
/// movement switches GPS back on.
public struct TrackingPolicy: Sendable {
    public struct Configuration: Sendable {
        public var dwellRadius: Double = 40
        public var dwellDuration: Double = 180
        /// Core Motion reporting movement this recently blocks going stationary
        /// (e.g. sitting in traffic, or on a subway with no GPS).
        public var motionVetoWindow: Double = 60
        /// If no fix at all arrives for this long while moving, give up and
        /// stop GPS rather than search forever indoors.
        public var noFixTimeout: Double = 360
        public var geofenceRadius: Double = 150
        /// A significant-change fix closer than this to the anchor is just noise.
        public var wakeDistance: Double = 250

        public init() {}
    }

    public let configuration: Configuration
    public private(set) var mode: TrackingMode = .off
    public private(set) var profile: LocationProfile = .onFoot

    /// First fix of the current dwell candidate.
    private var dwellStart: LocationSample?
    private var lastMovingMotionAt: Double?
    private var movingSince: Double = 0
    private var lastAnchor: GeoCoordinate?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func handle(_ event: TrackingEvent) -> [TrackingAction] {
        switch event {
        case .start(let time):
            guard mode == .off else { return [] }
            // Always start by moving: a few minutes of GPS settles where we are.
            // Clear any geofence left over from before the app was relaunched.
            return enterMoving(at: time)

        case .stop:
            guard mode != .off else { return [] }
            mode = .off
            dwellStart = nil
            return [.stopContinuousUpdates, .clearGeofence, .breakTrace]

        case .location(let sample):
            guard mode == .moving else { return [] }
            updateDwell(with: sample)
            return evaluateDwell(now: sample.timestamp)

        case .tick(let time):
            guard mode == .moving else { return [] }
            return evaluateDwell(now: time)

        case let .motion(kind, confident, time):
            guard confident else { return [] }
            if kind.isMoving { lastMovingMotionAt = time }
            switch mode {
            case .off:
                return []
            case .moving:
                guard kind.isMoving else { return [] }
                let wanted: LocationProfile = kind == .automotive ? .vehicle : .onFoot
                guard wanted != profile else { return [] }
                profile = wanted
                return [.startContinuousUpdates(wanted)]
            case .stationary:
                guard kind.isMoving else { return [] }
                profile = kind == .automotive ? .vehicle : .onFoot
                return enterMoving(at: time)
            }

        case .geofenceExit(let time), .visitDeparture(let time):
            guard case .stationary = mode else { return [] }
            return enterMoving(at: time)

        case .significantChange(let sample):
            guard case .stationary(let anchor) = mode else { return [] }
            if let anchor, Geo.distance(anchor, sample.coordinate) <= configuration.wakeDistance { return [] }
            return enterMoving(at: sample.timestamp)
        }
    }

    private mutating func enterMoving(at time: Double) -> [TrackingAction] {
        mode = .moving
        movingSince = time
        dwellStart = nil
        return [.clearGeofence, .startContinuousUpdates(profile)]
    }

    private mutating func updateDwell(with sample: LocationSample) {
        // A vague indoor fix is still "here"; cap it so a 1 km cell-tower fix isn't.
        let radius = max(configuration.dwellRadius, min(sample.horizontalAccuracy, 100))
        if let start = dwellStart, Geo.distance(start.coordinate, sample.coordinate) <= radius { return }
        dwellStart = sample
    }

    private mutating func evaluateDwell(now: Double) -> [TrackingAction] {
        if let moved = lastMovingMotionAt, now - moved < configuration.motionVetoWindow { return [] }

        guard let start = dwellStart else {
            // No fix since we started moving. Don't leave GPS searching forever.
            guard now - movingSince >= configuration.noFixTimeout else { return [] }
            return enterStationary(at: lastAnchor)
        }
        guard now - start.timestamp >= configuration.dwellDuration else { return [] }
        return enterStationary(at: start.coordinate)
    }

    private mutating func enterStationary(at anchor: GeoCoordinate?) -> [TrackingAction] {
        mode = .stationary(anchor: anchor)
        dwellStart = nil
        lastAnchor = anchor
        var actions: [TrackingAction] = [.stopContinuousUpdates, .breakTrace]
        if let anchor {
            actions.append(.setGeofence(center: anchor, radius: configuration.geofenceRadius))
        }
        return actions
    }
}
