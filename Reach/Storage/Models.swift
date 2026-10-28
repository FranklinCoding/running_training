import Foundation
import SwiftData
import ReachCore

/// A run of raw fixes, packed with `PointCodec`. One row per ~2 minutes of
/// moving instead of one row per fix.
@Model
final class PointBatch {
    var start: Date
    var end: Date
    var count: Int
    var payload: Data

    init(samples: [LocationSample]) {
        start = Date(timeIntervalSince1970: samples.first?.timestamp ?? 0)
        end = Date(timeIntervalSince1970: samples.last?.timestamp ?? 0)
        count = samples.count
        payload = PointCodec.encode(samples)
    }

    func samples() -> [LocationSample] {
        (try? PointCodec.decode(payload)) ?? []
    }
}

/// An H3 cell (resolution 11) the user has passed through.
@Model
final class ExploredCell {
    /// The H3 index, bit-cast to a signed integer because SwiftData has no UInt64.
    @Attribute(.unique) var cellID: Int64
    /// Separate passes through the cell, for the heatmap. See `CellVisitRule`.
    var passes: Int
    var firstVisited: Date
    var lastVisited: Date

    init(cell: H3Cell, date: Date) {
        cellID = Int64(bitPattern: cell)
        passes = 1
        firstVisited = date
        lastVisited = date
    }

    var cell: H3Cell { H3Cell(bitPattern: cellID) }
}

/// Recording diagnostics shown on the Recording tab: state changes, wakeups
/// and battery level. Pruned after two weeks.
@Model
final class RecorderLogEntry {
    var date: Date
    var kind: String
    var message: String
    /// 0...1, or nil when unknown (e.g. in the simulator).
    var battery: Double?

    init(date: Date = .now, kind: String, message: String, battery: Double?) {
        self.date = date
        self.kind = kind
        self.message = message
        self.battery = battery
    }
}
