import Observation
import ReachCore

/// Explored cells for the map, kept in step with `RecordingStore`.
@Observable
@MainActor
final class CoverageModel {
    private(set) var cellCount: Int
    /// Bumped whenever cells are added, so the map knows to redraw.
    private(set) var revision = 0
    let overlay = HexOverlay()

    init(cells: [H3Cell]) {
        overlay.add(cells)
        cellCount = cells.count
    }

    func add(_ cells: [H3Cell]) {
        guard !cells.isEmpty else { return }
        overlay.add(cells)
        cellCount += cells.count
        revision += 1
    }

    var exploredSquareKilometres: Double {
        Double(cellCount) * H3.averageArea() / 1_000_000
    }
}
