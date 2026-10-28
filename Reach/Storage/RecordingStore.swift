import Foundation
import SwiftData
import ReachCore
import os

/// Writes recorded fixes and explored cells to SwiftData.
@MainActor
final class RecordingStore {
    private static let logger = Logger(subsystem: "Reach", category: "Store")
    /// Flush buffered fixes after this many, or this many seconds, whichever comes first.
    private static let batchSize = 120
    private static let batchAge: Double = 120

    let context: ModelContext
    private var pending: [LocationSample] = []
    private var cells: [Int64: ExploredCell]?

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Fixes

    func append(_ sample: LocationSample) {
        pending.append(sample)
        if pending.count >= Self.batchSize || sample.timestamp - pending[0].timestamp >= Self.batchAge {
            flush()
        }
    }

    func flush() {
        if !pending.isEmpty {
            context.insert(PointBatch(samples: pending))
            pending.removeAll()
        }
        save()
    }

    func samples(since date: Date) -> [LocationSample] {
        let descriptor = FetchDescriptor<PointBatch>(predicate: #Predicate { $0.end >= date },
                                                     sortBy: [SortDescriptor(\.start)])
        let stored = (try? context.fetch(descriptor)) ?? []
        return stored.flatMap { $0.samples() }.filter { $0.timestamp >= date.timeIntervalSince1970 }
            + pending.filter { $0.timestamp >= date.timeIntervalSince1970 }
    }

    // MARK: Cells

    func allCells() -> [H3Cell] {
        loadCells().keys.map { H3Cell(bitPattern: $0) }
    }

    /// Records cell touches. Returns the cells explored for the first time.
    func record(_ touches: [CoverageTracer.Touch]) -> [H3Cell] {
        var known = loadCells()
        var firstTime: [H3Cell] = []
        for touch in touches {
            let id = Int64(bitPattern: touch.cell)
            let date = Date(timeIntervalSince1970: touch.timestamp)
            if let cell = known[id] {
                if CellVisitRule.countsAsNewPass(lastVisit: cell.lastVisited.timeIntervalSince1970, now: touch.timestamp) {
                    cell.passes += 1
                }
                cell.lastVisited = max(cell.lastVisited, date)
            } else {
                let cell = ExploredCell(cell: touch.cell, date: date)
                context.insert(cell)
                known[id] = cell
                firstTime.append(touch.cell)
            }
        }
        cells = known
        return firstTime
    }

    private func loadCells() -> [Int64: ExploredCell] {
        if let cells { return cells }
        let all = (try? context.fetch(FetchDescriptor<ExploredCell>())) ?? []
        let loaded = Dictionary(all.map { ($0.cellID, $0) }, uniquingKeysWith: { a, _ in a })
        cells = loaded
        return loaded
    }

    // MARK: Log

    func log(_ kind: String, _ message: String, battery: Double?) {
        context.insert(RecorderLogEntry(kind: kind, message: message, battery: battery))
        Self.logger.info("\(kind, privacy: .public): \(message, privacy: .public)")
    }

    func pruneLog(olderThan cutoff: Date) {
        do {
            try context.delete(model: RecorderLogEntry.self, where: #Predicate { $0.date < cutoff })
        } catch {
            Self.logger.error("Pruning the log failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Self.logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
