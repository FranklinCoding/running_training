import ReachCore
import SwiftUI

struct ExploredMapScreen: View {
    @Environment(CoverageModel.self) private var coverage
    @Environment(LocationRecorder.self) private var recorder

    var body: some View {
        ExploredMapView(overlay: coverage.overlay, revision: coverage.revision)
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coverage.exploredSquareKilometres, format: .number.precision(.fractionLength(2)))
                            .font(.title2.weight(.semibold).monospacedDigit())
                        + Text(" km² explored").font(.subheadline)
                        Text("\(coverage.cellCount.formatted()) hexagons")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    RecordingBadge(mode: recorder.isRunning ? recorder.mode : .off)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
    }
}

struct RecordingBadge: View {
    let mode: TrackingMode

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .accessibilityLabel("Recording status: \(title)")
    }

    private var title: String {
        switch mode {
        case .off: return "Not recording"
        case .moving: return "Recording"
        case .stationary: return "Paused, you're still"
        }
    }

    private var symbol: String {
        switch mode {
        case .off: return "location.slash"
        case .moving: return "location.fill"
        case .stationary: return "pause.circle"
        }
    }

    private var tint: Color {
        switch mode {
        case .off: return .secondary
        case .moving: return .green
        case .stationary: return .orange
        }
    }
}
