import Foundation

/// Drops fixes that are too vague or physically impossible before they're stored.
public struct PointFilter: Sendable {
    public struct Configuration: Sendable {
        /// Fixes worse than this are discarded outright.
        public var maxHorizontalAccuracy: Double = 50
        /// About 250 km/h. Nothing in a city moves faster, so faster jumps are GPS glitches.
        public var maxSpeed: Double = 70
        /// Duplicate or out-of-order fixes closer together than this are dropped.
        public var minInterval: Double = 0.5

        public init() {}
    }

    public var configuration: Configuration
    public private(set) var lastAccepted: LocationSample?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func accept(_ sample: LocationSample) -> Bool {
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= configuration.maxHorizontalAccuracy else { return false }
        if let last = lastAccepted {
            let dt = sample.timestamp - last.timestamp
            guard dt >= configuration.minInterval else { return false }
            // Give both fixes the benefit of their error radius before calling it a teleport.
            let slack = last.horizontalAccuracy + sample.horizontalAccuracy
            let distance = Geo.distance(last.coordinate, sample.coordinate)
            if max(0, distance - slack) / dt > configuration.maxSpeed { return false }
        }
        lastAccepted = sample
        return true
    }

    public mutating func reset() {
        lastAccepted = nil
    }
}
