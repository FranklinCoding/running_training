import Foundation
import SwiftData

/// The app's long-lived objects. Created once, at launch, whether or not any
/// UI is shown (background relaunches have none).
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let store: RecordingStore
    let coverage: CoverageModel
    let permissions: Permissions
    let recorder: LocationRecorder

    private init() {
        do {
            // Stored in Application Support with iOS's default file protection
            // (readable after first unlock, so background recording can write to it).
            // Included in the user's iCloud/Finder device backups like other app data.
            container = try ModelContainer(for: PointBatch.self, ExploredCell.self, RecorderLogEntry.self)
        } catch {
            fatalError("Could not open the Reach database: \(error)")
        }
        store = RecordingStore(context: container.mainContext)
        coverage = CoverageModel(cells: store.allCells())
        permissions = Permissions()
        recorder = LocationRecorder(store: store, coverage: coverage)
    }
}
