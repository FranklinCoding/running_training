import Foundation

/// Turns a stream of fixes into the H3 cells the path passed through.
///
/// Consecutive fixes are joined by a straight line and every cell along it is
/// marked, so sparse fixes (a fast bike ride) don't leave holes. Long time gaps
/// or big jumps are never bridged: those are tunnels, the subway or a dead
/// phone, and drawing a line across them would mark places you never went.
public struct CoverageTracer: Sendable {
    public struct Configuration: Sendable {
        public var resolution = H3.coverageResolution
        /// Stricter than `PointFilter`: a 50 m fix could put you on the wrong street.
        public var maxHorizontalAccuracy: Double = 40
        /// Never join fixes further apart in time than this (seconds)...
        public var maxGap: Double = 120
        /// ...or in space (metres).
        public var maxJump: Double = 500
        /// Sampling step along the line, metres. A third of a res-11 edge,
        /// so consecutive cells are always neighbours.
        public var step: Double = 8

        public init() {}
    }

    public struct Touch: Equatable, Sendable {
        public var cell: H3Cell
        public var timestamp: Double

        public init(cell: H3Cell, timestamp: Double) {
            self.cell = cell
            self.timestamp = timestamp
        }
    }

    public var configuration: Configuration
    private var last: LocationSample?
    private var lastCell: H3Cell?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Cells entered since the previous fix, in path order. A cell is
    /// reported again only after the path has left it.
    public mutating func add(_ sample: LocationSample) -> [Touch] {
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= configuration.maxHorizontalAccuracy else { return [] }
        var touches: [Touch] = []
        if let last,
           sample.timestamp - last.timestamp <= configuration.maxGap,
           Geo.distance(last.coordinate, sample.coordinate) <= configuration.maxJump {
            let distance = Geo.distance(last.coordinate, sample.coordinate)
            let steps = max(1, Int((distance / configuration.step).rounded(.up)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let point = Geo.interpolate(last.coordinate, sample.coordinate, fraction: t)
                let time = last.timestamp + (sample.timestamp - last.timestamp) * t
                emit(point, time, into: &touches)
            }
        } else {
            lastCell = nil
            emit(sample.coordinate, sample.timestamp, into: &touches)
        }
        last = sample
        return touches
    }

    /// Start a fresh trace: the next fix won't be joined to the previous one.
    public mutating func breakTrace() {
        last = nil
        lastCell = nil
    }

    private mutating func emit(_ point: GeoCoordinate, _ time: Double, into touches: inout [Touch]) {
        guard let cell = H3.cell(at: point, resolution: configuration.resolution), cell != lastCell else { return }
        touches.append(Touch(cell: cell, timestamp: time))
        lastCell = cell
    }
}

/// When a repeat visit to a cell counts as a new pass (for the heatmap).
public enum CellVisitRule {
    /// Walking back and forth on one block within half an hour is one pass.
    public static let newPassInterval: Double = 30 * 60

    public static func countsAsNewPass(lastVisit: Double?, now: Double) -> Bool {
        guard let lastVisit else { return true }
        return now - lastVisit >= newPassInterval
    }
}
