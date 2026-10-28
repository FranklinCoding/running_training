import SwiftUI
import SwiftData

@main
struct ReachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.recorder)
                .environment(services.coverage)
                .environment(services.permissions)
        }
        .modelContainer(services.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                services.permissions.refresh()
                services.recorder.startIfAuthorized()
            case .background:
                services.recorder.flush()
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // iOS relaunches the app in the background for geofence exits, visits and
        // significant location changes. Recording has to resume here, before (and
        // often without) any UI.
        let services = AppServices.shared
        if launchOptions?[.location] != nil {
            services.recorder.log("launch", "Relaunched in the background for a location event")
        }
        services.store.pruneLog(olderThan: Date().addingTimeInterval(-14 * 24 * 3600))
        services.recorder.startIfAuthorized()
        return true
    }
}
