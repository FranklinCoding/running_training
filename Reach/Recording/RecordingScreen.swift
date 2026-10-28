import CoreLocation
import MapKit
import ReachCore
import SwiftData
import SwiftUI

/// Recording controls plus the diagnostics needed to tune battery use in
/// Phase 1: current state, today's numbers, and the state-change log with
/// battery level at each change.
struct RecordingScreen: View {
    @Environment(LocationRecorder.self) private var recorder
    @Environment(Permissions.self) private var permissions
    @Environment(CoverageModel.self) private var coverage
    @Query(RecordingScreen.logDescriptor) private var log: [RecorderLogEntry]
    @State private var today = TodayStats()

    static var logDescriptor: FetchDescriptor<RecorderLogEntry> {
        var descriptor = FetchDescriptor<RecorderLogEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 300
        return descriptor
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Record my location", isOn: Binding(get: { recorder.isEnabled },
                                                               set: { recorder.setEnabled($0) }))
                    if !permissions.hasAlways {
                        Button(permissions.isLocationBlocked ? "Open Settings to allow location" : "Allow location all the time") {
                            permissions.requestLocation()
                        }
                    }
                } footer: {
                    Text("Your location history is stored only on this iPhone and in its device backups.")
                }

                Section("Now") {
                    LabeledContent("State", value: stateText)
                    LabeledContent("GPS profile", value: recorder.profile == .onFoot ? "On foot (best accuracy)" : "Vehicle (reduced accuracy)")
                    LabeledContent("Motion", value: recorder.lastMotion.rawValue.capitalized)
                    LabeledContent("Last fix", value: lastFixText)
                    LabeledContent("Location permission", value: permissionText)
                    LabeledContent("Motion permission", value: motionPermissionText)
                }

                Section("Today") {
                    LabeledContent("Fixes recorded", value: today.fixes.formatted())
                    LabeledContent("Distance", value: Measurement(value: today.metres / 1000, unit: UnitLength.kilometers)
                        .formatted(.measurement(width: .abbreviated, usage: .road)))
                    LabeledContent("Hexagons explored (all time)", value: coverage.cellCount.formatted())
                    NavigationLink("Today's raw track") {
                        TrackMapView(samples: today.samples)
                            .navigationTitle("Today's track")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .disabled(today.samples.isEmpty)
                }

                Section("Log") {
                    if log.isEmpty {
                        Text("Nothing yet").foregroundStyle(.secondary)
                    }
                    ForEach(log) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.kind.capitalized).font(.subheadline.weight(.semibold))
                                Spacer()
                                if let battery = entry.battery {
                                    Text(battery, format: .percent.precision(.fractionLength(0)))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Recording")
            .task(id: coverage.revision) { refreshToday() }
            .refreshable { refreshToday() }
        }
    }

    private func refreshToday() {
        recorder.flush()
        today = TodayStats(samples: AppServices.shared.store.samples(since: Calendar.current.startOfDay(for: .now)))
    }

    private var stateText: String {
        guard recorder.isRunning else { return "Off" }
        switch recorder.mode {
        case .off: return "Off"
        case .moving: return "Moving, GPS on"
        case .stationary: return "Still, GPS off"
        }
    }

    private var lastFixText: String {
        guard let s = recorder.lastSample else { return "None yet" }
        let date = Date(timeIntervalSince1970: s.timestamp)
        return "\(date.formatted(.relative(presentation: .named))), ±\(Int(s.horizontalAccuracy)) m"
    }

    private var permissionText: String {
        switch permissions.location {
        case .authorizedAlways: return permissions.isPrecise ? "Always, precise" : "Always, approximate"
        case .authorizedWhenInUse: return "While using the app"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not asked yet"
        }
    }

    private var motionPermissionText: String {
        guard MotionMonitor.isAvailable else { return "Not available" }
        switch permissions.motion {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not asked yet"
        }
    }
}

struct TodayStats {
    var samples: [LocationSample] = []
    var fixes: Int { samples.count }
    var metres: Double = 0

    init() {}

    init(samples: [LocationSample]) {
        self.samples = samples
        // Only count legs between closely spaced fixes, so GPS gaps don't add phantom distance.
        var total = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where b.timestamp - a.timestamp <= 120 {
            total += Geo.distance(a.coordinate, b.coordinate)
        }
        metres = total
    }
}

/// Raw fixes on a SwiftUI map, for checking what recording captured.
struct TrackMapView: View {
    let samples: [LocationSample]

    var body: some View {
        Map {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment)
                    .stroke(.blue, lineWidth: 3)
            }
            if let first = samples.first {
                Marker("Start", systemImage: "flag", coordinate: CLLocationCoordinate2D(first.coordinate))
                    .tint(.green)
            }
            if let last = samples.last {
                Marker("Latest", systemImage: "location", coordinate: CLLocationCoordinate2D(last.coordinate))
                    .tint(.red)
            }
        }
    }

    /// Split at GPS gaps and thin to keep the map responsive.
    private var segments: [[CLLocationCoordinate2D]] {
        let step = max(1, samples.count / 3000)
        var result: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var previous: LocationSample?
        for (i, s) in samples.enumerated() where i % step == 0 || i == samples.count - 1 {
            if let previous, s.timestamp - previous.timestamp > 120, !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(CLLocationCoordinate2D(s.coordinate))
            previous = s
        }
        if current.count > 1 { result.append(current) }
        return result
    }
}
