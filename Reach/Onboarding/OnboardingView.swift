import SwiftUI

/// First-run explanation and permission requests. App Review checks that
/// Always location is clearly justified before it's requested, so the
/// "why" comes before every prompt.
struct OnboardingView: View {
    @Environment(Permissions.self) private var permissions
    let onFinish: () -> Void
    @State private var step = Step.welcome

    enum Step: Int, CaseIterable {
        case welcome, location, motion, privacy
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: symbol)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 48)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.largeTitle.bold())
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    Text(primaryTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if let secondaryTitle {
                    Button(secondaryTitle, action: advance)
                        .controlSize(.large)
                }
                PageDots(count: Step.allCases.count, current: step.rawValue)
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .onChange(of: permissions.location) { _, _ in
            if step == .location, permissions.hasAlways { advance() }
        }
        .onChange(of: permissions.motion) { _, _ in
            if step == .motion, permissions.isMotionDecided { advance() }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Content

    private var symbol: String {
        switch step {
        case .welcome: return "hexagon.fill"
        case .location: return "location.fill"
        case .motion: return "figure.walk.motion"
        case .privacy: return "lock.fill"
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "See how much of New York you've explored"
        case .location: return "Location, all the time"
        case .motion: return "Motion & Fitness"
        case .privacy: return "Your map stays yours"
        }
    }

    private var paragraphs: [String] {
        switch step {
        case .welcome:
            return [
                "Reach quietly records where you go and paints it onto a map of the city, so you can see the streets you know and the blank spots you haven't been to yet.",
                "Carry your phone as usual. There's nothing to start or stop.",
            ]
        case .location:
            return [
                "To fill in your map without you opening the app, Reach needs to use your location in the background. iOS calls this \"Always\" access.",
                "Choose \"Allow While Using App\" first. iOS will then ask whether to \"Change to Always Allow\". Choose that too.",
                "To save battery, Reach turns GPS off whenever you're standing still and only turns it back on when you move.",
                "With \"While Using\" only, your map only fills in while Reach is open on screen.",
            ]
        case .motion:
            return [
                "Motion data lets Reach tell walking from riding, and notice when you've stopped so it can switch GPS off sooner.",
                "It's processed on your iPhone and never leaves it.",
            ]
        case .privacy:
            return [
                "Reach has no account, no servers and no analytics. Your location history is never sent to us or anyone else.",
                "It's stored on this iPhone, and included in your iPhone's own encrypted backups so it survives moving to a new phone.",
                "You can pause recording at any time from the Recording tab.",
            ]
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Continue"
        case .location:
            if permissions.hasAlways { return "Continue" }
            if permissions.isLocationBlocked { return "Open Settings" }
            if permissions.hasAnyLocation { return "Change to Always" }
            return "Allow location access"
        case .motion:
            return permissions.isMotionDecided ? "Continue" : "Allow motion access"
        case .privacy: return "Start exploring"
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case .location where !permissions.hasAlways: return "Not now"
        case .motion where !permissions.isMotionDecided: return "Not now"
        default: return nil
        }
    }

    // MARK: Actions

    private func primaryAction() {
        switch step {
        case .location where !permissions.hasAlways:
            permissions.requestLocation()
        case .motion where !permissions.isMotionDecided:
            permissions.requestMotion()
        default:
            advance()
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        withAnimation { step = next }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
